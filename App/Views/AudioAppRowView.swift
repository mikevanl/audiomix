import SwiftUI

struct AudioAppRowView: View {
    let app: AudioApp
    let tapManager: AudioTapManager

    private var volume: Float32 { tapManager.volume(for: app.id) }
    private var isMuted: Bool { tapManager.isMuted(for: app.id) }
    private var level: Float32 { tapManager.level(for: app.id) }
    private var currentDeviceUID: String? { tapManager.outputDeviceUID(for: app.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Row 1: app identity + device routing menu
            HStack(spacing: 10) {
                ZStack(alignment: .bottomTrailing) {
                    Image(nsImage: app.icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)

                    if app.isOutputActive {
                        Circle()
                            .fill(.green.opacity(level > 0.001 ? 1.0 : 0.3))
                            .frame(width: 6, height: 6)
                            .offset(x: 1, y: 1)
                    }
                }

                Text(app.name)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                deviceMenu
            }

            // Row 2: volume controls
            HStack(spacing: 6) {
                Button {
                    tapManager.setMuted(!isMuted, for: app.id)
                } label: {
                    Image(systemName: muteIconName)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .foregroundStyle(isMuted ? .red : .secondary)

                Slider(
                    value: Binding(
                        get: { Double(volume) },
                        set: { tapManager.setVolume(Float32($0), for: app.id) }
                    ),
                    in: 0...1
                )
                .controlSize(.small)

                Text("\(Int(volume * 100))%")
                    .font(.caption2)
                    .monospacedDigit()
                    .frame(width: 32, alignment: .trailing)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 34)

            // Row 3: level meter
            if app.isOutputActive {
                LevelMeterView(level: level)
                    .padding(.leading, 34)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    // MARK: - Device Routing Menu

    @ViewBuilder
    private var deviceMenu: some View {
        Menu {
            Button {
                tapManager.setOutputDevice(uid: nil, for: app.id)
            } label: {
                HStack {
                    Text("System Default")
                    if currentDeviceUID == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }

            Divider()

            ForEach(tapManager.availableOutputDevices) { device in
                Button {
                    tapManager.setOutputDevice(uid: device.uid, for: app.id)
                } label: {
                    HStack {
                        Text(device.name)
                        if currentDeviceUID == device.uid {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.triangle.branch")
                .font(.caption)
                .foregroundStyle(currentDeviceUID != nil ? Color.accentColor : .secondary)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 20)
        .help(deviceTooltip)
    }

    private var deviceTooltip: String {
        if let uid = currentDeviceUID,
           let device = tapManager.availableOutputDevices.first(where: { $0.uid == uid }) {
            return "Output: \(device.name)"
        }
        return "Output: System Default"
    }

    private var muteIconName: String {
        if isMuted { return "speaker.slash.fill" }
        if volume == 0 { return "speaker.fill" }
        if volume < 0.33 { return "speaker.wave.1.fill" }
        if volume < 0.66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}
