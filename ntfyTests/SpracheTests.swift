import Foundation
import Testing

// Ohne deutsche Grundsprache zeigt iOS Systemknöpfe englisch an (geprüft 27.10.2026).
@Suite("Sprache der App")
struct SpracheTests {

    @Test("Die App meldet Deutsch als Grund- und einzige Sprache")
    func deutsch() {
        let info = Bundle.main.infoDictionary ?? [:]
        #expect(info["CFBundleDevelopmentRegion"] as? String == "de")
        #expect(info["CFBundleLocalizations"] as? [String] == ["de"])
        #expect(Bundle.main.preferredLocalizations.first == "de")
    }
}
