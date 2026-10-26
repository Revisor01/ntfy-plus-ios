import Foundation
import Testing
@testable import ntfy

@Suite("Gespeicherte Anhänge und Aktionen")
struct StoredModelTests {

    @Test("Anhang: Bilderkennung, Dateiname und Ablauf")
    func storedAttachment() {
        let image = StoredAttachment(from: NtfyAttachment(
            name: nil, type: "image/png", size: 10, expires: 1700000000, url: nil))
        #expect(image.isImage == true)
        #expect(image.fileName == "attachment")
        #expect(image.expiryDate == Date(timeIntervalSince1970: 1700000000))

        let text = StoredAttachment(from: NtfyAttachment(
            name: "log.txt", type: "text/plain", size: nil, expires: 0, url: nil))
        #expect(text.isImage == false)
        #expect(text.fileName == "log.txt")
        #expect(text.expiryDate == nil)
        #expect(text.formattedSize == nil)

        let untyped = StoredAttachment(from: NtfyAttachment(
            name: nil, type: nil, size: nil, expires: nil, url: nil))
        #expect(untyped.isImage == false)
        #expect(untyped.expiryDate == nil)
    }

    @Test("Aktion übernimmt alle Felder, auch den Kopierwert")
    func storedAction() throws {
        let source = NtfyAction(action: "copy", label: "Code", url: nil, method: nil,
                                headers: nil, body: nil, clear: false, value: "123456")
        let stored = StoredAction(from: source)
        #expect(stored.action == "copy")
        #expect(stored.label == "Code")
        #expect(stored.value == "123456")
        #expect(stored.clear == false)

        let roundTrip = try JSONDecoder().decode(StoredAction.self,
                                                 from: JSONEncoder().encode(stored))
        #expect(roundTrip == stored)
    }
}
