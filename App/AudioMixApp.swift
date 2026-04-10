import SwiftUI
import MenuBarExtraAccess

@main
struct AudioMixApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var isPresented = false

    var body: some Scene {
        MenuBarExtra("AudioMix", systemImage: "speaker.wave.2.fill") {
            MenuBarPopoverView(monitor: appDelegate.monitor, tapManager: appDelegate.tapManager)
                .onChange(of: appDelegate.monitor.activeApps) { _, apps in
                    appDelegate.tapManager.syncWithApps(apps)
                    appDelegate.notifier.update(apps: apps)
                    appDelegate.rulesEngine.handleAppListUpdate(apps)
                }
        }
        .menuBarExtraAccess(isPresented: $isPresented)
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(rulesEngine: appDelegate.rulesEngine)
        }
    }
}
