import WidgetKit
import SwiftUI

// MARK: - Shared Data Model

struct WidgetEntry: TimelineEntry {
    let date: Date
    let messages: [WidgetMessage]
}

struct WidgetMessage: Identifiable, Codable {
    let messageId: String
    let topic: String
    let title: String
    let message: String
    let time: Int
    let priority: Int

    var id: String { messageId }

    var deepLinkURL: URL {
        URL(string: "ntfy://topic/\(topic)") ?? URL(string: "ntfy://")!
    }

    var timeDate: Date {
        Date(timeIntervalSince1970: TimeInterval(time))
    }
}

// MARK: - App Group Data Reading

private func readWidgetMessages() -> [WidgetMessage] {
    guard let containerURL = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: "group.de.godsapp.ntfy"
    ) else { return [] }

    let fileURL = containerURL.appendingPathComponent("widget_data.json")

    guard let data = try? Data(contentsOf: fileURL),
          let messages = try? JSONDecoder().decode([WidgetMessage].self, from: data) else {
        return []
    }
    return messages
}

// MARK: - Timeline Provider

struct NtfyTimelineProvider: TimelineProvider {

    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: Date(), messages: [
            WidgetMessage(messageId: "preview", topic: "ha-alerts",
                          title: "Bewegungsmelder", message: "Keller ausgelöst",
                          time: Int(Date().timeIntervalSince1970), priority: 3)
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        completion(WidgetEntry(date: Date(), messages: readWidgetMessages()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        let messages = readWidgetMessages()
        let entry = WidgetEntry(date: Date(), messages: messages)

        // Alle 15 Minuten neu laden (zusätzlich zu WidgetCenter.reloadAllTimelines())
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Small Widget View

struct SmallWidgetView: View {
    let entry: WidgetEntry

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "bell.fill")
                .font(.system(size: 24))
                .foregroundStyle(.white)

            Text("\(entry.messages.count)")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("ungelesen")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [Color(hex: "#1E88E5"), Color(hex: "#1565C0")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .widgetURL(URL(string: "ntfy://"))
    }
}

// MARK: - Medium Widget View

struct MediumWidgetView: View {
    let entry: WidgetEntry

    private var displayMessages: [WidgetMessage] {
        Array(entry.messages.prefix(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "bell.fill")
                    .font(.caption2)
                    .foregroundStyle(.blue)
                Text("ntfy+")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.blue)
                Spacer()
                Text("\(entry.messages.count) ungelesen")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            if displayMessages.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    Text("Keine ungelesenen Nachrichten")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(displayMessages) { msg in
                        Link(destination: msg.deepLinkURL) {
                            MessageRowView(message: msg)
                        }
                        if msg.id != displayMessages.last?.id {
                            Divider()
                                .padding(.leading, 12)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Message Row (Medium Widget)

struct MessageRowView: View {
    let message: WidgetMessage

    private var priorityColor: Color {
        switch message.priority {
        case 5: return Color(hex: "#E53935")
        case 4: return Color(hex: "#FB8C00")
        case 2: return Color(hex: "#43A047")
        case 1: return Color(hex: "#757575")
        default: return Color(hex: "#1E88E5")
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(priorityColor)
                .frame(width: 3, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text(message.topic)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Text(relativeTime(message.timeDate))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Text(message.title.isEmpty ? message.message : message.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "jetzt" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        if seconds < 86400 { return "\(seconds / 3600)h" }
        return "\(seconds / 86400)d"
    }
}

// MARK: - Color Hex Helper (Widget-intern, kein Import von Hauptapp möglich)

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Widget Definition

struct NtfyWidget: Widget {
    let kind: String = "NtfyWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NtfyTimelineProvider()) { entry in
            NtfyWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("ntfy+")
        .description("Ungelesene Nachrichten auf einen Blick.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Entry View (dispatches to Small/Medium)

struct NtfyWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: WidgetEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

// MARK: - Previews

#Preview(as: .systemSmall) {
    NtfyWidget()
} timeline: {
    WidgetEntry(date: Date(), messages: [
        WidgetMessage(messageId: "1", topic: "ha-alerts", title: "Test", message: "Body", time: Int(Date().timeIntervalSince1970), priority: 4)
    ])
}

#Preview(as: .systemMedium) {
    NtfyWidget()
} timeline: {
    WidgetEntry(date: Date(), messages: [
        WidgetMessage(messageId: "1", topic: "ha-alerts", title: "Bewegungsmelder", message: "Keller", time: Int(Date().timeIntervalSince1970), priority: 4),
        WidgetMessage(messageId: "2", topic: "uptime", title: "Service down", message: "push.godsapp.de", time: Int(Date().timeIntervalSince1970) - 300, priority: 5),
        WidgetMessage(messageId: "3", topic: "plex", title: "Wiedergabe", message: "Breaking Bad S01E01", time: Int(Date().timeIntervalSince1970) - 1800, priority: 3)
    ])
}
