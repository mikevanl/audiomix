import SwiftUI

struct SettingsView: View {
    let rulesEngine: RulesEngine

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }

            RulesSettingsView(rulesEngine: rulesEngine)
                .tabItem { Label("Rules", systemImage: "list.bullet.rectangle") }

            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 360)
    }
}
