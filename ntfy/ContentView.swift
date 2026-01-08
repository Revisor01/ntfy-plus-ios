import SwiftUI
import SwiftData

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
        }
        .task {
            await subscribeToAllTopics()
        }
        .onChange(of: topics.count) {
            Task {
                await subscribeToAllTopics()
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
    }

    private func requestNotificationPermission() {
        Task {
            _ = await NotificationService.shared.requestAuthorization()
        }
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
                token: token
            ) { @MainActor message in
                // Check if message already exists
                let messageId = message.id
                let existingPredicate = #Predicate<StoredMessage> { $0.messageId == messageId }
                let descriptor = FetchDescriptor(predicate: existingPredicate)
                let existing = try? context.fetch(descriptor)

                if existing?.isEmpty ?? true {
                    // Check if message was deleted
                    let topicName = topicRef.name
                    let serverURL = topicRef.serverURL
                    let deletedPredicate = #Predicate<DeletedMessage> { deleted in
                        deleted.messageId == messageId && deleted.topicName == topicName && deleted.serverURL == serverURL
                    }
                    let deletedDescriptor = FetchDescriptor(predicate: deletedPredicate)
                    let deletedExists = (try? context.fetch(deletedDescriptor))?.isEmpty == false

                    if !deletedExists {
                        let storedMessage = StoredMessage(from: message, topic: topicRef)
                        context.insert(storedMessage)
                        topicRef.lastMessageAt = Date()
                        try? context.save()

                        // Show notification if not muted
                        if !topicRef.isMuted {
                            Task {
                                await NotificationService.shared.scheduleLocalNotification(
                                    for: message,
                                    topic: topicRef.name
                                )
                            }
                        }
                    }
                }
            }
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
