import CoreAudio
import Foundation
import os

private let logger = Logger(subsystem: "com.audiomix.AudioMix", category: "TapSession")

final class AudioTapSession {
    let pid: pid_t
    let audioObjectIDs: [AudioObjectID]

    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?
    private var isRunning = false

    /// Lock-free gain for the real-time audio thread (0.0...1.0).
    /// ARM64/x86-64 aligned 32-bit writes are hardware-atomic.
    let gainPtr: UnsafeMutablePointer<Float32>

    /// Lock-free mute flag (0 = unmuted, nonzero = muted).
    let mutePtr: UnsafeMutablePointer<UInt32>

    /// Lock-free RMS level written by the real-time audio thread (0.0...1.0 linear).
    let levelPtr: UnsafeMutablePointer<Float32>

    init(pid: pid_t, audioObjectIDs: [AudioObjectID]) {
        self.pid = pid
        self.audioObjectIDs = audioObjectIDs
        self.gainPtr = .allocate(capacity: 1)
        self.mutePtr = .allocate(capacity: 1)
        self.levelPtr = .allocate(capacity: 1)
        gainPtr.initialize(to: 1.0)
        mutePtr.initialize(to: 0)
        levelPtr.initialize(to: 0.0)
    }

    deinit {
        stop()
        gainPtr.deinitialize(count: 1)
        gainPtr.deallocate()
        mutePtr.deinitialize(count: 1)
        mutePtr.deallocate()
        levelPtr.deinitialize(count: 1)
        levelPtr.deallocate()
    }

    // MARK: - Public API

    func start(outputDeviceID: AudioObjectID) throws {
        guard !isRunning else { return }

        // 1. Create process tap
        let (newTapID, tapUUID) = try AudioObjectID.createProcessTap(for: audioObjectIDs)
        tapID = newTapID

        // 2. Read tap format for validation
        do {
            let format = try tapID.tapFormat()
            logger.debug("Tap format: \(format.mSampleRate)Hz, \(format.mChannelsPerFrame)ch, flags=\(format.mFormatFlags)")
        } catch {
            logger.warning("Could not read tap format: \(error.localizedDescription)")
        }

        // 3. Get output device UID
        guard let outputUID = outputDeviceID.deviceUID() else {
            logger.error("Could not get output device UID for device \(outputDeviceID)")
            AudioObjectID.destroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
            throw CoreAudioError.propertyNotSupported
        }

        // 4. Create private aggregate device with tap + output
        do {
            aggregateDeviceID = try AudioObjectID.createPrivateAggregateDevice(
                tapUUID: tapUUID,
                outputDeviceUID: outputUID
            )
        } catch {
            AudioObjectID.destroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
            throw error
        }

        // 5. Create IOProc
        let capturedGainPtr = gainPtr
        let capturedMutePtr = mutePtr
        let capturedLevelPtr = levelPtr

        let createStatus = AudioDeviceCreateIOProcIDWithBlock(
            &ioProcID,
            aggregateDeviceID,
            nil
        ) { _, inInputData, _, outOutputData, _ in
            let inputBL = inInputData.pointee
            let outputBL = outOutputData.pointee

            let gain = capturedGainPtr.pointee
            let isMuted = capturedMutePtr.pointee != 0
            let effectiveGain = isMuted ? Float32(0.0) : gain

            let inputCount = Int(inputBL.mNumberBuffers)
            let outputCount = Int(outputBL.mNumberBuffers)

            var sumOfSquares: Float32 = 0.0
            var totalSamples: Int = 0

            for i in 0..<min(inputCount, outputCount) {
                let inBuf = inputBL.mBuffers(at: i)
                let outBuf = outputBL.mBuffers(at: i)

                guard let inData = inBuf.mData?.assumingMemoryBound(to: Float32.self),
                      let outData = outBuf.mData?.assumingMemoryBound(to: Float32.self) else { continue }

                let sampleCount = Int(inBuf.mDataByteSize) / MemoryLayout<Float32>.size
                let outSampleCount = Int(outBuf.mDataByteSize) / MemoryLayout<Float32>.size
                let count = min(sampleCount, outSampleCount)

                if effectiveGain == 1.0 {
                    for j in 0..<count {
                        let s = inData[j]
                        outData[j] = s
                        sumOfSquares += s * s
                    }
                } else {
                    for j in 0..<count {
                        let s = inData[j] * effectiveGain
                        outData[j] = s
                        sumOfSquares += s * s
                    }
                }
                totalSamples += count
            }

            // Write RMS level for UI consumption
            if totalSamples > 0 {
                capturedLevelPtr.pointee = sqrtf(sumOfSquares / Float32(totalSamples))
            } else {
                capturedLevelPtr.pointee = 0.0
            }

            // Zero any extra output buffers that don't have matching input
            for i in inputCount..<outputCount {
                let outBuf = outputBL.mBuffers(at: i)
                if let outData = outBuf.mData {
                    memset(outData, 0, Int(outBuf.mDataByteSize))
                }
            }
        }

        guard createStatus == noErr else {
            logger.error("Failed to create IOProc: OSStatus \(createStatus)")
            AudioObjectID.destroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = kAudioObjectUnknown
            AudioObjectID.destroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
            throw CoreAudioError.readFailed(createStatus)
        }

        // 6. Start audio
        let startStatus = AudioDeviceStart(aggregateDeviceID, ioProcID)
        guard startStatus == noErr else {
            logger.error("Failed to start audio device: OSStatus \(startStatus)")
            if let procID = ioProcID {
                AudioDeviceDestroyIOProcID(aggregateDeviceID, procID)
            }
            ioProcID = nil
            AudioObjectID.destroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = kAudioObjectUnknown
            AudioObjectID.destroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
            throw CoreAudioError.readFailed(startStatus)
        }

        isRunning = true
        logger.info("Started tap session for PID \(self.pid)")
    }

    func stop() {
        guard isRunning || tapID != kAudioObjectUnknown else { return }

        if isRunning, let procID = ioProcID {
            AudioDeviceStop(aggregateDeviceID, procID)
        }
        isRunning = false

        if let procID = ioProcID {
            AudioDeviceDestroyIOProcID(aggregateDeviceID, procID)
            ioProcID = nil
        }

        AudioObjectID.destroyAggregateDevice(aggregateDeviceID)
        aggregateDeviceID = kAudioObjectUnknown

        AudioObjectID.destroyProcessTap(tapID)
        tapID = kAudioObjectUnknown

        logger.info("Stopped tap session for PID \(self.pid)")
    }

    func setVolume(_ value: Float32) {
        gainPtr.pointee = max(0.0, min(1.0, value))
    }

    func setMuted(_ muted: Bool) {
        mutePtr.pointee = muted ? 1 : 0
    }

    func readLevel() -> Float32 {
        levelPtr.pointee
    }
}

// MARK: - AudioBufferList helper

private extension AudioBufferList {
    /// Access buffer at index. AudioBufferList has a variable-length mBuffers field.
    func mBuffers(at index: Int) -> AudioBuffer {
        withUnsafePointer(to: self) { ptr in
            let bufferPtr = UnsafeRawPointer(ptr)
                .advanced(by: MemoryLayout<UInt32>.size) // skip mNumberBuffers
                .assumingMemoryBound(to: AudioBuffer.self)
            return bufferPtr[index]
        }
    }
}
