import SwiftUI
import SwiftData

struct MessagesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(NtfyService.self) private var ntfyService

    let topic: Topic

    @Query private var messages: [StoredMessage]
    @Query private var deletedMessages: [DeletedMessage]

    @State private var isLoading = false
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
            if messages.isEmpty && !isLoading {
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
            await loadMessages()
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
            await loadMessages()
            startSubscription()
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
                        .tint(.blue)
                    }
            }

            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
    }

    private func loadMessages() async {
        isLoading = true

        let token = KeychainManager.shared.loadToken(serverURL: topic.serverURL)
        let credentials = KeychainManager.shared.loadCredentials(serverURL: topic.serverURL)

        do {
            let fetchedMessages = try await ntfyService.fetchMessages(
                serverURL: topic.serverURL,
                topic: topic.name,
                since: "7d",
                username: credentials?.username,
                password: credentials?.password,
                token: token
            )

            // Fetch deleted message IDs fresh from database
            let topicName = topic.name
            let serverURL = topic.serverURL
            let deletedPredicate = #Predicate<DeletedMessage> { deleted in
                deleted.topicName == topicName && deleted.serverURL == serverURL
            }
            let deletedDescriptor = FetchDescriptor(predicate: deletedPredicate)
            let deletedRecords = (try? modelContext.fetch(deletedDescriptor)) ?? []
            let deletedIds = Set(deletedRecords.map { $0.messageId })

            for ntfyMessage in fetchedMessages {
                // Skip if message was deleted by user
                if deletedIds.contains(ntfyMessage.id) {
                    continue
                }

                // Check if message already exists
                let messageId = ntfyMessage.id
                let existingPredicate = #Predicate<StoredMessage> { $0.messageId == messageId }
                let descriptor = FetchDescriptor(predicate: existingPredicate)
                let existing = try? modelContext.fetch(descriptor)

                if existing?.isEmpty ?? true {
                    let storedMessage = StoredMessage(from: ntfyMessage, topic: topic)
                    modelContext.insert(storedMessage)
                }
            }

            if let latestMessage = fetchedMessages.first {
                topic.lastMessageAt = Date(timeIntervalSince1970: TimeInterval(latestMessage.time))
            }

            try? modelContext.save()
        } catch let ntfyError as NtfyError {
            // Ignore cancelled errors (happens when view disappears)
            if case .networkError(let underlying) = ntfyError,
               (underlying as NSError).code == NSURLErrorCancelled {
                // Silently ignore
            } else {
                error = ntfyError
                showingError = true
            }
        } catch {
            // Ignore cancelled errors
            if (error as NSError).code == NSURLErrorCancelled {
                // Silently ignore
            } else {
                self.error = .networkError(error)
                showingError = true
            }
        }

        isLoading = false
    }

    private func startSubscription() {
        let token = KeychainManager.shared.loadToken(serverURL: topic.serverURL)
        let credentials = KeychainManager.shared.loadCredentials(serverURL: topic.serverURL)

        ntfyService.subscribe(
            serverURL: topic.serverURL,
            topic: topic.name,
            username: credentials?.username,
            password: credentials?.password,
            token: token
        ) { [self] message in
            Task { @MainActor in
                // Check if message already exists
                let existingPredicate = #Predicate<StoredMessage> { $0.messageId == message.id }
                let descriptor = FetchDescriptor(predicate: existingPredicate)
                let existing = try? modelContext.fetch(descriptor)

                if existing?.isEmpty ?? true {
                    let storedMessage = StoredMessage(from: message, topic: topic)
                    modelContext.insert(storedMessage)
                    topic.lastMessageAt = Date()

                    // Show notification if app is in background
                    if !topic.isMuted {
                        await NotificationService.shared.scheduleLocalNotification(
                            for: message,
                            topic: topic.name
                        )
                    }
                }
            }
        }
    }

    private func markAsRead(_ message: StoredMessage) {
        if !message.isRead {
            message.isRead = true
        }
    }

    private func toggleRead(_ message: StoredMessage) {
        message.isRead.toggle()
    }

    private func markAllAsRead() {
        for message in messages where !message.isRead {
            message.isRead = true
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

        withAnimation {
            modelContext.delete(message)
        }
        try? modelContext.save()
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
        }

        // Delete all messages locally
        withAnimation {
            for message in messages {
                modelContext.delete(message)
            }
        }
        try? modelContext.save()
    }

    private func unsubscribeTopic() {
        // Unsubscribe from SSE
        ntfyService.unsubscribe(serverURL: topic.serverURL, topic: topic.name)

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

        // Dismiss the view
        dismiss()
    }
}

#Preview {
    NavigationStack {
        Text("MessagesView Preview")
    }
    .modelContainer(for: [Topic.self, StoredMessage.self], inMemory: true)
    .environment(NtfyService.shared)
}
