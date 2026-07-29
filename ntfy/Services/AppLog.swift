import os.log

// MARK: - AppLog
//
// Zentraler Logging-Wrapper ueber os.Logger mit expliziten Privacy-Annotationen.
// Ersetzt print()-Aufrufe im gesamten ntfy-Target. Die NotificationServiceExtension
// nutzt bereits os.Logger — dieser Wrapper folgt demselben, projektintern etablierten
// Muster, damit Diagnose auch in Release-Builds moeglich bleibt (im Gegensatz zu
// #if DEBUG, das Logs in Release komplett entfernen wuerde).
//
// Sensible Werte (APNs-/FCM-Token, Topic-Namen — bei ntfy das Zugangsgeheimnis)
// werden an der Aufrufstelle mit `privacy: .private` interpoliert und in Release
// redigiert (`<private>`). Nicht-sensible Werte (Statuscodes, Zaehler, Fehlerkategorien)
// duerfen `privacy: .public` verwenden.

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
