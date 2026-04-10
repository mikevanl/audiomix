# AudioMix

Per-app volume, mute, and output device routing for macOS.

A lightweight, native macOS menu bar app that brings Windows-style per-app audio management to macOS. See what's making sound, control volume per app, mute individual apps, and route audio to different output devices — all from the menu bar.

## Features

- **Per-app volume control** — Individual volume slider (0–100%) for each audio-producing app
- **Per-app mute** — Toggle mute for any app independently
- **Real-time VU meters** — Visual level bars showing actual audio output per app
- **Per-app output routing** — Route any app to a specific output device (speakers, headphones, AirPods, etc.)
- **Source detection** — Real-time indicators showing which apps are currently producing sound
- **Automation rules** — Trigger actions when devices connect/disconnect or apps launch/quit
- **CLI tool** — Full CLI (`audiomix`) for scripting and integration with tools like SketchyBar
- **New audio source notifications** — Get notified when a new app starts playing audio
- **Native macOS UI** — SwiftUI menu bar popover with vibrancy, matches system appearance

## Requirements

- macOS 14.2 (Sonoma) or later
- Xcode 16+ (for building from source)
- Audio Capture permission (prompted on first use)

## Installation

### Homebrew

```sh
brew install --formula Formula/audiomix.rb
```

### Build from Source

```sh
git clone https://github.com/yourusername/audiomix.git
cd audiomix
brew install xcodegen    # if not already installed
xcodegen generate
xcodebuild -scheme AudioMix -configuration Release -destination 'platform=macOS' build
xcodebuild -scheme audiomix -configuration Release -destination 'platform=macOS' build
```

The built app is at `DerivedData/AudioMix-*/Build/Products/Release/AudioMix.app`.
The CLI binary is at `DerivedData/AudioMix-*/Build/Products/Release/audiomix`.

Copy the app to `/Applications/` and the CLI to `/usr/local/bin/` (or anywhere in your PATH).

## Getting Started

1. Launch **AudioMix** — a speaker icon appears in the menu bar
2. On first use, macOS will prompt for **Audio Capture** permission — grant it
3. Click the menu bar icon to open the popover
4. Play audio in any app — it appears in the list with a volume slider and level meter

### Granting Permission

AudioMix requires the "Audio Capture" permission to intercept and control per-app audio. When the permission prompt appears:

1. Click **Allow** in the system dialog
2. If you accidentally denied it, go to **System Settings > Privacy & Security > Audio Capture** and enable AudioMix

## Menu Bar App

The popover shows:

- **App icon + name** — with a green activity dot (bright when emitting audio, dim when silent)
- **Device routing menu** — click the branch icon to route the app to a specific output device
- **Volume slider** — drag to adjust volume (0–100%)
- **Mute button** — click the speaker icon to mute/unmute
- **VU meter** — thin horizontal bar showing real-time audio level (green/orange/red)
- **Settings gear** — opens the Settings window
- **Quit** — closes AudioMix

## CLI Reference

The `audiomix` CLI communicates with the running app via a Unix domain socket. The app must be running for CLI commands to work.

### List apps

```sh
audiomix list                  # JSON output
audiomix list --active         # Only apps currently emitting audio
audiomix list --human          # Human-readable table
```

### Volume control

```sh
audiomix volume Spotify        # Get current volume
audiomix volume Spotify 50     # Set to 50%
audiomix volume com.spotify.client 75  # By bundle ID
```

### Mute control

```sh
audiomix mute Spotify          # Toggle mute
audiomix mute Spotify --on     # Mute
audiomix mute Spotify --off    # Unmute
```

### Output routing

```sh
audiomix route Spotify "AirPods Pro"   # Route to specific device
audiomix route Spotify --reset         # Reset to system default
```

### List output devices

```sh
audiomix devices               # JSON output
audiomix devices --human       # Human-readable list
```

### Active sources

```sh
audiomix active                # JSON: apps currently emitting audio
audiomix active --human        # Human-readable table
```

### Rules management

```sh
audiomix rules list            # List all automation rules
audiomix rules list --human    # Human-readable format
audiomix rules add rule.json   # Add rules from a JSON file
audiomix rules remove <id>     # Remove a rule by ID
```

### App identifiers

The `<app>` argument accepts:

- **App name** — e.g., `Spotify`, `"Google Chrome"` (case-insensitive)
- **PID** — e.g., `1234` (numeric)
- **Bundle ID** — e.g., `com.spotify.client` (contains dots)

### Output format

All commands output JSON by default (for machine parsing). Use `--human` for readable output.

If the app is not running, CLI commands exit with code 1 and print an error to stderr.

## Automation Rules

Rules are stored as JSON at `~/Library/Application Support/AudioMix/rules.json`.

### Rule format

```json
{
  "trigger": {
    "type": "device_connected",
    "device": "AirPods Pro"
  },
  "action": {
    "type": "route",
    "app": "Music",
    "device": "AirPods Pro"
  },
  "enabled": true
}
```

### Trigger types

| Type | Description | Required field |
|------|-------------|----------------|
| `device_connected` | An output device is connected | `device` (device name) |
| `device_disconnected` | An output device is disconnected | `device` (device name) |
| `app_launched` | An audio app appears | `app` (app name or bundle ID) |
| `app_quit` | An audio app disappears | `app` (app name or bundle ID) |

### Action types

| Type | Description | Required fields |
|------|-------------|-----------------|
| `route` | Route app to a device | `app`, `device` |
| `mute` | Mute the app | `app` |
| `unmute` | Unmute the app | `app` |
| `set_volume` | Set volume (0-100) | `app`, `volume` |

### Example: Route Music to AirPods when they connect

```json
[
  {
    "trigger": { "type": "device_connected", "device": "AirPods Pro" },
    "action": { "type": "route", "app": "Music", "device": "AirPods Pro" }
  },
  {
    "trigger": { "type": "device_connected", "device": "AirPods Pro" },
    "action": { "type": "mute", "app": "Microsoft Teams" }
  }
]
```

Save as `rules.json` and add via CLI:

```sh
audiomix rules add rules.json
```

Rules can also be managed in **Settings > Rules**.

## Settings

Open via the gear icon in the popover, or **AudioMix > Settings** in the menu bar.

- **General** — Launch at login, notification preferences
- **Rules** — View, add, and delete automation rules
- **About** — Version and license information

## Permissions

| Permission | Why | How to grant |
|---|---|---|
| Audio Capture | Required to tap per-app audio streams | System prompt on first use, or System Settings > Privacy & Security > Audio Capture |
| Notifications | Optional, for new audio source alerts | System prompt on first use |

AudioMix does **not** require Screen Recording, microphone access, or accessibility permissions.

## Troubleshooting

### No apps appear in the popover

- Ensure Audio Capture permission is granted (System Settings > Privacy & Security > Audio Capture)
- Play audio in an app and wait ~2 seconds for detection

### CLI says "AudioMix app is not running"

- The menu bar app must be running for CLI commands to work
- Launch AudioMix.app first

### Audio routing not taking effect

- The target device must be connected and available
- Check `audiomix devices` to verify the device is listed
- Some Bluetooth devices may need a moment after connecting

### Volume slider has no effect

- Verify the Audio Capture permission is granted
- Check if the app is muted (the mute button may be active)

## Architecture

AudioMix consists of three targets:

- **AudioMix** — SwiftUI menu bar app with Core Audio Tap API for per-process audio tapping
- **audiomix** — CLI tool using swift-argument-parser, communicates via Unix domain socket
- **AudioMixKit** — Shared framework with IPC types and client library

The audio pipeline uses macOS 14.2+ Core Audio Tap API:

1. `CATapDescription` targets specific process AudioObjectIDs
2. Private aggregate device combines the tap with the output device
3. IOProc callback applies gain/mute and computes RMS for VU meters
4. Lock-free `UnsafeMutablePointer<Float32>` for thread-safe volume/level communication

IPC uses a Unix domain socket at `~/Library/Application Support/AudioMix/audiomix.sock` with newline-delimited JSON messages.

## License

MIT License. See [LICENSE](LICENSE) for details.
