import AudioMixKit
import CoreAudio
import Foundation
import Network
import os

private let logger = Logger(subsystem: "com.audiomix.AudioMix", category: "IPCServer")

@MainActor
final class IPCServer {
    private let tapManager: AudioTapManager
    private let monitor: AudioProcessMonitor
    private let rulesEngine: RulesEngine
    private var listener: NWListener?
    private let socketPath = IPCConstants.socketPath

    init(tapManager: AudioTapManager, monitor: AudioProcessMonitor, rulesEngine: RulesEngine) {
        self.tapManager = tapManager
        self.monitor = monitor
        self.rulesEngine = rulesEngine
    }

    func start() {
        let dir = IPCConstants.supportDirectory
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        unlink(socketPath)

        do {
            let params = NWParameters()
            params.requiredLocalEndpoint = NWEndpoint.unix(path: socketPath)
            listener = try NWListener(using: params)
        } catch {
            logger.error("Failed to create IPC listener: \(error.localizedDescription)")
            return
        }

        listener?.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.handleConnection(connection)
            }
        }

        listener?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                logger.info("IPC server listening on \(IPCConstants.socketPath)")
            case .failed(let error):
                logger.error("IPC listener failed: \(error.localizedDescription)")
            default:
                break
            }
        }

        listener?.start(queue: .main)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        unlink(socketPath)
        logger.info("IPC server stopped")
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)
        receiveRequest(on: connection, buffer: Data())
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self else { return }

            var accumulated = buffer
            if let content { accumulated.append(content) }

            if accumulated.contains(0x0A) {
                let lineEnd = accumulated.firstIndex(of: 0x0A)!
                let lineData = accumulated[accumulated.startIndex..<lineEnd]

                Task { @MainActor in
                    let response: IPCResponse
                    if let request = try? JSONDecoder().decode(IPCRequest.self, from: lineData) {
                        response = self.handleRequest(request)
                    } else {
                        response = .failure("Invalid request JSON")
                    }

                    var responseData = (try? JSONEncoder().encode(response)) ?? Data()
                    responseData.append(0x0A)
                    connection.send(content: responseData, completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                }
            } else if isComplete || error != nil {
                connection.cancel()
            } else {
                Task { @MainActor in
                    self.receiveRequest(on: connection, buffer: accumulated)
                }
            }
        }
    }

    // MARK: - Command Dispatch

    private func handleRequest(_ request: IPCRequest) -> IPCResponse {
        switch request.command {
        case "list":
            return handleList(activeOnly: request.activeOnly ?? false)
        case "volume":
            return handleVolume(appID: request.app, value: request.value)
        case "mute":
            return handleMute(appID: request.app, state: request.state)
        case "route":
            return handleRoute(appID: request.app, device: request.device, reset: request.reset ?? false)
        case "devices":
            return handleDevices()
        case "active":
            return handleList(activeOnly: true)
        case "rules_list":
            return handleRulesList()
        case "rules_add":
            return handleRulesAdd(json: request.ruleJSON)
        case "rules_remove":
            return handleRulesRemove(id: request.ruleID)
        default:
            return .failure("Unknown command: \(request.command)")
        }
    }

    private func handleList(activeOnly: Bool) -> IPCResponse {
        var apps = monitor.activeApps
        if activeOnly {
            apps = apps.filter(\.isOutputActive)
        }
        return .success(apps: apps.map { makeSnapshot($0) })
    }

    private func handleVolume(appID: String?, value: Int?) -> IPCResponse {
        guard let appID, let pid = resolveApp(appID) else {
            return .failure("No audio app found matching '\(appID ?? "")'")
        }

        if let value {
            let clamped = max(0, min(100, value))
            tapManager.setVolume(Float32(clamped) / 100.0, for: pid)
        }

        guard let app = monitor.activeApps.first(where: { $0.id == pid }) else {
            return .failure("App no longer active")
        }
        return .success(app: makeSnapshot(app))
    }

    private func handleMute(appID: String?, state: String?) -> IPCResponse {
        guard let appID, let pid = resolveApp(appID) else {
            return .failure("No audio app found matching '\(appID ?? "")'")
        }

        switch state {
        case "on": tapManager.setMuted(true, for: pid)
        case "off": tapManager.setMuted(false, for: pid)
        default: tapManager.setMuted(!tapManager.isMuted(for: pid), for: pid)
        }

        guard let app = monitor.activeApps.first(where: { $0.id == pid }) else {
            return .failure("App no longer active")
        }
        return .success(app: makeSnapshot(app))
    }

    private func handleRoute(appID: String?, device: String?, reset: Bool) -> IPCResponse {
        guard let appID, let pid = resolveApp(appID) else {
            return .failure("No audio app found matching '\(appID ?? "")'")
        }

        if reset {
            tapManager.setOutputDevice(uid: nil, for: pid)
        } else if let device {
            let match = tapManager.availableOutputDevices.first {
                $0.name.localizedCaseInsensitiveCompare(device) == .orderedSame || $0.uid == device
            }
            guard let match else {
                return .failure("No output device found matching '\(device)'")
            }
            tapManager.setOutputDevice(uid: match.uid, for: pid)
        }

        guard let app = monitor.activeApps.first(where: { $0.id == pid }) else {
            return .failure("App no longer active")
        }
        return .success(app: makeSnapshot(app))
    }

    private func handleDevices() -> IPCResponse {
        let defaultUID = AudioObjectID.defaultOutputDeviceUID()
        let snapshots = tapManager.availableOutputDevices.map {
            DeviceSnapshot(uid: $0.uid, name: $0.name, isDefault: $0.uid == defaultUID)
        }
        return .success(devices: snapshots)
    }

    // MARK: - Rules

    private func handleRulesList() -> IPCResponse {
        let snapshots = rulesEngine.listRules().map { RuleSnapshot(rule: $0) }
        return .success(rules: snapshots)
    }

    private func handleRulesAdd(json: String?) -> IPCResponse {
        guard let json, let data = json.data(using: .utf8) else {
            return .failure("Missing or invalid rule JSON")
        }

        do {
            // Support both single rule and array of rules
            if let rules = try? JSONDecoder().decode([Rule].self, from: data) {
                for rule in rules {
                    rulesEngine.addRule(rule)
                }
                let snapshots = rules.map { RuleSnapshot(rule: $0) }
                return .success(rules: snapshots)
            } else {
                let rule = try JSONDecoder().decode(Rule.self, from: data)
                rulesEngine.addRule(rule)
                return .success(rules: [RuleSnapshot(rule: rule)])
            }
        } catch {
            return .failure("Invalid rule JSON: \(error.localizedDescription)")
        }
    }

    private func handleRulesRemove(id: String?) -> IPCResponse {
        guard let id else {
            return .failure("Missing rule ID")
        }
        if rulesEngine.removeRule(id: id) {
            return IPCResponse(ok: true)
        } else {
            return .failure("No rule found with ID '\(id)'")
        }
    }

    // MARK: - Helpers

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

    private func makeSnapshot(_ app: AudioApp) -> AppSnapshot {
        let deviceUID = tapManager.outputDeviceUID(for: app.id)
        let deviceName = deviceUID.flatMap { uid in
            tapManager.availableOutputDevices.first(where: { $0.uid == uid })?.name
        }
        return AppSnapshot(
            pid: app.id,
            name: app.name,
            bundleID: app.bundleID,
            volume: Int(tapManager.volume(for: app.id) * 100),
            muted: tapManager.isMuted(for: app.id),
            active: app.isOutputActive,
            outputDevice: deviceName
        )
    }
}
