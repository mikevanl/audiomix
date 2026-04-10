import Foundation

public enum IPCConstants {
    public static var socketPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Application Support/AudioMix/audiomix.sock"
    }

    public static var supportDirectory: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Application Support/AudioMix"
    }
}

public struct IPCRequest: Codable {
    public let command: String
    public var app: String?
    public var value: Int?
    public var state: String?
    public var device: String?
    public var reset: Bool?
    public var activeOnly: Bool?
    public var ruleID: String?
    public var ruleJSON: String?

    public init(command: String, app: String? = nil, value: Int? = nil,
                state: String? = nil, device: String? = nil,
                reset: Bool? = nil, activeOnly: Bool? = nil,
                ruleID: String? = nil, ruleJSON: String? = nil) {
        self.command = command
        self.app = app
        self.value = value
        self.state = state
        self.device = device
        self.reset = reset
        self.activeOnly = activeOnly
        self.ruleID = ruleID
        self.ruleJSON = ruleJSON
    }
}

public struct IPCResponse: Codable {
    public let ok: Bool
    public var error: String?
    public var apps: [AppSnapshot]?
    public var app: AppSnapshot?
    public var devices: [DeviceSnapshot]?
    public var rules: [RuleSnapshot]?

    public init(ok: Bool, error: String? = nil, apps: [AppSnapshot]? = nil,
                app: AppSnapshot? = nil, devices: [DeviceSnapshot]? = nil,
                rules: [RuleSnapshot]? = nil) {
        self.ok = ok
        self.error = error
        self.apps = apps
        self.app = app
        self.devices = devices
        self.rules = rules
    }

    public static func success(apps: [AppSnapshot]) -> IPCResponse {
        IPCResponse(ok: true, apps: apps)
    }

    public static func success(app: AppSnapshot) -> IPCResponse {
        IPCResponse(ok: true, app: app)
    }

    public static func success(devices: [DeviceSnapshot]) -> IPCResponse {
        IPCResponse(ok: true, devices: devices)
    }

    public static func success(rules: [RuleSnapshot]) -> IPCResponse {
        IPCResponse(ok: true, rules: rules)
    }

    public static func failure(_ message: String) -> IPCResponse {
        IPCResponse(ok: false, error: message)
    }
}

public struct AppSnapshot: Codable {
    public let pid: Int32
    public let name: String
    public let bundleID: String?
    public let volume: Int
    public let muted: Bool
    public let active: Bool
    public let outputDevice: String?

    public init(pid: Int32, name: String, bundleID: String?, volume: Int,
                muted: Bool, active: Bool, outputDevice: String?) {
        self.pid = pid
        self.name = name
        self.bundleID = bundleID
        self.volume = volume
        self.muted = muted
        self.active = active
        self.outputDevice = outputDevice
    }
}

public struct DeviceSnapshot: Codable {
    public let uid: String
    public let name: String
    public let isDefault: Bool

    public init(uid: String, name: String, isDefault: Bool) {
        self.uid = uid
        self.name = name
        self.isDefault = isDefault
    }
}
