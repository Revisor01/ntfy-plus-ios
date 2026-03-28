import SwiftUI
import SwiftData

struct MessagesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(NtfyService.self) private var ntfyService

    let topic: Topic

    @Query private var messages: [StoredMessage]
    @Query private var deletedMessages: [DeletedMessage]

    @State private var error: NtfyError?
    @State private var showingError = false
    @State private var showingPublish = false
    @State private var showingClearConfirm = false
    @State private var showingUnsubscribeConfirm = false

    @Environment(\.dismiss) private var dismiss

    init(topic: Topic) {
        self.topic = topic
        let topicId = topic.id
        let topicName = topic.name
        let serverURL = topic.serverURL
        _messages = Query(
            filter: #Predicate<StoredMessage> { message in
                message.topic?.id == topicId
            },
            sort: \StoredMessage.time,
            order: .reverse
        )
        _deletedMessages = Query(
            filter: #Predicate<DeletedMessage> { deleted in
                deleted.topicName == topicName && deleted.serverURL == serverURL
            }
        )
    }

    private var deletedMessageIds: Set<String> {
        Set(deletedMessages.map { $0.messageId })
    }

    var body: some View {
        Group {
            if messages.isEmpty {
                ContentUnavailableView {
                    Label("Keine Nachrichten", systemImage: AppIcons.empty)
                } description: {
                    Text("Nachrichten für \(topic.name) werden hier angezeigt.")
                }
            } else {
                messageList
            }
        }
        .navigationTitle(topic.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingPublish = true
                    } label: {
                        Label("Nachricht senden", systemImage: AppIcons.send)
                    }

                    Button {
                        markAllAsRead()
                    } label: {
                        Label("Alle als gelesen", systemImage: AppIcons.checkmark)
                    }

                    Divider()

                    Button(role: .destructive) {
                        showingClearConfirm = true
                    } label: {
                        Label("Alle Nachrichten löschen", systemImage: "trash")
                    }

                    Button(role: .destructive) {
                        showingUnsubscribeConfirm = true
                    } label: {
                        Label("Topic entfernen", systemImage: "minus.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .refreshable {
            await ntfyService.refreshTopics([topic], context: modelContext, since: "24h")
        }
        .sheet(isPresented: $showingPublish) {
            PublishView(selectedTopic: topic)
        }
        .alert("Fehler", isPresented: $showingError, presenting: error) { _ in
            Button("OK") {}
        } message: { error in
            Text(error.localizedDescription)
        }
        .alert("Alle Nachrichten löschen?", isPresented: $showingClearConfirm) {
            Button("Abbrechen", role: .cancel) {}
            Button("Löschen", role: .destructive) {
                clearAllMessages()
            }
        } message: {
            Text("Alle Nachrichten in diesem Topic werden gelöscht und nicht wieder geladen.")
        }
        .alert("Topic entfernen?", isPresented: $showingUnsubscribeConfirm) {
            Button("Abbrechen", role: .cancel) {}
            Button("Entfernen", role: .destructive) {
                unsubscribeTopic()
            }
        } message: {
            Text("Das Topic \"\(topic.name)\" wird entfernt. Alle lokalen Nachrichten werden gelöscht.")
        }
        .task {
            await ntfyService.refreshTopics([topic], context: modelContext, since: "168h")
        }
    }

    private var messageList: some View {
        List {
            ForEach(messages) { message in
                MessageRow(message: message)
                    .onAppear {
                        markAsRead(message)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            deleteMessage(message)
                        } label: {
                            Label("Löschen", systemImage: AppIcons.delete)
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            toggleRead(message)
                        } label: {
                            Label(
                                message.isRead ? "Ungelesen" : "Gelesen",
                                systemImage: message.isRead ? AppIcons.unread : AppIcons.read
                            )
                        }
                        .tint(AppColors.primary)
                    }
            }

        }
        .listStyle(.plain)
    }

    private func markAsRead(_ message: StoredMessage) {
        if !message.isRead {
            message.isRead = true
            // Remove notification and update badge
            NotificationService.shared.removeNotification(withIdentifier: message.messageId)
            Task {
                await updateBadgeCount()
            }
        }
    }

    private func toggleRead(_ message: StoredMessage) {
        message.isRead.toggle()
        if message.isRead {
            NotificationService.shared.removeNotification(withIdentifier: message.messageId)
        }
        Task {
            await updateBadgeCount()
        }
    }

    private func markAllAsRead() {
        for message in messages where !message.isRead {
            message.isRead = true
            NotificationService.shared.removeNotification(withIdentifier: message.messageId)
        }
        Task {
            await NotificationService.shared.clearBadge()
        }
    }

    private func deleteMessage(_ message: StoredMessage) {
        // Save deleted message ID so it won't be reloaded from server
        let deletedRecord = DeletedMessage(
            messageId: message.messageId,
            topicName: topic.name,
            serverURL: topic.serverURL
        )
        modelContext.insert(deletedRecord)

        // Remove notification
        NotificationService.shared.removeNotification(withIdentifier: message.messageId)

        // Try to delete on server if sequenceId is available (ntfy v2.16+)
        if let sequenceId = message.sequenceId {
            let token = KeychainManager.shared.loadToken(serverURL: topic.serverURL)
            let credentials = KeychainManager.shared.loadCredentials(serverURL: topic.serverURL)

            Task {
                try? await ntfyService.deleteMessage(
                    serverURL: topic.serverURL,
                    topic: topic.name,
                    sequenceId: sequenceId,
                    username: credentials?.username,
                    password: credentials?.password,
                    token: token
                )
            }
        }

        withAnimation {
            modelContext.delete(message)
        }
        try? modelContext.save()

        Task {
            await updateBadgeCount()
        }
    }

    private func clearAllMessages() {
        // Save all message IDs as deleted
        for message in messages {
            let deletedRecord = DeletedMessage(
                messageId: message.messageId,
                topicName: topic.name,
                serverURL: topic.serverURL
            )
            modelContext.insert(deletedRecord)
            NotificationService.shared.removeNotification(withIdentifier: message.messageId)
        }

        // Delete all messages locally
        withAnimation {
            for message in messages {
                modelContext.delete(message)
            }
        }
        try? modelContext.save()

        Task {
            await updateBadgeCount()
        }
    }

    private func unsubscribeTopic() {
        // Unsubscribe from SSE
        ntfyService.unsubscribe(serverURL: topic.serverURL, topic: topic.name)

        // Unsubscribe from Firebase topic
        FirebaseService.shared.unsubscribeFromTopic(serverURL: topic.serverURL, topic: topic.name)

        // Remove all notifications for this topic
        Task {
            await NotificationService.shared.removeNotifications(forTopic: topic.name)
        }

        // Delete all messages
        for message in messages {
            modelContext.delete(message)
        }

        // Delete all deleted message records for this topic
        for deleted in deletedMessages {
            modelContext.delete(deleted)
        }

        // Delete the topic itself
        modelContext.delete(topic)
        try? modelContext.save()

        Task {
            await updateBadgeCount()
        }

        // Dismiss the view
        dismiss()
    }

    private func updateBadgeCount() async {
        // Count unread messages across all topics
        let unreadPredicate = #Predicate<StoredMessage> { !$0.isRead }
        let descriptor = FetchDescriptor(predicate: unreadPredicate)
        let unreadCount = (try? modelContext.fetchCount(descriptor)) ?? 0
        await NotificationService.shared.setBadgeCount(unreadCount)
    }
}

#Preview {
    NavigationStack {
        Text("MessagesView Preview")
    }
    .modelContainer(for: [Topic.self, StoredMessage.self], inMemory: true)
    .environment(NtfyService.shared)
}
