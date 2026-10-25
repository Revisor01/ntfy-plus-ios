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
    @State private var searchText = ""
    @State private var showOnlyStarred = false
    /// Entprellt das Badge-Update, wenn beim Scrollen viele Nachrichten als gelesen markiert werden
    @State private var badgeUpdateTask: Task<Void, Never>?
    /// Waehrend der App-Sperre eingeblendete Zeilen — werden erst nach dem Entsperren als gelesen markiert
    @State private var deferredReadIds: Set<PersistentIdentifier> = []

    @Environment(\.dismiss) private var dismiss
    @Environment(\.isAppLocked) private var isAppLocked

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

    /// Titel direkt aus dem Topic — nach dem Loeschen des Topics nicht mehr auf
    /// dessen Attribute zugreifen (SwiftData-Backing-Data ist dann ungueltig).
    private var displayName: String {
        if topic.isDeleted || topic.modelContext == nil {
            return ""
        }
        return topic.name
    }

    private var filteredMessages: [StoredMessage] {
        // Set einmal pro Auswertung bauen (nicht pro Nachricht im Filter-Closure)
        let deletedMessageIds = Set(deletedMessages.map { $0.messageId })
        var result = messages.filter { !deletedMessageIds.contains($0.messageId) }

        // Star-Filter (Toolbar-Toggle)
        if showOnlyStarred {
            result = result.filter { $0.isStarred }
        }

        // Suche (kombiniert mit Star-Filter)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return result }
        return result.filter { message in
            (message.title?.localizedCaseInsensitiveContains(query) == true) ||
            (message.message?.localizedCaseInsensitiveContains(query) == true) ||
            (message.tags?.contains { $0.localizedCaseInsensitiveContains(query) } == true)
        }
    }

    var body: some View {
        // Gefilterte Liste nur einmal pro Body-Auswertung berechnen
        let visibleMessages = filteredMessages

        Group {
            if visibleMessages.isEmpty {
                ContentUnavailableView {
                    Label("Keine Nachrichten", systemImage: AppIcons.empty)
                } description: {
                    Text("Nachrichten für \(displayName) werden hier angezeigt.")
                }
            } else {
                messageList(visibleMessages)
            }
        }
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Nachrichten durchsuchen")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    hapticFeedback(.light)
                    showOnlyStarred.toggle()
                } label: {
                    Image(systemName: showOnlyStarred ? "star.fill" : "star")
                        .foregroundStyle(showOnlyStarred ? .yellow : .secondary)
                }
                .accessibilityLabel(showOnlyStarred ? "Alle Nachrichten" : "Nur Favoriten")
            }

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
                .accessibilityLabel("Weitere Aktionen")
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
            Text("Das Topic \"\(displayName)\" wird entfernt. Alle lokalen Nachrichten werden gelöscht.")
        }
        .task {
            await ntfyService.refreshTopics([topic], context: modelContext, since: "168h")
        }
        .onChange(of: isAppLocked) { _, locked in
            guard !locked, !deferredReadIds.isEmpty else { return }
            let pendingIds = deferredReadIds
            deferredReadIds.removeAll()
            for message in messages where pendingIds.contains(message.persistentModelID) {
                markAsRead(message)
            }
        }
    }

    private func messageList(_ visibleMessages: [StoredMessage]) -> some View {
        List {
            ForEach(visibleMessages) { message in
                MessageRow(message: message)
                    .onAppear {
                        // Hinter der App-Sperre nichts als gelesen markieren
                        if isAppLocked {
                            deferredReadIds.insert(message.persistentModelID)
                        } else {
                            markAsRead(message)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            hapticFeedback(.medium)
                            deleteMessage(message)
                        } label: {
                            Label("Löschen", systemImage: AppIcons.delete)
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            hapticFeedback(.medium)
                            toggleRead(message)
                        } label: {
                            Label(
                                message.isRead ? "Ungelesen" : "Gelesen",
                                systemImage: message.isRead ? AppIcons.unread : AppIcons.read
                            )
                        }
                        .tint(AppColors.primary)

                        Button {
                            toggleStar(message)
                        } label: {
                            Label(
                                message.isStarred ? "Entfernen" : "Favorit",
                                systemImage: message.isStarred ? "star.slash" : "star"
                            )
                        }
                        .tint(.yellow)
                    }
            }

        }
        .listStyle(.plain)
        // Markdown-Links & Co. in allen Zeilen: nur http/https oeffnen
        .environment(\.openURL, OpenURLAction { url in
            url.isSafeWebURL ? .systemAction : .discarded
        })
    }

    private func markAsRead(_ message: StoredMessage) {
        if !message.isRead {
            message.isRead = true
            // Denormalisierten Zaehler dekrementieren
            if let topicRef = message.topic {
                topicRef.unreadCount = max(0, topicRef.unreadCount - 1)
            }
            // Remove notification and update badge (entprellt — beim Scrollen
            // erscheinen viele Zeilen kurz hintereinander)
            NotificationService.shared.removeNotification(withIdentifier: message.messageId)
            scheduleBadgeUpdate()
        }
    }

    private func toggleRead(_ message: StoredMessage) {
        let wasUnread = !message.isRead
        message.isRead.toggle()
        // Denormalisierten Zaehler anpassen
        if let topicRef = message.topic {
            if message.isRead && wasUnread {
                topicRef.unreadCount = max(0, topicRef.unreadCount - 1)
            } else if !message.isRead && !wasUnread {
                topicRef.unreadCount += 1
            }
        }
        if message.isRead {
            NotificationService.shared.removeNotification(withIdentifier: message.messageId)
        }
        scheduleBadgeUpdate()
    }

    private func toggleStar(_ message: StoredMessage) {
        message.isStarred.toggle()
        if AppSettings.hapticFeedback {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }
    }

    private func markAllAsRead() {
        // Markiert nur die aktuell sichtbaren (gefilterten) Nachrichten —
        // daher Zaehler und Badge danach aus der DB neu berechnen statt pauschal zu leeren.
        for message in filteredMessages where !message.isRead {
            message.isRead = true
            NotificationService.shared.removeNotification(withIdentifier: message.messageId)
        }
        TopicActions.recalculateUnreadCount(for: topic, context: modelContext)
        try? modelContext.save()
        ntfyService.writeWidgetData(context: modelContext)
        badgeUpdateTask?.cancel()
        Task {
            await TopicActions.updateBadge(context: modelContext)
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

        // Wenn Message ungelesen war, Zaehler dekrementieren
        if !message.isRead {
            topic.unreadCount = max(0, topic.unreadCount - 1)
        }

        withAnimation {
            modelContext.delete(message)
        }
        try? modelContext.save()

        scheduleBadgeUpdate()
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

        // Alle Messages geloescht — unreadCount auf 0
        topic.unreadCount = 0

        // Delete all messages locally
        withAnimation {
            for message in messages {
                modelContext.delete(message)
            }
        }
        try? modelContext.save()

        scheduleBadgeUpdate()
    }

    private func unsubscribeTopic() {
        badgeUpdateTask?.cancel()

        // View zuerst schliessen, damit der Body nicht mehr gegen ein
        // geloeschtes `topic` ausgewertet wird.
        dismiss()

        // Gemeinsamer Aufraeum-Pfad (SSE/FCM abmelden, Benachrichtigungen,
        // Nachrichten, DeletedMessage-Records, Topic loeschen, Badge, Widget).
        // TopicActions.remove kopiert alle benoetigten Werte vor dem Loeschen.
        TopicActions.remove(topic, context: modelContext, ntfyService: ntfyService)
    }

    /// Badge- und Widget-Update entprellen: viele markAsRead-Aufrufe beim Scrollen
    /// resultieren in einem einzigen fetchCount bzw. Widget-Reload.
    private func scheduleBadgeUpdate() {
        badgeUpdateTask?.cancel()
        let context = modelContext
        badgeUpdateTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            NtfyService.shared.writeWidgetData(context: context)
            await TopicActions.updateBadge(context: context)
        }
    }
}

#Preview {
    NavigationStack {
        Text("MessagesView Preview")
    }
    .modelContainer(for: [Topic.self, StoredMessage.self], inMemory: true)
    .environment(NtfyService.shared)
}
