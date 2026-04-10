import AppKit
import CoreAudio
import Observation
import os

private let logger = Logger(subsystem: "com.audiomix.AudioMix", category: "TapManager")

@Observable
@MainActor
final class AudioTapManager {
    private(set) var sessions: [pid_t: AudioTapSession] = [:]
    private(set) var volumes: [pid_t: Float32] = [:]
    private(set) var muted: [pid_t: Bool] = [:]
    private(set) var displayLevels: [pid_t: Float32] = [:]
    private(set) var availableOutputDevices: [OutputDevice] = []
    private(set) var appOutputDeviceUIDs: [pid_t: String] = [:]
    var permissionDenied = false
    var onDeviceListChanged: ((_ connected: [OutputDevice], _ disconnected: [OutputDevice]) -> Void)?

    private var defaultOutputDeviceID: AudioObjectID
    private var outputDeviceListenerBlock: AudioObjectPropertyListenerBlock?
    private var deviceListListenerBlock: AudioObjectPropertyListenerBlock?
    private var workspaceObserver: NSObjectProtocol?
    private var lastKnownDeviceUIDs: Set<String> = []

    init() {
        defaultOutputDeviceID = AudioObjectID.defaultOutputDevice()
        availableOutputDevices = OutputDevice.allAvailable()
        lastKnownDeviceUIDs = Set(availableOutputDevices.map(\.uid))
        installOutputDeviceListener()
        installDeviceListListener()
        installWorkspaceObserver()
    }

    nonisolated deinit {
        // Sessions and listeners are cleaned up by their own deinit/dealloc.
        // For explicit cleanup, call teardownAll() before releasing.
    }

    // MARK: - Sync with Monitor

    func syncWithApps(_ apps: [AudioApp]) {
        let currentPIDs = Set(sessions.keys)
        let incomingPIDs = Set(apps.map(\.id))

        for pid in currentPIDs.subtracting(incomingPIDs) {
            destroySession(for: pid)
        }

        for app in apps where !currentPIDs.contains(app.id) {
            createSession(for: app)
        }
    }

    // MARK: - Volume & Mute Control

    func volume(for pid: pid_t) -> Float32 {
        volumes[pid] ?? 1.0
    }

    func isMuted(for pid: pid_t) -> Bool {
        muted[pid] ?? false
    }

    func setVolume(_ value: Float32, for pid: pid_t) {
        let clamped = max(0.0, min(1.0, value))
        volumes[pid] = clamped
        sessions[pid]?.setVolume(clamped)
    }

    func setMuted(_ value: Bool, for pid: pid_t) {
        muted[pid] = value
        sessions[pid]?.setMuted(value)
    }

    // MARK: - Level Metering

    func level(for pid: pid_t) -> Float32 {
        displayLevels[pid] ?? 0.0
    }

    func updateDisplayLevels() {
        let decayFactor: Float32 = 0.85
        for (pid, session) in sessions {
            let currentRMS = session.readLevel()
            let previous = displayLevels[pid] ?? 0.0
            let smoothed = max(currentRMS, previous * decayFactor)
            displayLevels[pid] = smoothed < 0.001 ? 0.0 : smoothed
        }
    }

    // MARK: - Output Device Routing

    func outputDeviceUID(for pid: pid_t) -> String? {
        appOutputDeviceUIDs[pid]
    }

    func setOutputDevice(uid: String?, for pid: pid_t) {
        if let uid {
            appOutputDeviceUIDs[pid] = uid
        } else {
            appOutputDeviceUIDs.removeValue(forKey: pid)
        }

        guard sessions[pid] != nil else { return }
        recreateSession(for: pid)
    }

    func teardownAll() {
        for pid in sessions.keys {
            sessions[pid]?.stop()
        }
        sessions.removeAll()
        displayLevels.removeAll()
    }

    // MARK: - Private: Session Lifecycle

    private func resolvedOutputDeviceID(for pid: pid_t) -> AudioObjectID {
        guard let uid = appOutputDeviceUIDs[pid],
              let device = availableOutputDevices.first(where: { $0.uid == uid }) else {
            return defaultOutputDeviceID
        }
        return device.id
    }

    private func createSession(for app: AudioApp) {
        let session = AudioTapSession(pid: app.id, audioObjectIDs: app.audioObjectIDs)

        let vol = volumes[app.id] ?? 1.0
        let mute = muted[app.id] ?? false
        session.setVolume(vol)
        session.setMuted(mute)

        do {
            try session.start(outputDeviceID: resolvedOutputDeviceID(for: app.id))
            sessions[app.id] = session
            volumes[app.id] = vol
            muted[app.id] = mute
            logger.debug("Created tap session for \(app.name) (PID \(app.id))")
        } catch {
            let status = (error as? CoreAudioError).flatMap {
                if case .readFailed(let s) = $0 { return s }
                return nil
            }
            if let s = status, s == -17001 || s == -17002 {
                permissionDenied = true
                logger.error("Audio capture permission denied")
            } else {
                logger.error("Failed to create tap for \(app.name) (PID \(app.id)): \(error.localizedDescription)")
            }
        }
    }

    private func recreateSession(for pid: pid_t) {
        guard let existingSession = sessions[pid] else { return }
        let audioObjectIDs = existingSession.audioObjectIDs

        destroySession(for: pid)

        let session = AudioTapSession(pid: pid, audioObjectIDs: audioObjectIDs)
        let vol = volumes[pid] ?? 1.0
        let mute = muted[pid] ?? false
        session.setVolume(vol)
        session.setMuted(mute)

        do {
            try session.start(outputDeviceID: resolvedOutputDeviceID(for: pid))
            sessions[pid] = session
            logger.debug("Recreated tap session for PID \(pid)")
        } catch {
            logger.error("Failed to recreate tap for PID \(pid): \(error.localizedDescription)")
        }
    }

    private func destroySession(for pid: pid_t) {
        sessions[pid]?.stop()
        sessions.removeValue(forKey: pid)
        displayLevels.removeValue(forKey: pid)
        logger.debug("Destroyed tap session for PID \(pid)")
    }

    // MARK: - Default Output Device Listener

    private func installOutputDeviceListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.handleDefaultOutputDeviceChange()
            }
        }
        outputDeviceListenerBlock = block

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
    }

    private func handleDefaultOutputDeviceChange() {
        let newDeviceID = AudioObjectID.defaultOutputDevice()
        guard newDeviceID != defaultOutputDeviceID else { return }

        logger.info("Default output device changed from \(self.defaultOutputDeviceID) to \(newDeviceID)")
        defaultOutputDeviceID = newDeviceID

        // Only recreate sessions following system default (no explicit routing override)
        let defaultFollowers = sessions.filter { appOutputDeviceUIDs[$0.key] == nil }
        for (pid, _) in defaultFollowers {
            recreateSession(for: pid)
        }
    }

    // MARK: - Device List Listener

    private func installDeviceListListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.handleDeviceListChange()
            }
        }
        deviceListListenerBlock = block

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
    }

    private func handleDeviceListChange() {
        let newDevices = OutputDevice.allAvailable()
        let newUIDs = Set(newDevices.map(\.uid))

        guard newUIDs != lastKnownDeviceUIDs else { return }

        let previousDevices = availableOutputDevices
        let previousUIDs = lastKnownDeviceUIDs
        lastKnownDeviceUIDs = newUIDs
        availableOutputDevices = newDevices
        logger.info("Device list changed: \(newDevices.count) output devices")

        // Handle disconnected routed devices — fall back to default
        for (pid, uid) in appOutputDeviceUIDs {
            if !newUIDs.contains(uid) {
                logger.warning("Routed device \(uid) disconnected for PID \(pid), falling back to default")
                appOutputDeviceUIDs.removeValue(forKey: pid)
                if sessions[pid] != nil {
                    recreateSession(for: pid)
                }
            }
        }

        // Notify rules engine
        let connected = newDevices.filter { !previousUIDs.contains($0.uid) }
        let disconnected = previousDevices.filter { !newUIDs.contains($0.uid) }
        if !connected.isEmpty || !disconnected.isEmpty {
            onDeviceListChanged?(connected, disconnected)
        }
    }

    // MARK: - Workspace Observer

    private func installWorkspaceObserver() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            Task { @MainActor [weak self] in
                if self?.sessions[pid] != nil {
                    self?.destroySession(for: pid)
                }
            }
        }
    }
}
