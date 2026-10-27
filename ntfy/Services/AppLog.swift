import os.log

// MARK: - AppLog
// os.Logger statt print, damit Diagnose auch im Release geht; sensible Werte mit `privacy: .private`.

enum AppLog {
    private static let subsystem = "de.godsapp.ntfy"

    /// SSE-/Netzwerk-Events (NtfyService Verbindungsaufbau, Reconnects, Refresh)
    static let network = Logger(subsystem: subsystem, category: "network")

    /// Firebase Cloud Messaging (Token-Handling, Topic-Subscriptions)
    static let firebase = Logger(subsystem: subsystem, category: "firebase")

    /// Lokale Notifications (Scheduling, Badge, Autorisierung)
    static let notifications = Logger(subsystem: subsystem, category: "notifications")

    /// App-Lifecycle (AppDelegate, Push-Registrierung, Deep-Links)
    static let app = Logger(subsystem: subsystem, category: "app")

    /// UI-Ebene (Views, Bild-Laden, Aktionen)
    static let ui = Logger(subsystem: subsystem, category: "ui")
}
