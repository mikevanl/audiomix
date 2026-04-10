import CoreAudio
import Foundation
import os

private let logger = Logger(subsystem: "com.audiomix.AudioMix", category: "CoreAudio")

enum CoreAudioError: Error {
    case propertyNotSupported
    case readFailed(OSStatus)
    case sizeMismatch
}

extension AudioObjectID {

    // MARK: - Generic Property Readers

    func read<T>(_ selector: AudioObjectPropertySelector,
                 scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) throws -> T {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(self, &address) else {
            throw CoreAudioError.propertyNotSupported
        }

        var dataSize = UInt32(MemoryLayout<T>.size)
        var value = UnsafeMutableRawPointer.allocate(byteCount: Int(dataSize), alignment: MemoryLayout<T>.alignment)
        defer { value.deallocate() }

        let status = AudioObjectGetPropertyData(self, &address, 0, nil, &dataSize, value)
        guard status == noErr else {
            throw CoreAudioError.readFailed(status)
        }

        return value.assumingMemoryBound(to: T.self).pointee
    }

    func readArray<T>(_ selector: AudioObjectPropertySelector,
                      scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) throws -> [T] {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(self, &address) else {
            throw CoreAudioError.propertyNotSupported
        }

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(self, &address, 0, nil, &dataSize)
        guard status == noErr else {
            throw CoreAudioError.readFailed(status)
        }

        let count = Int(dataSize) / MemoryLayout<T>.size
        guard count > 0 else { return [] }

        var array = [T](repeating: unsafeBitCast(0, to: T.self), count: count)
        status = AudioObjectGetPropertyData(self, &address, 0, nil, &dataSize, &array)
        guard status == noErr else {
            throw CoreAudioError.readFailed(status)
        }

        return array
    }

    func readString(_ selector: AudioObjectPropertySelector,
                    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(self, &address) else { return nil }

        var dataSize = UInt32(MemoryLayout<CFString>.size)
        var value: CFString = "" as CFString

        let status = AudioObjectGetPropertyData(self, &address, 0, nil, &dataSize, &value)
        guard status == noErr else { return nil }

        return value as String
    }

    // MARK: - System-Level Queries

    static func systemProcessList() -> [AudioObjectID] {
        do {
            return try AudioObjectID(kAudioObjectSystemObject).readArray(kAudioHardwarePropertyProcessObjectList)
        } catch {
            logger.error("Failed to read process list: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Per-Process Queries

    func processPID() -> pid_t? {
        do {
            return try read(kAudioProcessPropertyPID)
        } catch {
            return nil
        }
    }

    func processBundleID() -> String? {
        readString(kAudioProcessPropertyBundleID)
    }

    func processIsRunningOutput() -> Bool {
        do {
            let value: UInt32 = try read(kAudioProcessPropertyIsRunningOutput)
            return value != 0
        } catch {
            return false
        }
    }

    // MARK: - Default Output Device

    static func defaultOutputDevice() -> AudioObjectID {
        do {
            return try AudioObjectID(kAudioObjectSystemObject).read(kAudioHardwarePropertyDefaultOutputDevice)
        } catch {
            logger.error("Failed to read default output device: \(error.localizedDescription)")
            return kAudioObjectUnknown
        }
    }

    static func defaultOutputDeviceUID() -> String? {
        let deviceID = defaultOutputDevice()
        guard deviceID != kAudioObjectUnknown else { return nil }
        return deviceID.readString(kAudioDevicePropertyDeviceUID)
    }

    func deviceUID() -> String? {
        readString(kAudioDevicePropertyDeviceUID)
    }

    // MARK: - Process Tap Operations

    static func createProcessTap(
        for audioObjectIDs: [AudioObjectID]
    ) throws -> (tapID: AudioObjectID, tapUUID: String) {
        let description = CATapDescription(stereoMixdownOfProcesses: audioObjectIDs)
        description.name = "AudioMix-Tap-\(UUID().uuidString.prefix(8))"
        description.muteBehavior = .muted
        description.isPrivate = true

        var tapID: AudioObjectID = kAudioObjectUnknown
        let status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else {
            logger.error("Failed to create process tap: OSStatus \(status)")
            throw CoreAudioError.readFailed(status)
        }

        let uuid = description.uuid.uuidString
        logger.debug("Created process tap \(tapID) with UUID \(uuid)")
        return (tapID, uuid)
    }

    static func destroyProcessTap(_ tapID: AudioObjectID) {
        guard tapID != kAudioObjectUnknown else { return }
        let status = AudioHardwareDestroyProcessTap(tapID)
        if status != noErr {
            logger.warning("Failed to destroy process tap \(tapID): OSStatus \(status)")
        }
    }

    func tapFormat() throws -> AudioStreamBasicDescription {
        try read(kAudioTapPropertyFormat, scope: kAudioObjectPropertyScopeInput)
    }

    // MARK: - Aggregate Device Operations

    static func createPrivateAggregateDevice(
        tapUUID: String,
        outputDeviceUID: String
    ) throws -> AudioObjectID {
        let uid = "AudioMix-Aggregate-\(UUID().uuidString.prefix(8))"

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "AudioMix Tap Device",
            kAudioAggregateDeviceUIDKey: uid,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputDeviceUID],
            ],
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: tapUUID],
            ],
        ]

        var aggregateID: AudioObjectID = kAudioObjectUnknown
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID)
        guard status == noErr else {
            logger.error("Failed to create aggregate device: OSStatus \(status)")
            throw CoreAudioError.readFailed(status)
        }

        logger.debug("Created aggregate device \(aggregateID) with UID \(uid)")
        return aggregateID
    }

    static func destroyAggregateDevice(_ deviceID: AudioObjectID) {
        guard deviceID != kAudioObjectUnknown else { return }
        let status = AudioHardwareDestroyAggregateDevice(deviceID)
        if status != noErr {
            logger.warning("Failed to destroy aggregate device \(deviceID): OSStatus \(status)")
        }
    }

    // MARK: - Device Enumeration

    static func allOutputDevices() -> [AudioObjectID] {
        do {
            let allDevices: [AudioObjectID] = try AudioObjectID(kAudioObjectSystemObject)
                .readArray(kAudioHardwarePropertyDevices)
            return allDevices.filter { device in
                // Must have output streams
                guard device.hasOutputStreams() else { return false }
                // Exclude our own aggregate devices
                if let uid = device.deviceUID(), uid.hasPrefix("AudioMix-Aggregate-") {
                    return false
                }
                return true
            }
        } catch {
            logger.error("Failed to enumerate devices: \(error.localizedDescription)")
            return []
        }
    }

    func deviceName() -> String? {
        readString(kAudioObjectPropertyName)
    }

    func hasOutputStreams() -> Bool {
        do {
            let streams: [AudioObjectID] = try readArray(
                kAudioDevicePropertyStreams,
                scope: kAudioObjectPropertyScopeOutput
            )
            return !streams.isEmpty
        } catch {
            return false
        }
    }
}
