import SwiftUI
import SwiftData

struct TopicRow: View {
    let topic: Topic

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            // Topic Icon
            topicIcon

            // Content
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                HStack {
                    Text(topic.name)
                        .font(AppFonts.headline)
                        .lineLimit(1)

                    if topic.isMuted {
                        Image(systemName: AppIcons.mute)
                            .font(.caption)
                            .foregroundStyle(.secondary)
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

                    // Unread badge
                    if topic.unreadCount > 0 {
                        Text("\(topic.unreadCount)")
                            .font(AppFonts.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppColors.primary)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.vertical, AppSpacing.xxs)
    }

    // Generate a color from topic name for consistent colors
    private var generatedColor: Color {
        if let hex = topic.colorHex {
            return Color(hex: hex)
        }
        // Generate consistent color from topic name
        let hash = topic.name.utf8.reduce(0) { $0 &+ Int($1) }
        let colors: [Color] = [
            .red, .orange, .yellow, .green, .mint, .teal,
            .cyan, .blue, .indigo, .purple, .pink, .brown
        ]
        let index = Int(hash.magnitude % UInt(colors.count))
        return colors[index]
    }

    @ViewBuilder
    private var topicIcon: some View {
        // Priority 1: Show icon from latest message (e.g. Sonarr logo) if enabled
        if topic.shouldUseMessageIcon, let iconURL = topic.lastMessageIconURL {
            CachedAsyncImage(url: iconURL, placeholder: "app.badge")
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        // Priority 2: Custom icon set by user
        else if let iconName = topic.iconName {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(generatedColor.gradient)
                    .frame(width: 44, height: 44)

                Image(systemName: iconName)
                    .font(.title3)
                    .foregroundStyle(.white)
            }
        }
        // Priority 3: Letter avatar with gradient
        else {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(generatedColor.gradient)
                    .frame(width: 44, height: 44)

                Text(topic.displayLetter)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
            }
        }
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
