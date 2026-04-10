import AudioMixKit
import SwiftUI

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "speaker.wave.2.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)

            Text("AudioMix")
                .font(.title)
                .fontWeight(.semibold)

            Text("Version \(AudioMixKit.version)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Per-app volume, mute, and output device routing for macOS.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            Text("MIT License")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
    }
}
