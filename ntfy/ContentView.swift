import SwiftUI
import SwiftData
import UIKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(NtfyService.self) private var ntfyService
    @Query(sort: \Topic.lastMessageAt, order: .reverse) private var topics: [Topic]
    @Query private var servers: [Server]

    @State private var selectedTopic: Topic?
    @State private var showingAddTopic = false
    @State private var showingSettings = false
    @State private var showingPublish = false
    @State private var navigationPath = NavigationPath()
    @State private var subscribedTopicIds: Set<String> = []
    @State private var hasInitialized = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        Group {
            if !hasCompletedOnboarding || servers.isEmpty {
                OnboardingView(isOnboardingComplete: $hasCompletedOnboarding)
            } else {
                mainContent
            }
        }
        .onAppear {
            requestNotificationPermission()
            if !hasInitialized {
                hasInitialized = true
                Task {
                    print("📱 Initial load - fetching messages")
                    await refreshAllTopics()
                    await subscribeToAllTopics()
                }
            }
        }
        .onChange(of: topics.count) {
            Task {
                await subscribeToAllTopics()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            guard hasInitialized else { return }
            print("📱 didBecomeActiveNotification - refreshing messages")
            Task {
                await NotificationService.shared.clearBadge()
                await refreshAllTopics()
            }
        }
    }

    private var mainContent: some View {
        NavigationSplitView {
            TopicsView(
                selectedTopic: $selectedTopic,
                showingAddTopic: $showingAddTopic,
                showingSettings: $showingSettings,
                showingPublish: $showingPublish
            )
        } detail: {
            if let topic = selectedTopic {
                MessagesView(topic: topic)
            } else {
                EmptyStateView()
            }
        }
        .sheet(isPresented: $showingAddTopic) {
            AddTopicView()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showingPublish) {
            PublishView(selectedTopic: selectedTopic)
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToTopic)) { notification in
            if let topicName = notification.userInfo?["topic"] as? String {
                selectedTopic = topics.first { $0.name == topicName }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .markMessageRead)) { notification in
            if let messageId = notification.userInfo?["messageId"] as? String {
                let predicate = #Predicate<StoredMessage> { $0.messageId == messageId }
                let descriptor = FetchDescriptor(predicate: predicate)
                if let results = try? modelContext.fetch(descriptor),
                   let message = results.first,
                   !message.isRead {
                    message.isRead = true
                    if let topic = message.topic {
                        topic.unreadCount = max(0, topic.unreadCount - 1)
                    }
                    try? modelContext.save()
                }
            }
        }
    }

    private func requestNotificationPermission() {
        Task {
            _ = await NotificationService.shared.requestAuthorization()
        }
    }

    /// Fetch missed messages for all topics (called when app becomes active)
    @MainActor
    private func refreshAllTopics() async {
        await ntfyService.refreshTopics(topics, context: modelContext, since: "168h")
    }

    private func subscribeToAllTopics() async {
        let context = modelContext

        for topic in topics {
            // Skip if already subscribed
            guard !subscribedTopicIds.contains(topic.id) else { continue }

            subscribedTopicIds.insert(topic.id)

            // Subscribe to Firebase topic for push notifications
            FirebaseService.shared.subscribeToTopic(serverURL: topic.serverURL, topic: topic.name)

            let token = KeychainManager.shared.loadToken(serverURL: topic.serverURL)
            let credentials = KeychainManager.shared.loadCredentials(serverURL: topic.serverURL)

            let topicRef = topic

            ntfyService.subscribe(
                serverURL: topic.serverURL,
                topic: topic.name,
                username: credentials?.username,
                password: credentials?.password,
                token: token,
                onMessage: { @MainActor message in
                    ntfyService.storeMessages(for: topicRef, messages: [message], context: context)
                },
                onDelete: { @MainActor deletedMessageId in
                    // Find and delete the message locally when server sends delete event
                    let predicate = #Predicate<StoredMessage> { $0.messageId == deletedMessageId }
                    let descriptor = FetchDescriptor(predicate: predicate)
                    if let messages = try? context.fetch(descriptor) {
                        for message in messages {
                            NotificationService.shared.removeNotification(withIdentifier: message.messageId)
                            context.delete(message)
                        }
                        try? context.save()
                    }
                },
                onClear: { @MainActor in
                    // Clear all messages for this topic when server sends clear event
                    let topicId = topicRef.id
                    let predicate = #Predicate<StoredMessage> { $0.topic?.id == topicId }
                    let descriptor = FetchDescriptor(predicate: predicate)
                    if let messages = try? context.fetch(descriptor) {
                        for message in messages {
                            NotificationService.shared.removeNotification(withIdentifier: message.messageId)
                            context.delete(message)
                        }
                        try? context.save()
                    }
                }
            )
        }
    }
}

struct EmptyStateView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Kein Topic ausgewählt", systemImage: AppIcons.topics)
        } description: {
            Text("Wähle ein Topic aus der Liste oder erstelle ein neues.")
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Topic.self, StoredMessage.self, Server.self], inMemory: true)
}
