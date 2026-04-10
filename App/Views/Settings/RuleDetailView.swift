import AudioMixKit
import SwiftUI

struct RuleDetailView: View {
    let rulesEngine: RulesEngine
    @Environment(\.dismiss) private var dismiss

    @State private var triggerType: RuleTriggerType = .deviceConnected
    @State private var triggerDevice = ""
    @State private var triggerApp = ""
    @State private var actionType: RuleActionType = .route
    @State private var actionApp = ""
    @State private var actionDevice = ""
    @State private var actionVolume: Double = 50

    private var isDeviceTrigger: Bool {
        triggerType == .deviceConnected || triggerType == .deviceDisconnected
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Trigger") {
                    Picker("When", selection: $triggerType) {
                        Text("Device connected").tag(RuleTriggerType.deviceConnected)
                        Text("Device disconnected").tag(RuleTriggerType.deviceDisconnected)
                        Text("App launched").tag(RuleTriggerType.appLaunched)
                        Text("App quit").tag(RuleTriggerType.appQuit)
                    }

                    if isDeviceTrigger {
                        TextField("Device name", text: $triggerDevice, prompt: Text("e.g. AirPods Pro"))
                    } else {
                        TextField("App name or bundle ID", text: $triggerApp, prompt: Text("e.g. Music"))
                    }
                }

                Section("Action") {
                    Picker("Action", selection: $actionType) {
                        Text("Route to device").tag(RuleActionType.route)
                        Text("Mute").tag(RuleActionType.mute)
                        Text("Unmute").tag(RuleActionType.unmute)
                        Text("Set volume").tag(RuleActionType.setVolume)
                    }

                    TextField("Target app", text: $actionApp, prompt: Text("e.g. Spotify"))

                    if actionType == .route {
                        TextField("Output device", text: $actionDevice, prompt: Text("e.g. AirPods Pro"))
                    }

                    if actionType == .setVolume {
                        HStack {
                            Slider(value: $actionVolume, in: 0...100, step: 1)
                            Text("\(Int(actionVolume))%")
                                .monospacedDigit()
                                .frame(width: 40)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add Rule") { addRule() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: 400, height: 340)
    }

    private var isValid: Bool {
        let hasTriggerValue = isDeviceTrigger ? !triggerDevice.isEmpty : !triggerApp.isEmpty
        return hasTriggerValue && !actionApp.isEmpty
    }

    private func addRule() {
        let trigger = RuleTrigger(
            type: triggerType,
            device: isDeviceTrigger ? triggerDevice : nil,
            app: isDeviceTrigger ? nil : triggerApp
        )
        let action = RuleAction(
            type: actionType,
            app: actionApp,
            device: actionType == .route ? actionDevice : nil,
            volume: actionType == .setVolume ? Int(actionVolume) : nil
        )
        rulesEngine.addRule(Rule(trigger: trigger, action: action))
        dismiss()
    }
}
