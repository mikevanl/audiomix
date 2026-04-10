import AppKit
import CoreAudio

struct AudioApp: Identifiable {
    let id: pid_t
    var audioObjectIDs: [AudioObjectID]
    let name: String
    let icon: NSImage
    let bundleID: String?
    var isOutputActive: Bool
}

extension AudioApp: Hashable {
    static func == (lhs: AudioApp, rhs: AudioApp) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
