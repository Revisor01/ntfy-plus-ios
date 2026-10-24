import SwiftUI
import SwiftData

// MARK: - Date Extensions

/// Zwischengespeicherte Formatter — das Erzeugen eines DateFormatter ist teuer und
/// wurde bisher bei jedem Zeilen-Render (TopicRow/MessageRow) wiederholt.
/// DateFormatter, RelativeDateTimeFormatter und ISO8601DateFormatter sind seit iOS 7
/// thread-safe beim Formatieren/Parsen; die Instanzen werden nach der Konfiguration
/// nie mehr veraendert, daher ist `nonisolated(unsafe)` hier unbedenklich.
enum CachedFormatters {
    nonisolated(unsafe) static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = Locale(identifier: "de_DE")
        return formatter
    }()

    static let mediumDateShortTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "de_DE")
        return formatter
    }()

    static let shortTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "de_DE")
        return formatter
    }()

    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yy"
        formatter.locale = Locale(identifier: "de_DE")
        return formatter
    }()

    static let amzDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    nonisolated(unsafe) static let iso8601: ISO8601DateFormatter = ISO8601DateFormatter()
}

extension Date {
    func timeAgo() -> String {
        CachedFormatters.relative.localizedString(for: self, relativeTo: Date())
    }

    func formatted(style: DateFormatter.Style = .medium) -> String {
        if style == .medium {
            return CachedFormatters.mediumDateShortTime.string(from: self)
        }
        let formatter = DateFormatter()
        formatter.dateStyle = style
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "de_DE")
        return formatter.string(from: self)
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }

    var isYesterday: Bool {
        Calendar.current.isDateInYesterday(self)
    }

    func smartFormatted() -> String {
        if isToday {
            return CachedFormatters.shortTime.string(from: self)
        } else if isYesterday {
            return "Gestern"
        } else {
            return CachedFormatters.shortDate.string(from: self)
        }
    }
}

// MARK: - String Extensions

extension String {
    /// true fuer http(s)-URLs mit nicht-leerem Host und ohne Leerzeichen.
    /// Fuehrende/abschliessende Leerzeichen werden ignoriert (Eingaben werden vor
    /// der Verwendung ohnehin getrimmt).
    var isValidURL: Bool {
        let candidate = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty,
              !candidate.contains(where: { $0.isWhitespace }),
              let components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.isEmpty else {
            return false
        }
        return true
    }

    /// Gueltiger ntfy-Topic-Name: 1–64 Zeichen aus A–Z, a–z, 0–9, "-" und "_".
    /// (Entspricht der Server-Regel `^[-_A-Za-z0-9]{1,64}$`.)
    var isValidNtfyTopicName: Bool {
        let byteCount = utf8.count
        guard byteCount >= 1 && byteCount <= 64 else { return false }
        for byte in utf8 {
            switch byte {
            case 48...57,   // 0-9
                 65...90,   // A-Z
                 97...122,  // a-z
                 45,        // -
                 95:        // _
                continue
            default:
                return false
            }
        }
        return true
    }

    func trimmed() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isNotEmpty: Bool {
        !isEmpty
    }

    /// Normalisiert eine Server-URL: trimmt Whitespace, fügt optional https:// hinzu,
    /// und entfernt abschließende Slashes.
    /// - Parameter addProtocolIfMissing: true für Neu-Eingaben ohne Protokoll (Onboarding),
    ///   false für bereits validierte URLs aus bestehenden Server-Objekten.
    func normalizedServerURL(addProtocolIfMissing: Bool = true) -> String {
        var result = self.trimmingCharacters(in: .whitespacesAndNewlines)
        if addProtocolIfMissing {
            if !result.hasPrefix("http://") && !result.hasPrefix("https://") {
                result = "https://" + result
            }
        }
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return result
    }
}

// MARK: - Color Extensions

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    func toHex() -> String {
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0

        // getRed:green:blue:alpha: konvertiert automatisch aus jedem Farbraum inkl. Grayscale
        if uiColor.getRed(&r, green: &g, blue: &b, alpha: &a) {
            return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
        }

        // Fallback fuer nicht-konvertierbare Farbraeume
        guard let components = uiColor.cgColor.components else { return "#000000" }
        if components.count == 2 {
            // Grayscale: [white, alpha]
            let w = Int(components[0] * 255)
            return String(format: "#%02X%02X%02X", w, w, w)
        }
        guard components.count >= 3 else { return "#000000" }
        return String(format: "#%02X%02X%02X",
                      Int(components[0] * 255),
                      Int(components[1] * 255),
                      Int(components[2] * 255))
    }

    static let predefinedColors: [(name: String, color: Color)] = [
        ("Blau", .blue),
        ("Grün", .green),
        ("Orange", .orange),
        ("Rot", .red),
        ("Lila", .purple),
        ("Pink", .pink),
        ("Türkis", .teal),
        ("Indigo", .indigo),
        ("Mint", .mint),
        ("Cyan", .cyan),
        ("Braun", .brown),
        ("Grau", .gray)
    ]
}

// MARK: - View Extensions

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    func hapticFeedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        if AppSettings.hapticFeedback {
            let generator = UIImpactFeedbackGenerator(style: style)
            generator.impactOccurred()
        }
    }

    func onFirstAppear(perform action: @escaping () -> Void) -> some View {
        modifier(FirstAppearModifier(action: action))
    }
}

struct FirstAppearModifier: ViewModifier {
    let action: () -> Void
    @State private var hasAppeared = false

    func body(content: Content) -> some View {
        content.onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            action()
        }
    }
}

// MARK: - Array Extensions

extension Array where Element == String {
    func joinedEmojis() -> String {
        joined(separator: " ")
    }
}

// MARK: - Optional Extensions

extension Optional where Wrapped == String {
    var orEmpty: String {
        self ?? ""
    }

    var isNilOrEmpty: Bool {
        self?.isEmpty ?? true
    }
}

// MARK: - URL Extensions

extension URL {
    /// Nur sichere Web-Schemes (http/https) — verhindert javascript:/data:/file:/tel:
    /// usw. aus fremden Nachrichten (Markdown-Links, Klick-URLs, Anhaenge).
    var isSafeWebURL: Bool {
        guard let scheme = scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    var queryParameters: [String: String]? {
        guard let components = URLComponents(url: self, resolvingAgainstBaseURL: true),
              let queryItems = components.queryItems else { return nil }
        return queryItems.reduce(into: [String: String]()) { result, item in
            result[item.name] = item.value
        }
    }

    /// Parst ablauf-relevante Query-Parameter aus signierten URLs.
    /// Unterstützt: AWS S3 (Expires/X-Amz-Expires+X-Amz-Date), Azure SAS (se=), generisch (Expires=).
    var expiryDate: Date? {
        guard let params = queryParameters else { return nil }

        // 1. Generisches Unix-Timestamp "Expires" (S3 vorgeneriert, ntfy selbst)
        if let expiresStr = params["Expires"], let ts = TimeInterval(expiresStr) {
            return Date(timeIntervalSince1970: ts)
        }

        // 2. AWS Signature v4: X-Amz-Expires (Sekunden) + X-Amz-Date (ISO8601 kompakt)
        if let amzExpires = params["X-Amz-Expires"],
           let seconds = TimeInterval(amzExpires),
           let amzDate = params["X-Amz-Date"] {
            if let startDate = CachedFormatters.amzDate.date(from: amzDate) {
                return startDate.addingTimeInterval(seconds)
            }
        }

        // 3. Azure SAS: se= (ISO8601 standard)
        if let seStr = params["se"] {
            if let date = CachedFormatters.iso8601.date(from: seStr) {
                return date
            }
        }

        return nil
    }
}

// MARK: - Binding Extensions

extension Binding where Value == String {
    func max(_ limit: Int) -> Self {
        if self.wrappedValue.count > limit {
            DispatchQueue.main.async {
                self.wrappedValue = String(self.wrappedValue.prefix(limit))
            }
        }
        return self
    }
}

// MARK: - Topic-/Badge-Helfer

/// Gemeinsame Schritte fuer Views, die Topics entfernen oder Gelesen-Status aendern
/// (TopicsView, MessagesView, SettingsView) — damit alle Pfade identisch aufraeumen.
@MainActor
enum TopicActions {
    /// Setzt das App-Badge auf die Anzahl ungelesener Nachrichten ueber alle Topics.
    static func updateBadge(context: ModelContext) async {
        let unreadPredicate = #Predicate<StoredMessage> { !$0.isRead }
        let descriptor = FetchDescriptor<StoredMessage>(predicate: unreadPredicate)
        let unreadCount = (try? context.fetchCount(descriptor)) ?? 0
        await NotificationService.shared.setBadgeCount(unreadCount)
    }

    /// Berechnet den denormalisierten unreadCount eines Topics aus den gespeicherten Nachrichten neu.
    static func recalculateUnreadCount(for topic: Topic, context: ModelContext) {
        let topicId = topic.id
        let predicate = #Predicate<StoredMessage> { message in
            message.topic?.id == topicId && message.isRead == false
        }
        let descriptor = FetchDescriptor<StoredMessage>(predicate: predicate)
        if let count = try? context.fetchCount(descriptor) {
            topic.unreadCount = count
        }
    }

    /// Entfernt ein Topic vollstaendig: SSE- und FCM-Abo beenden, zugestellte
    /// Benachrichtigungen entfernen, Nachrichten + DeletedMessage-Records loeschen,
    /// Topic loeschen, speichern, Badge und Widget aktualisieren.
    /// Nach dem Aufruf darf auf `topic` nicht mehr zugegriffen werden.
    static func remove(_ topic: Topic, context: ModelContext, ntfyService: NtfyService) {
        // Alle benoetigten Werte kopieren, BEVOR das Model geloescht wird
        let topicId = topic.id
        let topicName = topic.name
        let serverURL = topic.serverURL

        // SSE-Abo beenden
        ntfyService.unsubscribe(serverURL: serverURL, topic: topicName)

        // FCM-Topics sind nur ueber den Namen adressiert — nur abmelden, wenn kein
        // anderes Topic gleichen Namens (auf einem anderen Server) uebrig bleibt.
        let sameNamePredicate = #Predicate<Topic> { other in
            other.name == topicName && other.id != topicId
        }
        let sameNameCount = (try? context.fetchCount(FetchDescriptor<Topic>(predicate: sameNamePredicate))) ?? 0
        if sameNameCount == 0 {
            FirebaseService.shared.unsubscribeFromTopic(serverURL: serverURL, topic: topicName)
        }

        // Nachrichten des Topics loeschen (inkl. zugehoeriger Benachrichtigungen)
        let messagePredicate = #Predicate<StoredMessage> { message in
            message.topic?.id == topicId
        }
        let messages = (try? context.fetch(FetchDescriptor<StoredMessage>(predicate: messagePredicate))) ?? []
        for message in messages {
            NotificationService.shared.removeNotification(withIdentifier: message.messageId)
            context.delete(message)
        }

        // DeletedMessage-Records des Topics loeschen
        let deletedPredicate = #Predicate<DeletedMessage> { deleted in
            deleted.topicName == topicName && deleted.serverURL == serverURL
        }
        let deletedRecords = (try? context.fetch(FetchDescriptor<DeletedMessage>(predicate: deletedPredicate))) ?? []
        for record in deletedRecords {
            context.delete(record)
        }

        // Topic selbst loeschen
        context.delete(topic)
        try? context.save()

        ntfyService.writeWidgetData(context: context)

        Task {
            // Gruppierte Benachrichtigungen (threadIdentifier = Topic-Name) entfernen
            if sameNameCount == 0 {
                await NotificationService.shared.removeNotifications(forTopic: topicName)
            }
            await updateBadge(context: context)
        }
    }
}
