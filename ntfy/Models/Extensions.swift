import SwiftUI

// MARK: - Date Extensions

extension Date {
    func timeAgo() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = Locale(identifier: "de_DE")
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    func formatted(style: DateFormatter.Style = .medium) -> String {
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
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            formatter.locale = Locale(identifier: "de_DE")
            return formatter.string(from: self)
        } else if isYesterday {
            return "Gestern"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "dd.MM.yy"
            return formatter.string(from: self)
        }
    }
}

// MARK: - String Extensions

extension String {
    var isValidURL: Bool {
        if let url = URL(string: self) {
            return url.scheme != nil && url.host != nil
        }
        return false
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
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            formatter.timeZone = TimeZone(identifier: "UTC")
            if let startDate = formatter.date(from: amzDate) {
                return startDate.addingTimeInterval(seconds)
            }
        }

        // 3. Azure SAS: se= (ISO8601 standard)
        if let seStr = params["se"] {
            let formatter = ISO8601DateFormatter()
            if let date = formatter.date(from: seStr) {
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
