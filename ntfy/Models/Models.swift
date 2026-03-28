import Foundation
import SwiftData

// MARK: - API Response Models

struct NtfyMessage: Codable, Identifiable, Hashable {
    let id: String
    let time: Int
    let expires: Int?
    let event: String
    let topic: String
    let message: String?
    let title: String?
    let tags: [String]?
    let priority: Int?
    let click: String?
    let actions: [NtfyAction]?
    let attachment: NtfyAttachment?
    let icon: String?
    let sequenceId: String?

    enum CodingKeys: String, CodingKey {
        case id, time, expires, event, topic, message, title, tags, priority, click, actions, attachment, icon
        case sequenceId = "sequence_id"
    }

    var date: Date {
        Date(timeIntervalSince1970: TimeInterval(time))
    }

    var priorityLevel: Priority {
        Priority(rawValue: priority ?? 3) ?? .default
    }

    var displayTitle: String {
        title ?? topic
    }

    var displayMessage: String {
        message ?? ""
    }

    var emojiTags: [String] {
        tags?.compactMap { EmojiMap.emoji(for: $0) } ?? []
    }
}

struct NtfyAction: Codable, Hashable {
    let action: String
    let label: String
    let url: String?
    let method: String?
    let headers: [String: String]?
    let body: String?
    let clear: Bool?
}

struct NtfyAttachment: Codable, Hashable {
    let name: String?
    let type: String?
    let size: Int?
    let expires: Int?
    let url: String?
}

enum Priority: Int, CaseIterable {
    case min = 1
    case low = 2
    case `default` = 3
    case high = 4
    case urgent = 5

    var name: String {
        switch self {
        case .min: return "Minimal"
        case .low: return "Niedrig"
        case .default: return "Standard"
        case .high: return "Hoch"
        case .urgent: return "Dringend"
        }
    }

    var icon: String {
        switch self {
        case .min: return "arrow.down.to.line"
        case .low: return "arrow.down"
        case .default: return "minus"
        case .high: return "arrow.up"
        case .urgent: return "exclamationmark.2"
        }
    }

    var color: String {
        switch self {
        case .min: return "gray"
        case .low: return "blue"
        case .default: return "primary"
        case .high: return "orange"
        case .urgent: return "red"
        }
    }
}

// MARK: - SwiftData Models

@Model
final class Topic {
    @Attribute(.unique) var id: String
    var name: String
    var serverURL: String
    var useAuth: Bool
    var iconName: String?
    var colorHex: String?
    var customLetter: String?
    var useMessageIcon: Bool?
    var isMuted: Bool
    var createdAt: Date
    var lastMessageAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \StoredMessage.topic)
    var messages: [StoredMessage]?

    init(name: String, serverURL: String, useAuth: Bool = true, iconName: String? = nil, colorHex: String? = nil) {
        self.id = UUID().uuidString
        self.name = name
        self.serverURL = serverURL
        self.useAuth = useAuth
        self.iconName = iconName
        self.colorHex = colorHex
        self.customLetter = nil
        self.useMessageIcon = true
        self.isMuted = false
        self.createdAt = Date()
        self.messages = []
    }

    var fullURL: String {
        "\(serverURL)/\(name)"
    }

    var unreadCount: Int {
        messages?.filter { !$0.isRead }.count ?? 0
    }

    var displayLetter: String {
        customLetter ?? String(name.prefix(1)).uppercased()
    }

    var shouldUseMessageIcon: Bool {
        useMessageIcon ?? true
    }
}

// Storable action for SwiftData
struct StoredAction: Codable, Hashable {
    let action: String      // "view", "http", "broadcast"
    let label: String
    let url: String?
    let method: String?     // GET, POST, etc.
    let headers: [String: String]?
    let body: String?
    let clear: Bool?

    init(from ntfyAction: NtfyAction) {
        self.action = ntfyAction.action
        self.label = ntfyAction.label
        self.url = ntfyAction.url
        self.method = ntfyAction.method
        self.headers = ntfyAction.headers
        self.body = ntfyAction.body
        self.clear = ntfyAction.clear
    }
}

// Storable attachment for SwiftData
struct StoredAttachment: Codable, Hashable {
    let name: String?
    let type: String?
    let size: Int?
    let expires: Int?
    let url: String?

    init(from ntfyAttachment: NtfyAttachment) {
        self.name = ntfyAttachment.name
        self.type = ntfyAttachment.type
        self.size = ntfyAttachment.size
        self.expires = ntfyAttachment.expires
        self.url = ntfyAttachment.url
    }

    var isImage: Bool {
        guard let type = type else { return false }
        return type.hasPrefix("image/")
    }

    var formattedSize: String? {
        guard let size = size else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }

    var fileName: String {
        name ?? "attachment"
    }
}

@Model
final class StoredMessage {
    @Attribute(.unique) var id: String
    var messageId: String
    var sequenceId: String?
    var time: Int
    var title: String?
    var message: String?
    var tags: [String]?
    var priority: Int
    var clickURL: String?
    var iconURL: String?
    var isRead: Bool
    var receivedAt: Date

    // New: Attachment and Actions
    var attachmentData: Data?
    var actionsData: Data?

    var topic: Topic?

    init(from ntfyMessage: NtfyMessage, topic: Topic) {
        self.id = UUID().uuidString
        self.messageId = ntfyMessage.id
        self.sequenceId = ntfyMessage.sequenceId
        self.time = ntfyMessage.time
        self.title = ntfyMessage.title
        self.message = ntfyMessage.message
        self.tags = ntfyMessage.tags
        self.priority = ntfyMessage.priority ?? 3
        self.clickURL = ntfyMessage.click
        self.iconURL = ntfyMessage.icon
        self.isRead = false
        self.receivedAt = Date()
        self.topic = topic

        // Encode attachment
        if let attachment = ntfyMessage.attachment {
            let storedAttachment = StoredAttachment(from: attachment)
            self.attachmentData = try? JSONEncoder().encode(storedAttachment)
        }

        // Encode actions
        if let actions = ntfyMessage.actions, !actions.isEmpty {
            let storedActions = actions.map { StoredAction(from: $0) }
            self.actionsData = try? JSONEncoder().encode(storedActions)
        }
    }

    var date: Date {
        Date(timeIntervalSince1970: TimeInterval(time))
    }

    var priorityLevel: Priority {
        Priority(rawValue: priority) ?? .default
    }

    var emojiTags: [String] {
        tags?.compactMap { EmojiMap.emoji(for: $0) } ?? []
    }

    // Decoded attachment
    var attachment: StoredAttachment? {
        guard let data = attachmentData else { return nil }
        return try? JSONDecoder().decode(StoredAttachment.self, from: data)
    }

    // Decoded actions
    var actions: [StoredAction]? {
        guard let data = actionsData else { return nil }
        return try? JSONDecoder().decode([StoredAction].self, from: data)
    }
}

@Model
final class Server {
    @Attribute(.unique) var id: String
    var url: String
    var name: String
    var useAuth: Bool
    var username: String?
    var isDefault: Bool
    var addedAt: Date

    init(url: String, name: String? = nil, useAuth: Bool = false, username: String? = nil, isDefault: Bool = false) {
        self.id = UUID().uuidString
        self.url = url.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.name = name ?? url
        self.useAuth = useAuth
        self.username = username
        self.isDefault = isDefault
        self.addedAt = Date()
    }
}

@Model
final class DeletedMessage {
    @Attribute(.unique) var messageId: String
    var topicName: String
    var serverURL: String
    var deletedAt: Date

    init(messageId: String, topicName: String, serverURL: String) {
        self.messageId = messageId
        self.topicName = topicName
        self.serverURL = serverURL
        self.deletedAt = Date()
    }
}

// MARK: - Emoji Mapping

struct EmojiMap {
    static let tagToEmoji: [String: String] = [
        // Status
        "white_check_mark": "✅",
        "check": "✅",
        "x": "❌",
        "warning": "⚠️",
        "no_entry": "⛔",
        "rotating_light": "🚨",

        // Communication
        "speech_balloon": "💬",
        "email": "📧",
        "envelope": "✉️",
        "bell": "🔔",
        "loudspeaker": "📢",
        "mega": "📣",

        // Objects
        "computer": "💻",
        "cd": "💿",
        "floppy_disk": "💾",
        "file_folder": "📁",
        "package": "📦",
        "gift": "🎁",
        "key": "🔑",
        "lock": "🔒",
        "unlock": "🔓",

        // Actions
        "rocket": "🚀",
        "fire": "🔥",
        "zap": "⚡",
        "boom": "💥",
        "sparkles": "✨",
        "star": "⭐",
        "heart": "❤️",
        "thumbsup": "👍",
        "thumbsdown": "👎",
        "clap": "👏",
        "pray": "🙏",

        // Faces
        "smile": "😊",
        "grin": "😁",
        "joy": "😂",
        "sob": "😭",
        "thinking": "🤔",
        "eyes": "👀",
        "skull": "💀",

        // Nature
        "sunny": "☀️",
        "cloud": "☁️",
        "rain": "🌧️",
        "snowflake": "❄️",
        "rainbow": "🌈",

        // Tech
        "gear": "⚙️",
        "wrench": "🔧",
        "hammer": "🔨",
        "nut_and_bolt": "🔩",
        "link": "🔗",
        "chart": "📊",
        "chart_with_upwards_trend": "📈",
        "chart_with_downwards_trend": "📉",

        // Time
        "hourglass": "⏳",
        "stopwatch": "⏱️",
        "alarm_clock": "⏰",
        "calendar": "📅",

        // Money
        "moneybag": "💰",
        "dollar": "💵",
        "credit_card": "💳",

        // Transport
        "car": "🚗",
        "taxi": "🚕",
        "airplane": "✈️",
        "ship": "🚢",

        // Misc
        "tada": "🎉",
        "trophy": "🏆",
        "medal": "🏅",
        "crown": "👑",
        "gem": "💎",
        "bulb": "💡",
        "mag": "🔍",
        "pin": "📌",
        "pushpin": "📍",
        "paperclip": "📎",
        "scissors": "✂️",
        "pencil": "✏️",
        "memo": "📝"
    ]

    static func emoji(for tag: String) -> String? {
        tagToEmoji[tag.lowercased()]
    }
}

// MARK: - Settings

@MainActor
struct AppSettings {
    private static var defaults: UserDefaults { UserDefaults.standard }

    static var defaultServerURL: String {
        get { defaults.string(forKey: "defaultServerURL") ?? "https://push.godsapp.de" }
        set { defaults.set(newValue, forKey: "defaultServerURL") }
    }

    static var useToken: Bool {
        get { defaults.bool(forKey: "useToken") }
        set { defaults.set(newValue, forKey: "useToken") }
    }

    static var notificationsEnabled: Bool {
        get { defaults.bool(forKey: "notificationsEnabled") }
        set { defaults.set(newValue, forKey: "notificationsEnabled") }
    }

    static var hapticFeedback: Bool {
        get { defaults.object(forKey: "hapticFeedback") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "hapticFeedback") }
    }

    static var appTheme: AppTheme {
        get {
            guard let raw = defaults.string(forKey: "appTheme"),
                  let theme = AppTheme(rawValue: raw) else { return .system }
            return theme
        }
        set { defaults.set(newValue.rawValue, forKey: "appTheme") }
    }

    static var accentColorHex: String {
        get { defaults.string(forKey: "accentColorHex") ?? "#4574AD" }
        set { defaults.set(newValue, forKey: "accentColorHex") }
    }
}

enum AppTheme: String, CaseIterable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Hell"
        case .dark: return "Dunkel"
        }
    }
}
