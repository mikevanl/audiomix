import Foundation

public struct Rule: Codable, Identifiable {
    public let id: String
    public let trigger: RuleTrigger
    public let action: RuleAction
    public let enabled: Bool

    public init(id: String = UUID().uuidString, trigger: RuleTrigger, action: RuleAction, enabled: Bool = true) {
        self.id = id
        self.trigger = trigger
        self.action = action
        self.enabled = enabled
    }
}

public struct RuleTrigger: Codable {
    public let type: RuleTriggerType
    public let device: String?
    public let app: String?

    public init(type: RuleTriggerType, device: String? = nil, app: String? = nil) {
        self.type = type
        self.device = device
        self.app = app
    }
}

public enum RuleTriggerType: String, Codable {
    case deviceConnected = "device_connected"
    case deviceDisconnected = "device_disconnected"
    case appLaunched = "app_launched"
    case appQuit = "app_quit"
}

public struct RuleAction: Codable {
    public let type: RuleActionType
    public let app: String
    public let device: String?
    public let volume: Int?

    public init(type: RuleActionType, app: String, device: String? = nil, volume: Int? = nil) {
        self.type = type
        self.app = app
        self.device = device
        self.volume = volume
    }
}

public enum RuleActionType: String, Codable {
    case route
    case mute
    case unmute
    case setVolume = "set_volume"
}

public struct RuleSnapshot: Codable {
    public let id: String
    public let trigger: RuleTrigger
    public let action: RuleAction
    public let enabled: Bool

    public init(rule: Rule) {
        self.id = rule.id
        self.trigger = rule.trigger
        self.action = rule.action
        self.enabled = rule.enabled
    }
}
