import ArgumentParser
import AudioMixKit
import Foundation

@main
struct AudioMixCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "audiomix",
        abstract: "Control per-app audio from the command line.",
        version: AudioMixKit.version,
        subcommands: [List.self, Volume.self, Mute.self, Route.self, Devices.self, Active.self, Rules.self]
    )
}

// MARK: - List

struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List all apps with audio streams.")

    @Flag(name: .long, help: "Only show apps currently emitting audio.")
    var active = false

    @Flag(name: .long, help: "Human-readable output.")
    var human = false

    func run() async throws {
        let response = try await sendRequest(IPCRequest(command: "list", activeOnly: active))
        guard let apps = response.apps else { return }

        if human {
            printAppsTable(apps)
        } else {
            printJSON(apps)
        }
    }
}

// MARK: - Volume

struct Volume: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Get or set volume for an app.")

    @Argument(help: "App name, PID, or bundle ID.")
    var app: String

    @Argument(help: "Volume level (0-100). Omit to get current volume.")
    var value: Int?

    @Flag(name: .long, help: "Human-readable output.")
    var human = false

    func run() async throws {
        let response = try await sendRequest(IPCRequest(command: "volume", app: app, value: value))
        guard let snapshot = response.app else { return }

        if human {
            print("\(snapshot.name): \(snapshot.volume)%\(snapshot.muted ? " (muted)" : "")")
        } else {
            printJSON(snapshot)
        }
    }
}

// MARK: - Mute

struct Mute: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Toggle or set mute for an app.")

    @Argument(help: "App name, PID, or bundle ID.")
    var app: String

    @Flag(name: .long, help: "Mute the app.")
    var on = false

    @Flag(name: .long, help: "Unmute the app.")
    var off = false

    func run() async throws {
        let state: String? = on ? "on" : off ? "off" : nil
        let response = try await sendRequest(IPCRequest(command: "mute", app: app, state: state))
        guard let snapshot = response.app else { return }
        print(snapshot.muted ? "Muted \(snapshot.name)" : "Unmuted \(snapshot.name)")
    }
}

// MARK: - Route

struct Route: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Route app to a specific output device.")

    @Argument(help: "App name, PID, or bundle ID.")
    var app: String

    @Argument(help: "Output device name. Omit with --reset to use system default.")
    var device: String?

    @Flag(name: .long, help: "Reset to system default output.")
    var reset = false

    func run() async throws {
        let response = try await sendRequest(
            IPCRequest(command: "route", app: app, device: device, reset: reset)
        )
        guard let snapshot = response.app else { return }
        let output = snapshot.outputDevice ?? "System Default"
        print("\(snapshot.name) → \(output)")
    }
}

// MARK: - Devices

struct Devices: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List available output devices.")

    @Flag(name: .long, help: "Human-readable output.")
    var human = false

    func run() async throws {
        let response = try await sendRequest(IPCRequest(command: "devices"))
        guard let devices = response.devices else { return }

        if human {
            for d in devices {
                let marker = d.isDefault ? " (default)" : ""
                print("  \(d.name)\(marker)")
            }
        } else {
            printJSON(devices)
        }
    }
}

// MARK: - Active

struct Active: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show currently active audio sources.")

    @Flag(name: .long, help: "Human-readable output.")
    var human = false

    func run() async throws {
        let response = try await sendRequest(IPCRequest(command: "active"))
        guard let apps = response.apps else { return }

        if human {
            printAppsTable(apps)
        } else {
            printJSON(apps)
        }
    }
}

// MARK: - Rules

struct Rules: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage automation rules.",
        subcommands: [RulesList.self, RulesAdd.self, RulesRemove.self]
    )
}

struct RulesList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List all rules.")

    @Flag(name: .long, help: "Human-readable output.")
    var human = false

    func run() async throws {
        let response = try await sendRequest(IPCRequest(command: "rules_list"))
        guard let rules = response.rules else { return }

        if human {
            if rules.isEmpty {
                print("No rules configured.")
                return
            }
            for r in rules {
                let trigger = "\(r.trigger.type.rawValue): \(r.trigger.device ?? r.trigger.app ?? "?")"
                let action = "\(r.action.type.rawValue) \(r.action.app)"
                let extra = r.action.device ?? r.action.volume.map { "\($0)%" } ?? ""
                let status = r.enabled ? "" : " (disabled)"
                print("  [\(r.id.prefix(8))] \(trigger) → \(action) \(extra)\(status)")
            }
        } else {
            printJSON(rules)
        }
    }
}

struct RulesAdd: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "add", abstract: "Add rules from a JSON file.")

    @Argument(help: "Path to a JSON file containing a rule or array of rules.")
    var file: String

    func run() async throws {
        let url = URL(fileURLWithPath: file)
        guard let data = try? Data(contentsOf: url),
              let json = String(data: data, encoding: .utf8) else {
            printError("Could not read file: \(file)")
            throw ExitCode.failure
        }

        let response = try await sendRequest(IPCRequest(command: "rules_add", ruleJSON: json))
        guard let rules = response.rules else { return }
        print("Added \(rules.count) rule(s).")
        for r in rules {
            print("  [\(r.id.prefix(8))] \(r.trigger.type.rawValue) → \(r.action.type.rawValue) \(r.action.app)")
        }
    }
}

struct RulesRemove: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "remove", abstract: "Remove a rule by ID.")

    @Argument(help: "Rule ID (or prefix).")
    var id: String

    func run() async throws {
        let response = try await sendRequest(IPCRequest(command: "rules_remove", ruleID: id))
        if response.ok {
            print("Rule removed.")
        }
    }
}

// MARK: - Helpers

private func sendRequest(_ request: IPCRequest) async throws -> IPCResponse {
    let client = IPCClient()
    let response: IPCResponse
    do {
        response = try await client.send(request)
    } catch let error as IPCError {
        printError(error.errorDescription ?? "Unknown error")
        throw ExitCode.failure
    } catch {
        printError(error.localizedDescription)
        throw ExitCode.failure
    }

    if !response.ok {
        printError(response.error ?? "Unknown error")
        throw ExitCode.failure
    }
    return response
}

private func printJSON<T: Encodable>(_ value: T) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(value),
          let json = String(data: data, encoding: .utf8) else { return }
    print(json)
}

private func printAppsTable(_ apps: [AppSnapshot]) {
    if apps.isEmpty {
        print("No audio apps found.")
        return
    }
    let header = String(format: "%-20s %6s %5s %6s %7s  %s", "NAME", "PID", "VOL", "MUTED", "ACTIVE", "OUTPUT")
    print(header)
    for a in apps {
        let output = a.outputDevice ?? "System Default"
        let line = String(format: "%-20s %6d %4d%% %-6s %-7s  %s",
                          String(a.name.prefix(20)), a.pid, a.volume,
                          a.muted ? "yes" : "no",
                          a.active ? "yes" : "no",
                          output)
        print(line)
    }
}

private func printError(_ message: String) {
    FileHandle.standardError.write(Data("Error: \(message)\n".utf8))
}

