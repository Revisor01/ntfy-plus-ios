import Foundation
import UserNotifications

// MARK: - PushPayload
//
// Liest die FCM-Data-Felder, die der ntfy-Server in den APNs-Payload legt
// (alle Werte als String, siehe ntfy server/server_firebase.go):
// id, time, event, topic, sequence_id, priority, tags (kommagetrennt), click, icon,
// title, message, content_type, encoding, actions (JSON-String),
// attachment_name/_type/_size/_expires/_url, poll_id, truncated.

struct PushPayload {
    let userInfo: [AnyHashable: Any]

    var event: String { string("event") ?? "message" }
    var topic: String { string("topic") ?? "" }
    var id: String? { nonEmpty("id") }
    var pollId: String? { nonEmpty("poll_id") }

    var priority: Int? {
        guard let value = string("priority"), let int = Int(value), (1...5).contains(int) else {
            return nil
        }
        return int
    }

    func string(_ key: String) -> String? {
        if let value = userInfo[key] as? String {
            return value
        }
        if let number = userInfo[key] as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    func nonEmpty(_ key: String) -> String? {
        guard let value = string(key), !value.isEmpty else { return nil }
        return value
    }

    /// Baut aus einem normalen "message"-Push ein ntfy-JSON-Objekt,
    /// das die App als NtfyMessage dekodieren kann.
    func messageDictionary() -> [String: Any]? {
        guard event == "message", let id = self.id, !topic.isEmpty else { return nil }

        var dict: [String: Any] = [
            "id": id,
            "time": Int(string("time") ?? "") ?? Int(Date().timeIntervalSince1970),
            "event": "message",
            "topic": topic
        ]

        // base64-kodierte Nachrichten (Binaerdaten) nicht als Text uebernehmen
        if string("encoding") != "base64", let message = nonEmpty("message") {
            dict["message"] = message
        }
        if let title = nonEmpty("title") { dict["title"] = title }
        if let click = nonEmpty("click") { dict["click"] = click }
        if let icon = nonEmpty("icon") { dict["icon"] = icon }
        if let sequenceId = nonEmpty("sequence_id") { dict["sequence_id"] = sequenceId }
        if let priority = self.priority { dict["priority"] = priority }

        if let tagString = nonEmpty("tags") {
            let tags = tagString
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if !tags.isEmpty {
                dict["tags"] = tags
            }
        }

        if let actionsString = nonEmpty("actions"),
           let data = actionsString.data(using: .utf8),
           let rawActions = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
            // Nur Actions mit den Pflichtfeldern der App (action, label) uebernehmen —
            // sonst scheitert das Dekodieren der ganzen Nachricht in der App.
            let actions = rawActions.filter { $0["action"] is String && $0["label"] is String }
            if !actions.isEmpty {
                dict["actions"] = actions
            }
        }

        if let attachmentURL = nonEmpty("attachment_url") {
            var attachment: [String: Any] = ["url": attachmentURL]
            if let name = nonEmpty("attachment_name") { attachment["name"] = name }
            if let type = nonEmpty("attachment_type") { attachment["type"] = type }
            if let size = nonEmpty("attachment_size").flatMap({ Int($0) }) { attachment["size"] = size }
            if let expires = nonEmpty("attachment_expires").flatMap({ Int($0) }) { attachment["expires"] = expires }
            dict["attachment"] = attachment
        }

        return dict
    }
}

// MARK: - Priority → Darstellung

enum PriorityStyle {
    /// Uebertraegt die ntfy-Prioritaet (1–5) auf Interruption-Level, Relevanz und Sound —
    /// analog zur bisherigen lokalen Notification-Logik der App:
    /// 1 = passiv/lautlos, 2–4 = aktiv mit Standard-Sound, 5 = time-sensitive.
    /// Critical Alerts werden bewusst nicht verwendet (kein Entitlement).
    static func apply(priority: Int?, to content: UNMutableNotificationContent) {
        let level = priority ?? 3
        switch level {
        case 1:
            content.interruptionLevel = .passive
            content.relevanceScore = 0.1
            content.sound = nil
        case 2:
            content.interruptionLevel = .active
            content.relevanceScore = 0.3
        case 4:
            content.interruptionLevel = .active
            content.relevanceScore = 0.8
        case 5:
            content.interruptionLevel = .timeSensitive
            content.relevanceScore = 1.0
        default:
            content.interruptionLevel = .active
            content.relevanceScore = 0.5
        }
        if level > 1 && content.sound == nil {
            content.sound = .default
        }
    }

    /// In der App stummgeschaltetes Topic: still zustellen (kein Ton, passiv).
    /// Muss nach `apply(priority:to:)` aufgerufen werden, das den Ton sonst wieder setzt.
    static func applyMuted(to content: UNMutableNotificationContent) {
        content.sound = nil
        content.interruptionLevel = .passive
        content.relevanceScore = min(content.relevanceScore, 0.1)
    }
}
