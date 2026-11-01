import Foundation

/// Passendes SF Symbol und Farbe zu einem Topic-Namen.
struct TopicSymbol: Equatable, Sendable {
    let symbol: String
    let colorHex: String
}

/// Was ein Topic als Bild zeigt: ein SF Symbol oder ein bis zwei Buchstaben.
enum TopicGlyph: Equatable, Sendable {
    case symbol(String)
    case letter(String)
}

enum TopicSymbols {

    private struct Rule {
        let keywords: [String]
        let symbol: TopicSymbol
    }

    /// Reihenfolge ist Vorrang: `uptime-critical` soll als kritisch gelten, nicht als Uptime.
    private static let rules: [Rule] = [
        Rule(keywords: ["critical", "kritisch", "crit", "alarm", "alert", "urgent", "notfall"],
             symbol: TopicSymbol(symbol: "exclamationmark.octagon.fill", colorHex: "#E53935")),
        Rule(keywords: ["plex", "tautulli"],
             symbol: TopicSymbol(symbol: "play.rectangle.fill", colorHex: "#E5A00D")),
        Rule(keywords: ["sonarr", "serien", "series", "tv"],
             symbol: TopicSymbol(symbol: "tv.fill", colorHex: "#35C5F4")),
        Rule(keywords: ["radarr", "filme", "movies"],
             symbol: TopicSymbol(symbol: "film.fill", colorHex: "#FFA000")),
        Rule(keywords: ["nzb", "nzbget", "sabnzbd", "sab", "download", "downloads"],
             symbol: TopicSymbol(symbol: "arrow.down.circle.fill", colorHex: "#F5A623")),
        Rule(keywords: ["usenet", "newsgroups", "prowlarr"],
             symbol: TopicSymbol(symbol: "newspaper.fill", colorHex: "#607D8B")),
        Rule(keywords: ["audiobooks", "audiobook", "audiobookshelf", "hoerbuch", "hoerbuecher", "podcast"],
             symbol: TopicSymbol(symbol: "headphones", colorHex: "#8E5CC4")),
        Rule(keywords: ["docker", "watchtower", "container", "portainer"],
             symbol: TopicSymbol(symbol: "shippingbox.fill", colorHex: "#2496ED")),
        Rule(keywords: ["monitoring", "monitor", "kuma", "beszel"],
             symbol: TopicSymbol(symbol: "gauge.with.dots.needle.bottom.50percent", colorHex: "#009688")),
        Rule(keywords: ["uptime", "status", "health"],
             symbol: TopicSymbol(symbol: "waveform.path.ecg", colorHex: "#43A047")),
        Rule(keywords: ["github", "gitlab", "gitea", "git", "release", "releases"],
             symbol: TopicSymbol(symbol: "chevron.left.forwardslash.chevron.right", colorHex: "#24292F")),
        Rule(keywords: ["plausible", "umami", "analytics", "statistik", "stats"],
             symbol: TopicSymbol(symbol: "chart.bar.fill", colorHex: "#5850EC")),
        Rule(keywords: ["fahrtenbuch", "fahrt", "car"],
             symbol: TopicSymbol(symbol: "car.fill", colorHex: "#1E88E5")),
        Rule(keywords: ["homeassistant", "hass", "ha", "smarthome", "zuhause"],
             symbol: TopicSymbol(symbol: "house.fill", colorHex: "#18BCF2")),
        Rule(keywords: ["backup", "backups", "sicherung"],
             symbol: TopicSymbol(symbol: "externaldrive.fill", colorHex: "#6D4C41")),
        Rule(keywords: ["mail", "email", "postfach"],
             symbol: TopicSymbol(symbol: "envelope.fill", colorHex: "#1565C0")),
        Rule(keywords: ["n8n", "automation", "workflow"],
             symbol: TopicSymbol(symbol: "point.3.connected.trianglepath.dotted", colorHex: "#EA4B71")),
        Rule(keywords: ["test", "debug"],
             symbol: TopicSymbol(symbol: "hammer.fill", colorHex: "#757575")),
    ]

    /// Kurze Schlüsselwörter treffen nur als ganzes Wort, sonst wäre `ha` in jedem `chat`.
    private static let minimumSubstringLength = 4

    /// Zuordnung zum Topic-Namen; erst ganze Wörter (getrennt durch `-`, `_`, `.`), dann Teilwörter.
    static func match(for topicName: String) -> TopicSymbol? {
        let name = topicName.lowercased()
        let words = Set(name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        guard !words.isEmpty else { return nil }

        if let rule = rules.first(where: { rule in rule.keywords.contains(where: words.contains) }) {
            return rule.symbol
        }
        let rule = rules.first { rule in
            rule.keywords.contains { $0.count >= minimumSubstringLength && name.contains($0) }
        }
        return rule?.symbol
    }

    /// Eigene Wahl vor Zuordnung: gewähltes Icon, dann eigener Buchstabe, dann passendes Symbol, sonst Anfangsbuchstabe.
    static func glyph(topicName: String, iconName: String?, customLetter: String?) -> TopicGlyph {
        if let iconName, !iconName.isEmpty {
            return .symbol(iconName)
        }
        if let customLetter, !customLetter.isEmpty {
            return .letter(customLetter)
        }
        if let match = match(for: topicName) {
            return .symbol(match.symbol)
        }
        let first = String(topicName.prefix(1)).uppercased()
        return .letter(first.isEmpty ? "?" : first)
    }

    /// Eigene Farbe vor zugeordneter; nil heißt: aus dem Namen ableiten.
    static func colorHex(topicName: String, colorHex: String?) -> String? {
        if let colorHex, !colorHex.isEmpty {
            return colorHex
        }
        return match(for: topicName)?.colorHex
    }
}
