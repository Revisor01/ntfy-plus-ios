import Foundation
import Testing
@testable import ntfy

@Suite("Eingaben prüfen und URLs bilden")
struct ExtensionsTests {

    @Test("Topic-Namen nach der Server-Regel")
    func topicNames() {
        #expect("backups".isValidNtfyTopicName == true)
        #expect("Home_Assistant-2".isValidNtfyTopicName == true)
        #expect(String(repeating: "a", count: 64).isValidNtfyTopicName == true)

        #expect("".isValidNtfyTopicName == false)
        #expect(String(repeating: "a", count: 65).isValidNtfyTopicName == false)
        #expect("mit leerzeichen".isValidNtfyTopicName == false)
        #expect("grüße".isValidNtfyTopicName == false)
        #expect("a/b".isValidNtfyTopicName == false)
    }

    @Test("Nur http- und https-URLs mit Host sind gültig")
    func validURLs() {
        #expect("https://ntfy.sh".isValidURL == true)
        #expect("  http://example.com:8080/pfad  ".isValidURL == true)

        #expect("ntfy.sh".isValidURL == false)
        #expect("ftp://example.com".isValidURL == false)
        #expect("https://".isValidURL == false)
        #expect("https://exa mple.com".isValidURL == false)
        #expect("".isValidURL == false)
    }

    @Test("Server-URL wird ergänzt und ohne Schrägstrich am Ende gespeichert")
    func normalizedServerURL() {
        #expect("ntfy.sh/".normalizedServerURL() == "https://ntfy.sh")
        #expect(" http://example.com// ".normalizedServerURL() == "http://example.com")
        #expect("https://example.com/ntfy/".normalizedServerURL() == "https://example.com/ntfy")
        #expect("ntfy.sh/".normalizedServerURL(addProtocolIfMissing: false) == "ntfy.sh")
    }

    @Test("Klick-URLs aus fremden Nachrichten nur mit Web-Schema")
    func safeWebURL() throws {
        #expect(try #require(URL(string: "HTTPS://example.com")).isSafeWebURL == true)
        #expect(try #require(URL(string: "http://example.com")).isSafeWebURL == true)
        #expect(try #require(URL(string: "javascript:alert(1)")).isSafeWebURL == false)
        #expect(try #require(URL(string: "data:text/plain,hallo")).isSafeWebURL == false)
        #expect(try #require(URL(string: "tel:+491234")).isSafeWebURL == false)
    }

    @Test("Ablauf signierter Anhang-URLs")
    func signedURLExpiry() throws {
        let generic = try #require(URL(string: "https://example.com/f?Expires=1700000000"))
        #expect(generic.expiryDate == Date(timeIntervalSince1970: 1700000000))

        let aws = try #require(URL(string:
            "https://example.com/f?X-Amz-Date=20240101T000000Z&X-Amz-Expires=3600"))
        #expect(aws.expiryDate == Date(timeIntervalSince1970: 1704070800))

        let azure = try #require(URL(string: "https://example.com/f?se=2024-01-01T00:00:00Z"))
        #expect(azure.expiryDate == Date(timeIntervalSince1970: 1704067200))

        let plain = try #require(URL(string: "https://example.com/f?foo=bar"))
        #expect(plain.expiryDate == nil)
        #expect(try #require(URL(string: "https://example.com/f")).expiryDate == nil)
    }

    @Test("Query-Parameter als Wörterbuch")
    func queryParameters() throws {
        let url = try #require(URL(string: "https://example.com/?a=1&b=zwei"))
        #expect(url.queryParameters == ["a": "1", "b": "zwei"])
    }

    @Test("Optionale Zeichenketten")
    func optionalStrings() {
        let none: String? = nil
        let empty: String? = ""
        let text: String? = "x"
        #expect(none.orEmpty == "")
        #expect(none.isNilOrEmpty == true)
        #expect(empty.isNilOrEmpty == true)
        #expect(text.isNilOrEmpty == false)
        #expect(text.orEmpty == "x")
        #expect("  a b \n".trimmed() == "a b")
        #expect(["✅", "🔥"].joinedEmojis() == "✅ 🔥")
    }
}
