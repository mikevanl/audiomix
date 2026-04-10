import AudioMixKit
import SwiftUI

struct RulesSettingsView: View {
    let rulesEngine: RulesEngine
    @State private var selection: String?
    @State private var showingAddSheet = false

    var body: some View {
        VStack(spacing: 0) {
            if rulesEngine.rules.isEmpty {
                ContentUnavailableView {
                    Label("No Rules", systemImage: "list.bullet.rectangle")
                } description: {
                    Text("Add automation rules to control audio when devices connect or apps launch.")
                }
                .frame(maxHeight: .infinity)
            } else {
                List(rulesEngine.rules, selection: $selection) { rule in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ruleSummary(rule))
                            .font(.body)
                        Text(ruleDetail(rule))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(rule.id)
                }
            }

            Divider()

            HStack {
                Button { showingAddSheet = true } label: {
                    Image(systemName: "plus")
                }

                Button {
                    if let id = selection {
                        _ = rulesEngine.removeRule(id: id)
                        selection = nil
                    }
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(selection == nil)

                Spacer()
            }
            .padding(8)
        }
        .sheet(isPresented: $showingAddSheet) {
            RuleDetailView(rulesEngine: rulesEngine)
        }
    }

    private func ruleSummary(_ rule: Rule) -> String {
        let trigger = rule.trigger.type.rawValue.replacingOccurrences(of: "_", with: " ")
        return "When \(trigger): \(rule.trigger.device ?? rule.trigger.app ?? "?")"
    }

    private func ruleDetail(_ rule: Rule) -> String {
        let action = rule.action.type.rawValue.replacingOccurrences(of: "_", with: " ")
        var detail = "\(action) \(rule.action.app)"
        if let device = rule.action.device { detail += " → \(device)" }
        if let vol = rule.action.volume { detail += " to \(vol)%" }
        return detail
    }
}
