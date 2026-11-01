import Testing
@testable import ntfy

@Suite("Topic-Symbole")
struct TopicSymbolsTests {

    @Test("Bekannte Topics bekommen ihr Symbol und ihre Farbe", arguments: [
        ("plex", "play.rectangle.fill", "#E5A00D"),
        ("sonarr", "tv.fill", "#35C5F4"),
        ("nzb", "arrow.down.circle.fill", "#F5A623"),
        ("usenet", "newspaper.fill", "#607D8B"),
        ("audiobooks", "headphones", "#8E5CC4"),
        ("docker", "shippingbox.fill", "#2496ED"),
        ("monitoring", "gauge.with.dots.needle.bottom.50percent", "#009688"),
        ("uptime", "waveform.path.ecg", "#43A047"),
        ("uptime-critical", "exclamationmark.octagon.fill", "#E53935"),
        ("github", "chevron.left.forwardslash.chevron.right", "#24292F"),
        ("plausible", "chart.bar.fill", "#5850EC"),
        ("fahrtenbuch", "car.fill", "#1E88E5"),
    ])
    func bekannteTopics(name: String, symbol: String, colorHex: String) {
        #expect(TopicSymbols.match(for: name) == TopicSymbol(symbol: symbol, colorHex: colorHex))
    }

    @Test("Teilwörter und Schreibweisen treffen")
    func teilwoerter() {
        #expect(TopicSymbols.match(for: "Plex")?.symbol == "play.rectangle.fill")
        #expect(TopicSymbols.match(for: "server_docker")?.symbol == "shippingbox.fill")
        #expect(TopicSymbols.match(for: "serveruptime")?.symbol == "waveform.path.ecg")
        #expect(TopicSymbols.match(for: "uptimekuma")?.symbol == "gauge.with.dots.needle.bottom.50percent")
        #expect(TopicSymbols.match(for: "uptimecritical")?.symbol == "exclamationmark.octagon.fill")
        #expect(TopicSymbols.match(for: "audiobookshelf-neu")?.symbol == "headphones")
        #expect(TopicSymbols.match(for: "github.releases")?.symbol == "chevron.left.forwardslash.chevron.right")
    }

    @Test("Kritisch hat Vorrang vor dem Dienst")
    func kritischVorrang() {
        #expect(TopicSymbols.match(for: "critical-uptime")?.symbol == "exclamationmark.octagon.fill")
        #expect(TopicSymbols.match(for: "docker-alert")?.symbol == "exclamationmark.octagon.fill")
    }

    @Test("Kurze Schlüsselwörter nur als ganzes Wort")
    func kurzeSchluesselwoerter() {
        #expect(TopicSymbols.match(for: "ha")?.symbol == "house.fill")
        #expect(TopicSymbols.match(for: "chat") == nil)
        #expect(TopicSymbols.match(for: "sabbath") == nil)
        #expect(TopicSymbols.match(for: "sab")?.symbol == "arrow.down.circle.fill")
    }

    @Test("Unbekannte Topics haben keine Zuordnung")
    func unbekannt() {
        #expect(TopicSymbols.match(for: "einkaufsliste") == nil)
        #expect(TopicSymbols.match(for: "") == nil)
        #expect(TopicSymbols.match(for: "---") == nil)
    }

    @Test("Rückfall: Anfangsbuchstabe, bei leerem Namen ein Fragezeichen")
    func rueckfall() {
        #expect(TopicSymbols.glyph(topicName: "einkaufsliste", iconName: nil, customLetter: nil) == .letter("E"))
        #expect(TopicSymbols.glyph(topicName: "", iconName: nil, customLetter: nil) == .letter("?"))
        #expect(TopicSymbols.colorHex(topicName: "einkaufsliste", colorHex: nil) == nil)
    }

    @Test("Eigene Wahl überschreibt die Zuordnung")
    func eigeneWahl() {
        #expect(TopicSymbols.glyph(topicName: "plex", iconName: nil, customLetter: nil) == .symbol("play.rectangle.fill"))
        #expect(TopicSymbols.glyph(topicName: "plex", iconName: "star.fill", customLetter: nil) == .symbol("star.fill"))
        #expect(TopicSymbols.glyph(topicName: "plex", iconName: nil, customLetter: "PX") == .letter("PX"))
        #expect(TopicSymbols.glyph(topicName: "plex", iconName: "star.fill", customLetter: "PX") == .symbol("star.fill"))
        #expect(TopicSymbols.glyph(topicName: "plex", iconName: "", customLetter: "") == .symbol("play.rectangle.fill"))
        #expect(TopicSymbols.colorHex(topicName: "plex", colorHex: "#123456") == "#123456")
        #expect(TopicSymbols.colorHex(topicName: "plex", colorHex: nil) == "#E5A00D")
        #expect(TopicSymbols.colorHex(topicName: "plex", colorHex: "") == "#E5A00D")
    }
}
