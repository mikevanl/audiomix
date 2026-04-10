import Foundation
import UserNotifications

@MainActor
final class AudioSourceNotifier {
    private var knownPIDs: Set<pid_t> = []
    private var hasInitialized = false

    func update(apps: [AudioApp]) {
        let currentPIDs = Set(apps.map(\.id))

        if hasInitialized {
            let newPIDs = currentPIDs.subtracting(knownPIDs)
            for pid in newPIDs {
                if let app = apps.first(where: { $0.id == pid }) {
                    sendNotification(for: app)
                }
            }
        } else {
            hasInitialized = true
        }

        knownPIDs = currentPIDs
    }

    private func sendNotification(for app: AudioApp) {
        guard UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true else { return }

        let content = UNMutableNotificationContent()
        content.title = "New Audio Source"
        content.body = "\(app.name) started playing audio"
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: "new-source-\(app.id)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
}
