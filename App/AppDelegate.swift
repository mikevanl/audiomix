import AppKit
import AudioMixKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let monitor = AudioProcessMonitor()
    let tapManager = AudioTapManager()
    let notifier = AudioSourceNotifier()
    private(set) lazy var rulesEngine = RulesEngine(tapManager: tapManager, monitor: monitor)
    private var ipcServer: IPCServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }

        monitor.start()
        rulesEngine.loadRules()

        tapManager.onDeviceListChanged = { [weak self] connected, disconnected in
            guard let engine = self?.rulesEngine else { return }
            for device in connected {
                engine.evaluate(event: RuleEvent(type: .deviceConnected, deviceName: device.name))
            }
            for device in disconnected {
                engine.evaluate(event: RuleEvent(type: .deviceDisconnected, deviceName: device.name))
            }
        }

        ipcServer = IPCServer(tapManager: tapManager, monitor: monitor, rulesEngine: rulesEngine)
        ipcServer?.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        ipcServer?.stop()
        monitor.stop()
        tapManager.teardownAll()
    }
}
