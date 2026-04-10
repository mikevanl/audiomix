import AppKit
import CoreAudio
import Observation
import os

private let logger = Logger(subsystem: "com.audiomix.AudioMix", category: "ProcessMonitor")

private let ignoredBundleIDPrefixes: Set<String> = [
    "com.apple.audio",
    "com.apple.coreaudio",
    "com.apple.systemsound",
]

@Observable
@MainActor
final class AudioProcessMonitor {
    var activeApps: [AudioApp] = []
    var isMonitoring = false

    private var pollingTask: Task<Void, Never>?
    private let pollingInterval: Duration = .seconds(2)

    func start() {
        guard !isMonitoring else { return }
        isMonitoring = true
        logger.info("Starting audio process monitor")

        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: self?.pollingInterval ?? .seconds(2))
            }
        }
    }

    func stop() {
        guard isMonitoring else { return }
        isMonitoring = false
        pollingTask?.cancel()
        pollingTask = nil
        logger.info("Stopped audio process monitor")
    }

    private func refresh() {
        let processObjectIDs = AudioObjectID.systemProcessList()
        let ownPID = ProcessInfo.processInfo.processIdentifier

        // Group AudioObjectIDs by PID and track output activity
        var pidToObjectIDs: [pid_t: [AudioObjectID]] = [:]
        var pidIsActive: [pid_t: Bool] = [:]

        for objectID in processObjectIDs {
            guard let pid = objectID.processPID(), pid != ownPID else { continue }

            let bundleID = objectID.processBundleID() ?? ""
            if ignoredBundleIDPrefixes.contains(where: { bundleID.hasPrefix($0) }) {
                continue
            }

            pidToObjectIDs[pid, default: []].append(objectID)
            if objectID.processIsRunningOutput() {
                pidIsActive[pid] = true
            }
        }

        // Resolve PIDs to AudioApp models
        var apps: [AudioApp] = []
        for (pid, objectIDs) in pidToObjectIDs {
            let isActive = pidIsActive[pid] ?? false

            guard let app = NSRunningApplication(processIdentifier: pid) else { continue }
            guard !app.isTerminated else { continue }

            let name = app.localizedName ?? objectIDs.first?.processBundleID() ?? "Unknown"
            let icon = app.icon ?? NSWorkspace.shared.icon(for: .applicationBundle)
            let bundleID = app.bundleIdentifier ?? objectIDs.first?.processBundleID()

            apps.append(AudioApp(
                id: pid,
                audioObjectIDs: objectIDs,
                name: name,
                icon: icon,
                bundleID: bundleID,
                isOutputActive: isActive
            ))
        }

        apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let currentPIDs = Set(activeApps.map(\.id))
        let newPIDs = Set(apps.map(\.id))
        let activeChanged = Set(activeApps.filter(\.isOutputActive).map(\.id))
            != Set(apps.filter(\.isOutputActive).map(\.id))

        if currentPIDs != newPIDs || activeChanged {
            activeApps = apps
            logger.debug("Updated app list: \(apps.count) apps, \(apps.filter(\.isOutputActive).count) active")
        }
    }
}
