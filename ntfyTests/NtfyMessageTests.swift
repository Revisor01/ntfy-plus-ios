import Foundation
import Testing
@testable import ntfy

@Suite("Nachrichten aus der ntfy-API")
struct NtfyMessageTests {

    private func decode(_ json: String) throws -> NtfyMessage {
        try JSONDecoder().decode(NtfyMessage.self, from: Data(json.utf8))
    }

    @Test("Vollständige Nachricht mit allen optionalen Feldern")
    func decodesAllFields() throws {
        let message = try decode("""
        {
          "id": "sPs71M8A2T",
          "time": 1700000000,
          "expires": 1700043200,
          "event": "message",
          "topic": "backups",
          "message": "Sicherung **fertig**",
          "title": "Nachtlauf",
          "tags": ["rocket", "unbekannt", "FIRE"],
          "priority": 4,
          "click": "https://example.com/log",
          "icon": "https://example.com/icon.png",
          "sequence_id": "seq-1",
          "content_type": "text/Markdown",
          "actions": [
            {"action": "copy", "label": "Kopieren", "value": "abc", "clear": true},
            {"action": "http", "label": "Neu starten", "url": "https://example.com/restart",
             "method": "POST", "headers": {"X-Token": "t"}, "body": "{}"}
          ],
          "attachment": {"name": "log.txt", "type": "text/plain", "size": 2048,
                         "expires": 1700086400, "url": "https://example.com/file/log.txt"}
        }
        """)

        #expect(message.id == "sPs71M8A2T")
        #expect(message.time == 1700000000)
        #expect(message.expires == 1700043200)
        #expect(message.event == "message")
        #expect(message.topic == "backups")
        #expect(message.displayTitle == "Nachtlauf")
        #expect(message.displayMessage == "Sicherung **fertig**")
        #expect(message.sequenceId == "seq-1")
        #expect(message.isMarkdown == true)
        #expect(message.priorityLevel == .high)
        #expect(message.emojiTags == ["🚀", "🔥"])
        #expect(message.date == Date(timeIntervalSince1970: 1700000000))
        #expect(message.click == "https://example.com/log")
        #expect(message.icon == "https://example.com/icon.png")

        let actions = try #require(message.actions)
        #expect(actions.count == 2)
        #expect(actions[0].action == "copy")
        #expect(actions[0].value == "abc")
        #expect(actions[0].clear == true)
        #expect(actions[1].method == "POST")
        #expect(actions[1].headers == ["X-Token": "t"])
        #expect(actions[1].body == "{}")

        let attachment = try #require(message.attachment)
        #expect(attachment.name == "log.txt")
        #expect(attachment.size == 2048)
        #expect(attachment.url == "https://example.com/file/log.txt")
    }

    @Test("Minimale Nachricht ohne optionale Felder")
    func decodesMinimalMessage() throws {
        let message = try decode("""
        {"id": "x1", "time": 1, "event": "message", "topic": "alerts"}
        """)

        #expect(message.title == nil)
        #expect(message.message == nil)
        #expect(message.tags == nil)
        #expect(message.actions == nil)
        #expect(message.attachment == nil)
        #expect(message.displayTitle == "alerts")
        #expect(message.displayMessage == "")
        #expect(message.priorityLevel == .default)
        #expect(message.emojiTags == [])
        #expect(message.isMarkdown == false)
    }

    @Test("Fehlende Pflichtfelder werfen einen Fehler")
    func rejectsMissingTopic() {
        #expect(throws: DecodingError.self) {
            try decode(#"{"id": "x1", "time": 1, "event": "message"}"#)
        }
    }

    @Test("Prioritäten 1 bis 5, alles andere wird Standard")
    func priorityMapping() throws {
        #expect(Priority.allCases.map(\.rawValue) == [1, 2, 3, 4, 5])
        #expect(Priority.urgent.name == "Dringend")
        #expect(Priority.min.icon == "arrow.down.to.line")

        let urgent = try decode(#"{"id":"a","time":1,"event":"message","topic":"t","priority":5}"#)
        #expect(urgent.priorityLevel == .urgent)
        let outOfRange = try decode(#"{"id":"a","time":1,"event":"message","topic":"t","priority":9}"#)
        #expect(outOfRange.priorityLevel == .default)
    }

    @Test("Markdown nur bei content_type text/markdown")
    func markdownDetection() throws {
        let plain = try decode(#"{"id":"a","time":1,"event":"message","topic":"t","content_type":"text/plain"}"#)
        #expect(plain.isMarkdown == false)
        let withCharset = try decode(#"{"id":"a","time":1,"event":"message","topic":"t","content_type":"text/markdown; charset=utf-8"}"#)
        #expect(withCharset.isMarkdown == true)
    }

    @Test("Tags werden unabhängig von Groß- und Kleinschreibung zu Emoji")
    func emojiMap() {
        #expect(EmojiMap.emoji(for: "rocket") == "🚀")
        #expect(EmojiMap.emoji(for: "TADA") == "🎉")
        #expect(EmojiMap.emoji(for: "gibt_es_nicht") == nil)
    }
}
