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

                // Message body with Markdown support
                if let messageText = message.message, !messageText.isEmpty {
                    Text(parseMarkdown(messageText))
                        .font(AppFonts.body)
                        .foregroundStyle(.primary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .tint(AppColors.primary)
                }

                // Attachment
                if let attachment = message.attachment, let url = attachment.url {
                    attachmentView(attachment: attachment, url: url)
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

                // Action buttons from ntfy
                if let actions = message.actions, !actions.isEmpty {
                    actionButtonsView(actions: actions)
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

    // MARK: - Attachment View

    @ViewBuilder
    private func attachmentView(attachment: StoredAttachment, url: String) -> some View {
        if attachment.isImage {
            // Image attachment - show inline
            AsyncImage(url: URL(string: url)) { phase in
                switch phase {
                case .empty:
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.secondary.opacity(0.1))
                        .frame(height: 150)
                        .overlay {
                            ProgressView()
                        }
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 250)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        }
                        .onTapGesture {
                            openURL(url)
                        }
                case .failure:
                    attachmentFileRow(attachment: attachment, url: url, icon: "photo", color: AppColors.primary)
                @unknown default:
                    EmptyView()
                }
            }
        } else {
            // Non-image attachment - show as downloadable file
            let icon = iconForFileType(attachment.type)
            attachmentFileRow(attachment: attachment, url: url, icon: icon.0, color: icon.1)
        }
    }

    @ViewBuilder
    private func attachmentFileRow(attachment: StoredAttachment, url: String, icon: String, color: Color) -> some View {
        Button {
            openURL(url)
        } label: {
            HStack(spacing: AppSpacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(color.opacity(0.15))
                        .frame(width: 40, height: 40)

                    Image(systemName: icon)
                        .foregroundStyle(color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.fileName)
                        .font(AppFonts.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let size = attachment.formattedSize {
                        Text(size)
                            .font(AppFonts.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "arrow.down.circle")
                    .font(.title2)
                    .foregroundStyle(AppColors.primary)
            }
            .padding(AppSpacing.sm)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func iconForFileType(_ type: String?) -> (String, Color) {
        guard let type = type else { return ("doc", .gray) }

        if type.hasPrefix("image/") { return ("photo", AppColors.primary) }
        if type.hasPrefix("video/") { return ("film", .purple) }
        if type.hasPrefix("audio/") { return ("waveform", .orange) }
        if type.hasPrefix("text/") { return ("doc.text", .gray) }
        if type.contains("pdf") { return ("doc.fill", .red) }
        if type.contains("zip") || type.contains("tar") || type.contains("gz") { return ("doc.zipper", .yellow) }
        if type.contains("json") || type.contains("xml") { return ("curlybraces", .green) }

        return ("doc", .gray)
    }

    // MARK: - Action Buttons View

    @ViewBuilder
    private func actionButtonsView(actions: [StoredAction]) -> some View {
        HStack(spacing: AppSpacing.sm) {
            ForEach(actions.prefix(3), id: \.label) { action in
                actionButton(action)
            }
        }
    }

    @ViewBuilder
    private func actionButton(_ action: StoredAction) -> some View {
        Button {
            executeAction(action)
        } label: {
            HStack(spacing: AppSpacing.xxs) {
                Image(systemName: iconForAction(action))
                Text(action.label)
                    .lineLimit(1)
            }
            .font(AppFonts.caption)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xs)
            .background(AppColors.primary.opacity(0.1))
            .foregroundStyle(AppColors.primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func iconForAction(_ action: StoredAction) -> String {
        switch action.action {
        case "view": return "safari"
        case "http": return "network"
        case "broadcast": return "antenna.radiowaves.left.and.right"
        default: return "bolt"
        }
    }

    private func executeAction(_ action: StoredAction) {
        switch action.action {
        case "view":
            // Open URL in browser
            if let urlString = action.url {
                openURL(urlString)
            }

        case "http":
            // Execute HTTP request
            if let urlString = action.url, let url = URL(string: urlString) {
                Task {
                    await executeHTTPAction(action, url: url)
                }
            }

        default:
            // For broadcast and others, just open URL if available
            if let urlString = action.url {
                openURL(urlString)
            }
        }

        // Haptic feedback
        if AppSettings.hapticFeedback {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        }
    }

    private func executeHTTPAction(_ action: StoredAction, url: URL) async {
        var request = URLRequest(url: url)
        request.httpMethod = action.method ?? "POST"

        // Add headers
        if let headers = action.headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        // Add body
        if let body = action.body {
            request.httpBody = body.data(using: .utf8)
        }

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               (200...299).contains(httpResponse.statusCode) {
                await MainActor.run {
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                }
            }
        } catch {
            print("HTTP action failed: \(error)")
        }
    }

    // MARK: - Helpers

    private func parseMarkdown(_ text: String) -> AttributedString {
        do {
            return try AttributedString(markdown: text, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        } catch {
            return AttributedString(text)
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
