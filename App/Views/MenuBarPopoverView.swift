import SwiftUI

struct MenuBarPopoverView: View {
    let monitor: AudioProcessMonitor
    let tapManager: AudioTapManager

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 320)
        .background(.ultraThinMaterial)
    }

    private var header: some View {
        HStack {
            Text("Audio")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if tapManager.permissionDenied {
            permissionDeniedView
        } else if monitor.activeApps.isEmpty {
            EmptyStateView()
                .frame(minHeight: 120)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(monitor.activeApps) { app in
                            AudioAppRowView(app: app, tapManager: tapManager)
                        }
                    }
                }
                .frame(maxHeight: 500)
                .onChange(of: context.date) { _, _ in
                    tapManager.updateDisplayLevels()
                }
            }
        }
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Audio Capture Permission Required")
                .font(.subheadline)
                .fontWeight(.medium)
            Text("Grant access in System Settings to control app volumes.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding()
        .frame(minHeight: 140)
    }

    @Environment(\.openSettings) private var openSettings

    private var footer: some View {
        HStack {
            Button {
                openSettings()
            } label: {
                Image(systemName: "gear")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.caption)

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.caption)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
