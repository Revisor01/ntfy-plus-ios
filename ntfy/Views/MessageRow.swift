import SwiftUI
import SwiftData

struct MessageRow: View {
    let message: StoredMessage

    @State private var showingActions = false

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            // App Icon (from notification) with priority badge
            messageIcon

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                // Header
                HStack {
                    // Title or topic
                    if let title = message.title {
                        Text(title)
                            .font(AppFonts.headline)
                            .lineLimit(1)
                    } else {
                        Text(message.topic?.name ?? "")
                            .font(AppFonts.headline)
                            .lineLimit(1)
                    }

                    Spacer()

                    // Time
                    Text(message.date.smartFormatted())
                        .font(AppFonts.caption)
                        .foregroundStyle(.secondary)

                    // Unread indicator
                    if !message.isRead {
                        Circle()
                            .fill(AppColors.primary)
                            .frame(width: 8, height: 8)
                    }
                }

                // Emoji tags
                if !message.emojiTags.isEmpty {
                    HStack(spacing: AppSpacing.xxs) {
                        ForEach(message.emojiTags, id: \.self) { emoji in
                            Text(emoji)
                                .font(.title3)
                        }
                    }
                }

                // Message body
                if let messageText = message.message, !messageText.isEmpty {
                    Text(messageText)
                        .font(AppFonts.body)
                        .foregroundStyle(.primary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Click URL
                if let clickURL = message.clickURL, clickURL.isValidURL {
                    Button {
                        openURL(clickURL)
                    } label: {
                        HStack(spacing: AppSpacing.xxs) {
                            Image(systemName: AppIcons.link)
                            Text(displayURL(clickURL))
                                .lineLimit(1)
                        }
                        .font(AppFonts.caption)
                        .foregroundStyle(AppColors.primary)
                    }
                    .buttonStyle(.plain)
                }

                // Actions row
                HStack(spacing: AppSpacing.md) {
                    // Copy button
                    Button {
                        copyMessage()
                    } label: {
                        Image(systemName: AppIcons.copy)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    // Share button
                    Button {
                        shareMessage()
                    } label: {
                        Image(systemName: AppIcons.share)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    Spacer()

                    // Full timestamp on tap
                    Text(message.date.formatted())
                        .font(AppFonts.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, AppSpacing.xxs)
            }
        }
        .padding(.vertical, AppSpacing.xs)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                copyMessage()
            } label: {
                Label("Kopieren", systemImage: AppIcons.copy)
            }

            Button {
                shareMessage()
            } label: {
                Label("Teilen", systemImage: AppIcons.share)
            }

            if let clickURL = message.clickURL, clickURL.isValidURL {
                Button {
                    openURL(clickURL)
                } label: {
                    Label("Link öffnen", systemImage: AppIcons.link)
                }
            }
        }
    }

    @ViewBuilder
    private var messageIcon: some View {
        let priority = message.priorityLevel

        ZStack(alignment: .topTrailing) {
            // Main icon
            if let iconURL = message.iconURL {
                CachedAsyncImage(url: iconURL, placeholder: "app.badge")
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                // Priority-based fallback icon
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AppColors.priority(priority).opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: priority == .default ? "bell.fill" : priority.icon)
                        .font(.title2)
                        .foregroundStyle(AppColors.priority(priority))
                }
            }

            // Priority badge for high/urgent priorities when icon is present
            if message.iconURL != nil && (priority == .high || priority == .urgent) {
                priorityBadge(for: priority)
            }
        }
        .frame(width: 52, height: 52) // Larger frame to accommodate badge
    }

    @ViewBuilder
    private func priorityBadge(for priority: Priority) -> some View {
        ZStack {
            Circle()
                .fill(priority == .urgent ? .red : .orange)
                .frame(width: 20, height: 20)
                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)

            Image(systemName: "exclamationmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private func displayURL(_ urlString: String) -> String {
        guard let url = URL(string: urlString),
              let host = url.host else {
            return urlString
        }
        return host
    }

    private func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
    }

    private func copyMessage() {
        var text = ""
        if let title = message.title {
            text += "\(title)\n"
        }
        if let messageText = message.message {
            text += messageText
        }
        UIPasteboard.general.string = text

        // Haptic feedback
        if AppSettings.hapticFeedback {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        }
    }

    private func shareMessage() {
        var text = ""
        if let title = message.title {
            text += "\(title)\n"
        }
        if let messageText = message.message {
            text += messageText
        }

        let activityVC = UIActivityViewController(
            activityItems: [text],
            applicationActivities: nil
        )

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(activityVC, animated: true)
        }
    }
}

#Preview {
    @Previewable @State var previewMessage: StoredMessage? = nil

    List {
        Text("Preview")
    }
    .modelContainer(for: [Topic.self, StoredMessage.self], inMemory: true)
}
