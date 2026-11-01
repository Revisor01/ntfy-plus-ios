import SwiftUI
import SwiftData

struct TopicRow: View {
    let topic: Topic

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            topicIcon

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                HStack {
                    Text(topic.name)
                        .font(AppFonts.headline)
                        .lineLimit(1)

                    if topic.isMuted {
                        Image(systemName: AppIcons.mute)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Stummgeschaltet")
                    }

                    Spacer()

                    if let lastMessageAt = topic.lastMessageAt {
                        Text(lastMessageAt.smartFormatted())
                            .font(AppFonts.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    if let preview = topic.lastMessagePreview {
                        Text(preview)
                            .font(AppFonts.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("Keine Nachrichten")
                            .font(AppFonts.subheadline)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    if topic.unreadCount > 0 {
                        Text("\(topic.unreadCount)")
                            .font(AppFonts.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppColors.primary)
                            .clipShape(Capsule())
                            .accessibilityLabel("\(topic.unreadCount) ungelesen")
                    }
                }
            }
        }
        .padding(.vertical, AppSpacing.xxs)
    }

    @ViewBuilder
    private var topicIcon: some View {
        if topic.shouldUseMessageIcon, let iconURL = topic.lastMessageIconURL {
            CachedAsyncImage(url: iconURL, placeholder: "app.badge")
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            TopicAvatar(
                topicName: topic.name,
                iconName: topic.iconName,
                customLetter: topic.customLetter,
                colorHex: topic.colorHex
            )
        }
    }
}

/// Kachel mit Symbol oder Buchstabe eines Topics, wie in der Topic-Liste.
struct TopicAvatar: View {
    let topicName: String
    let iconName: String?
    let customLetter: String?
    let colorHex: String?
    var size: CGFloat = 44

    static func fallbackColor(for topicName: String) -> Color {
        let hash = topicName.utf8.reduce(0) { $0 &+ Int($1) }
        let colors: [Color] = [
            .red, .orange, .yellow, .green, .mint, .teal,
            .cyan, .blue, .indigo, .purple, .pink, .brown
        ]
        return colors[Int(hash.magnitude % UInt(colors.count))]
    }

    static func color(topicName: String, colorHex: String?) -> Color {
        if let hex = TopicSymbols.colorHex(topicName: topicName, colorHex: colorHex) {
            return Color(hex: hex)
        }
        return fallbackColor(for: topicName)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.23)
                .fill(Self.color(topicName: topicName, colorHex: colorHex).gradient)
                .frame(width: size, height: size)

            switch TopicSymbols.glyph(topicName: topicName, iconName: iconName, customLetter: customLetter) {
            case .symbol(let symbol):
                Image(systemName: symbol)
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(.white)
            case .letter(let letter):
                Text(letter)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Topic.self, StoredMessage.self, configurations: config)

    let topic = Topic(
        name: "test-topic",
        serverURL: "https://push.godsapp.de",
        iconName: "bell.fill",
        colorHex: "#4574AD"
    )
    container.mainContext.insert(topic)

    return List {
        TopicRow(topic: topic)
    }
    .modelContainer(container)
}
