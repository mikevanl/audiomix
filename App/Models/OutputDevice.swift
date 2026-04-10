import CoreAudio

struct OutputDevice: Identifiable, Hashable {
    let id: AudioObjectID
    let uid: String
    let name: String

    static func == (lhs: OutputDevice, rhs: OutputDevice) -> Bool {
        lhs.uid == rhs.uid
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(uid)
    }

    static func allAvailable() -> [OutputDevice] {
        AudioObjectID.allOutputDevices().compactMap { deviceID in
            guard let uid = deviceID.deviceUID(),
                  let name = deviceID.deviceName() else { return nil }
            return OutputDevice(id: deviceID, uid: uid, name: name)
        }
    }
}
