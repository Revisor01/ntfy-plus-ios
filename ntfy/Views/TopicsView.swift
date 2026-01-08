import SwiftUI
import SwiftData

struct TopicsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(NtfyService.self) private var ntfyService
    @Query(sort: \Topic.lastMessageAt, order: .reverse) private var topics: [Topic]

    @Binding var selectedTopic: Topic?
    @Binding var showingAddTopic: Bool
    @Binding var showingSettings: Bool
    @Binding var showingPublish: Bool

    @State private var searchText = ""
    @State private var isRefreshing = false
    @State private var topicToEdit: Topic?

    var filteredTopics: [Topic] {
        if searchText.isEmpty {
            return topics
        }
        return topics.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var totalUnreadCount: Int {
        topics.reduce(0) { $0 + $1.unreadCount }
    }

    var body: some View {
        List(selection: $selectedTopic) {
            if filteredTopics.isEmpty && !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else if filteredTopics.isEmpty {
                ContentUnavailableView {
                    Label("Keine Topics", systemImage: AppIcons.empty)
                } description: {
                    Text("Tippe auf + um ein neues Topic hinzuzufügen.")
                }
            } else {
                ForEach(filteredTopics) { topic in
                    TopicRow(topic: topic)
                        .tag(topic)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteTopic(topic)
                            } label: {
                                Label("Löschen", systemImage: AppIcons.delete)
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                topicToEdit = topic
                            } label: {
                                Label("Anpassen", systemImage: "paintbrush.fill")
                            }
                            .tint(.purple)

                            Button {
                                toggleMute(topic)
                            } label: {
                                Label(
                                    topic.isMuted ? "Laut" : "Stumm",
                                    systemImage: topic.isMuted ? AppIcons.unmute : AppIcons.mute
                                )
                            }
                            .tint(topic.isMuted ? .green : .orange)
                        }
                        .contextMenu {
                            Button {
                                topicToEdit = topic
                            } label: {
                                Label("Anpassen", systemImage: "paintbrush.fill")
                            }

                            Button {
                                toggleMute(topic)
                            } label: {
                                Label(
                                    topic.isMuted ? "Benachrichtigungen aktivieren" : "Stummschalten",
                                    systemImage: topic.isMuted ? AppIcons.unmute : AppIcons.mute
                                )
                            }

                            Divider()

                            Button(role: .destructive) {
                                deleteTopic(topic)
                            } label: {
                                Label("Löschen", systemImage: AppIcons.delete)
                            }
                        }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "Topics durchsuchen")
        .refreshable {
            await refreshAllTopics()
        }
        .navigationTitle("ntfy+")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingAddTopic = true
                    } label: {
                        Label("Topic abonnieren", systemImage: AppIcons.add)
                    }

                    Button {
                        showingPublish = true
                    } label: {
                        Label("Nachricht senden", systemImage: AppIcons.send)
                    }
                } label: {
                    Image(systemName: AppIcons.add)
                }
            }

            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: AppIcons.settings)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if totalUnreadCount > 0 {
                unreadBadge
            }
        }
        .sheet(item: $topicToEdit) { topic in
            EditTopicView(topic: topic)
        }
    }

    private var unreadBadge: some View {
        HStack {
            Image(systemName: AppIcons.notification)
            Text("\(totalUnreadCount) ungelesen")
        }
        .font(AppFonts.footnote)
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .padding(.bottom, AppSpacing.sm)
    }

    private func deleteTopic(_ topic: Topic) {
        ntfyService.unsubscribe(serverURL: topic.serverURL, topic: topic.name)

        withAnimation {
            if selectedTopic == topic {
                selectedTopic = nil
            }
            modelContext.delete(topic)
        }
    }

    private func toggleMute(_ topic: Topic) {
        withAnimation {
            topic.isMuted.toggle()
        }
    }

    private func refreshAllTopics() async {
        isRefreshing = true

        for topic in topics {
            let token = KeychainManager.shared.loadToken(serverURL: topic.serverURL)
            let credentials = KeychainManager.shared.loadCredentials(serverURL: topic.serverURL)

            do {
                let messages = try await ntfyService.fetchMessages(
                    serverURL: topic.serverURL,
                    topic: topic.name,
                    since: "24h",
                    username: credentials?.username,
                    password: credentials?.password,
                    token: token
                )

                // Fetch deleted message IDs for this topic
                let topicName = topic.name
                let serverURL = topic.serverURL
                let deletedPredicate = #Predicate<DeletedMessage> { deleted in
                    deleted.topicName == topicName && deleted.serverURL == serverURL
                }
                let deletedDescriptor = FetchDescriptor(predicate: deletedPredicate)
                let deletedRecords = (try? modelContext.fetch(deletedDescriptor)) ?? []
                let deletedIds = Set(deletedRecords.map { $0.messageId })

                // Store new messages (skip deleted ones)
                for message in messages {
                    // Skip if message was deleted by user
                    if deletedIds.contains(message.id) {
                        continue
                    }

                    let existingPredicate = #Predicate<StoredMessage> { $0.messageId == message.id }
                    let descriptor = FetchDescriptor(predicate: existingPredicate)
                    let existing = try? modelContext.fetch(descriptor)

                    if existing?.isEmpty ?? true {
                        let storedMessage = StoredMessage(from: message, topic: topic)
                        modelContext.insert(storedMessage)
                    }
                }

                if let latestMessage = messages.first {
                    topic.lastMessageAt = Date(timeIntervalSince1970: TimeInterval(latestMessage.time))
                }
            } catch {
                print("Failed to refresh topic \(topic.name): \(error)")
            }
        }

        try? modelContext.save()
        isRefreshing = false
    }
}

#Preview {
    NavigationStack {
        TopicsView(
            selectedTopic: .constant(nil),
            showingAddTopic: .constant(false),
            showingSettings: .constant(false),
            showingPublish: .constant(false)
        )
    }
    .modelContainer(for: [Topic.self, StoredMessage.self], inMemory: true)
    .environment(NtfyService.shared)
}
