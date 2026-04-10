import AudioMixKit
import Foundation
import Observation
import os

private let logger = Logger(subsystem: "com.audiomix.AudioMix", category: "RulesEngine")

struct RuleEvent {
    let type: RuleTriggerType
    let deviceName: String?
    let appName: String?
    let appBundleID: String?

    init(type: RuleTriggerType, deviceName: String? = nil, appName: String? = nil, appBundleID: String? = nil) {
        self.type = type
        self.deviceName = deviceName
        self.appName = appName
        self.appBundleID = appBundleID
    }
}

@Observable
@MainActor
final class RulesEngine {
    private let tapManager: AudioTapManager
    private let monitor: AudioProcessMonitor
    private(set) var rules: [Rule] = []
    private let filePath: String

    private var knownAppPIDs: Set<pid_t> = []
    private var knownAppNames: [pid_t: (name: String, bundleID: String?)] = [:]
    private var hasInitializedAppTracking = false

    init(tapManager: AudioTapManager, monitor: AudioProcessMonitor) {
        self.tapManager = tapManager
        self.monitor = monitor
        self.filePath = IPCConstants.supportDirectory + "/rules.json"
    }

    // MARK: - Storage

    func loadRules() {
        guard FileManager.default.fileExists(atPath: filePath) else {
            logger.info("No rules file found, starting with empty rules")
            return
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
            rules = try JSONDecoder().decode([Rule].self, from: data)
            logger.info("Loaded \(self.rules.count) rules")
        } catch {
            logger.error("Failed to load rules: \(error.localizedDescription)")
            rules = []
        }
    }

    private func saveRules() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(rules)
            try data.write(to: URL(fileURLWithPath: filePath), options: .atomic)
            logger.debug("Saved \(self.rules.count) rules")
        } catch {
            logger.error("Failed to save rules: \(error.localizedDescription)")
        }
    }

    // MARK: - Rule Management

    func addRule(_ rule: Rule) {
        rules.append(rule)
        saveRules()
        logger.info("Added rule \(rule.id): \(rule.trigger.type.rawValue) → \(rule.action.type.rawValue)")
    }

    func removeRule(id: String) -> Bool {
        let before = rules.count
        rules.removeAll { $0.id == id }
        if rules.count < before {
            saveRules()
            logger.info("Removed rule \(id)")
            return true
        }
        return false
    }

    func listRules() -> [Rule] {
        rules
    }

    // MARK: - Event Evaluation

    func evaluate(event: RuleEvent) {
        for rule in rules where rule.enabled {
            guard rule.trigger.type == event.type else { continue }
            guard matchesTrigger(rule.trigger, event: event) else { continue }
            logger.info("Rule \(rule.id) matched event \(event.type.rawValue)")
            execute(rule.action)
        }
    }

    func handleAppListUpdate(_ apps: [AudioApp]) {
        let currentPIDs = Set(apps.map(\.id))

        if hasInitializedAppTracking {
            for pid in currentPIDs.subtracting(knownAppPIDs) {
                if let app = apps.first(where: { $0.id == pid }) {
                    evaluate(event: RuleEvent(type: .appLaunched, appName: app.name, appBundleID: app.bundleID))
                }
            }
            for pid in knownAppPIDs.subtracting(currentPIDs) {
                if let names = knownAppNames[pid] {
                    evaluate(event: RuleEvent(type: .appQuit, appName: names.name, appBundleID: names.bundleID))
                }
            }
        } else {
            hasInitializedAppTracking = true
        }

        knownAppPIDs = currentPIDs
        knownAppNames = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, ($0.name, $0.bundleID)) })
    }

    // MARK: - Private

    private func matchesTrigger(_ trigger: RuleTrigger, event: RuleEvent) -> Bool {
        switch trigger.type {
        case .deviceConnected, .deviceDisconnected:
            guard let triggerDevice = trigger.device, let eventDevice = event.deviceName else { return false }
            return triggerDevice.localizedCaseInsensitiveCompare(eventDevice) == .orderedSame

        case .appLaunched, .appQuit:
            guard let triggerApp = trigger.app else { return false }
            if let eventName = event.appName,
               triggerApp.localizedCaseInsensitiveCompare(eventName) == .orderedSame {
                return true
            }
            if let eventBundleID = event.appBundleID,
               triggerApp.localizedCaseInsensitiveCompare(eventBundleID) == .orderedSame {
                return true
            }
            return false
        }
    }

    private func execute(_ action: RuleAction) {
        guard let pid = resolveApp(action.app) else {
            logger.warning("Rule action target '\(action.app)' not found among active apps")
            return
        }

        switch action.type {
        case .route:
            guard let deviceName = action.device else {
                logger.warning("Route action missing device name")
                return
            }
            let match = tapManager.availableOutputDevices.first {
                $0.name.localizedCaseInsensitiveCompare(deviceName) == .orderedSame
            }
            guard let match else {
                logger.warning("Route target device '\(deviceName)' not available")
                return
            }
            tapManager.setOutputDevice(uid: match.uid, for: pid)
            logger.info("Rule routed \(action.app) to \(deviceName)")

        case .mute:
            tapManager.setMuted(true, for: pid)
            logger.info("Rule muted \(action.app)")

        case .unmute:
            tapManager.setMuted(false, for: pid)
            logger.info("Rule unmuted \(action.app)")

        case .setVolume:
            guard let vol = action.volume else {
                logger.warning("set_volume action missing volume value")
                return
            }
            tapManager.setVolume(Float32(max(0, min(100, vol))) / 100.0, for: pid)
            logger.info("Rule set volume of \(action.app) to \(vol)%")
        }
    }

    private func resolveApp(_ identifier: String) -> pid_t? {
        if let pid = Int32(identifier) {
            return monitor.activeApps.contains(where: { $0.id == pid }) ? pid : nil
        }
        if identifier.contains(".") {
            return monitor.activeApps.first {
                $0.bundleID?.localizedCaseInsensitiveCompare(identifier) == .orderedSame
            }?.id
        }
        return monitor.activeApps.first {
            $0.name.localizedCaseInsensitiveCompare(identifier) == .orderedSame
        }?.id
    }
}
