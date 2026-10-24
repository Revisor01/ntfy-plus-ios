import SwiftUI
import SwiftData
import UIKit
import LocalAuthentication

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(NtfyService.self) private var ntfyService
    @Query(sort: \Topic.lastMessageAt, order: .reverse) private var topics: [Topic]
    @Query private var servers: [Server]

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedTopic: Topic?
    @State private var showingAddTopic = false
    @State private var showingSettings = false
    @State private var showingPublish = false
    @State private var navigationPath = NavigationPath()
    /// Topic-ID → Server/Name der aktiven SSE-Subscription (Name wird zum Abmelden
    /// gebraucht, nachdem das Topic-Model bereits geloescht ist)
    @State private var subscribedTopicIds: [String: SubscribedTopic] = [:]
    /// Deep-Link-Ziel, das erst nach erfolgreicher Entsperrung angesteuert wird
    @State private var pendingDeepLinkTopic: String?
    @State private var hasInitialized = false
    @State private var isLocked = AppSettings.biometricLockEnabled
    @State private var lastBackgroundDate: Date?
    @State private var hasEnteredBackground = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        rootContent
            .overlay { lockOverlay }
            .animation(.easeInOut(duration: 0.2), value: isLocked)
            .onOpenURL { url in
                handleDeepLink(url)
            }
            .onAppear {
                columnVisibility = horizontalSizeClass == .regular ? .all : .detailOnly
                requestNotificationPermission()
                if !hasInitialized {
                    hasInitialized = true
                    Task {
                        AppLog.ui.info("📱 Initial load - fetching messages")
                        await refreshAllTopics()
                        syncSubscriptions()
                    }
                }
            }
            .onChange(of: currentTopicIds) {
                // Geloeschtes Topic nicht weiter im Detail-Bereich halten (iPad: dismiss() wirkt dort nicht)
                validateSelectedTopic()
                syncSubscriptions()
            }
            .onChange(of: scenePhase) { _, newPhase in
                // Beim Wechsel in den Hintergrund sofort sperren — Snapshot/Rueckkehr zeigt keine Inhalte
                if newPhase == .background {
                    hasEnteredBackground = true
                    if AppSettings.biometricLockEnabled {
                        isLocked = true
                    }
                }
            }
            .onChange(of: horizontalSizeClass) { _, newValue in
                columnVisibility = newValue == .regular ? .all : .detailOnly
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                hasEnteredBackground = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                guard hasInitialized else { return }
                if AppSettings.biometricLockEnabled && hasEnteredBackground {
                    isLocked = true
                }
                hasEnteredBackground = false
                AppLog.ui.info("📱 willEnterForeground - refreshing messages")
                Task {
                    await NotificationService.shared.clearBadge()
                    await refreshAllTopics()
                }
            }
    }

    @ViewBuilder
    private var rootContent: some View {
        if !hasCompletedOnboarding || servers.isEmpty {
            OnboardingView(isOnboardingComplete: $hasCompletedOnboarding)
        } else {
            mainContent
        }
    }

    @ViewBuilder
    private var lockOverlay: some View {
        if isLocked && scenePhase != .background {
            // Nicht im Hintergrund einblenden — LockScreenView startet onAppear die Authentifizierung
            LockScreenView {
                unlock()
            }
            .transition(.opacity)
        } else if (isLocked || AppSettings.biometricLockEnabled) && scenePhase != .active {
            // Datenschutz-Overlay fuer App-Switcher-Snapshot und inaktive Phasen
            privacyOverlay
        }
    }

    private var privacyOverlay: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            Image(systemName: "lock.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
        }
    }

    private func unlock() {
        isLocked = false
        if let pendingTopic = pendingDeepLinkTopic {
            pendingDeepLinkTopic = nil
            navigate(toTopicNamed: pendingTopic)
        }
    }

    private var mainContent: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            TopicsView(
                selectedTopic: $selectedTopic,
                showingAddTopic: $showingAddTopic,
                showingSettings: $showingSettings,
                showingPublish: $showingPublish
            )
            .navigationSplitViewColumnWidth(min: 260, ideal: 300)
        } detail: {
            if let topic = selectedTopic, !topic.isDeleted, topic.modelContext != nil {
                MessagesView(topic: topic)
                    .id(topic.id)
            } else {
                EmptyStateView()
            }
        }
        .navigationSplitViewStyle(.balanced)
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
                requestNavigation(toTopicNamed: topicName)
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

    // MARK: - Deep Link

    private func handleDeepLink(_ url: URL) {
        // Format: ntfy://topic/{topicName}
        guard url.scheme == "ntfy",
              url.host == "topic",
              !url.pathComponents.isEmpty else { return }

        // pathComponents[0] ist "/", pathComponents[1] ist der Topic-Name
        let components = url.pathComponents.filter { $0 != "/" }
        guard let topicName = components.first else { return }

        // Onboarding abgeschlossen und Topic vorhanden?
        guard hasCompletedOnboarding, !servers.isEmpty else { return }

        AppLog.ui.info("🔗 Deep Link: Topic '\(topicName, privacy: .private)'")
        requestNavigation(toTopicNamed: topicName)
    }

    /// Navigiert zum Topic — bei aktiver Sperre erst nach erfolgreicher Entsperrung.
    /// Ein Deep Link darf die biometrische Sperre NIE aufheben.
    private func requestNavigation(toTopicNamed topicName: String) {
        if isLocked {
            pendingDeepLinkTopic = topicName
            AppLog.ui.info("🔗 Navigation vorgemerkt bis zur Entsperrung")
            return
        }
        navigate(toTopicNamed: topicName)
    }

    private func navigate(toTopicNamed topicName: String) {
        // Exakter Namensvergleich, geloeschte Models ueberspringen
        guard let topic = topics.first(where: { !$0.isDeleted && $0.name == topicName }) else {
            AppLog.ui.info("🔗 Topic '\(topicName, privacy: .private)' nicht gefunden")
            return
        }
        selectedTopic = topic
        AppLog.ui.info("🔗 Navigiere zu Topic '\(topicName, privacy: .private)'")
    }

    // MARK: - Selection

    /// IDs der aktuell existierenden Topics — Ausloeser fuer Subscription-Abgleich.
    private var currentTopicIds: Set<String> {
        Set(topics.filter { !$0.isDeleted && $0.modelContext != nil }.map(\.id))
    }

    /// Setzt `selectedTopic` zurueck, wenn das Topic geloescht wurde, bevor die
    /// Detailspalte ein ungueltiges Model rendert.
    private func validateSelectedTopic() {
        guard let selected = selectedTopic else { return }
        // isDeleted/modelContext zuerst pruefen — weitere Property-Zugriffe auf geloeschte Models crashen
        if selected.isDeleted || selected.modelContext == nil {
            selectedTopic = nil
            return
        }
        let selectedID = selected.persistentModelID
        if !topics.contains(where: { $0.persistentModelID == selectedID }) {
            selectedTopic = nil
        }
    }

    // MARK: - Refresh & Subscriptions

    /// Fetch missed messages for all topics (called when app becomes active)
    @MainActor
    private func refreshAllTopics() async {
        await ntfyService.refreshTopics(topics, context: modelContext, since: "168h")
    }

    /// Gleicht die SSE-Subscriptions mit den vorhandenen Topics ab:
    /// neue Topics abonnieren, entfernte Topics abmelden.
    private func syncSubscriptions() {
        let currentTopics = topics.filter { !$0.isDeleted && $0.modelContext != nil }
        let currentIds = Set(currentTopics.map(\.id))
        let currentKeys = Set(currentTopics.map { SubscribedTopic(serverURL: $0.serverURL, name: $0.name) })

        // 1. Entfernte Topics abmelden (zuerst, damit ein gleichnamig neu angelegtes Topic danach sauber abonniert wird)
        for (topicId, subscribed) in subscribedTopicIds where !currentIds.contains(topicId) {
            subscribedTopicIds.removeValue(forKey: topicId)
            // Nur abmelden, wenn kein anderes Topic denselben Server/Namen nutzt
            if !currentKeys.contains(subscribed) {
                ntfyService.unsubscribe(serverURL: subscribed.serverURL, topic: subscribed.name)
                AppLog.ui.info("🔌 Subscription fuer entferntes Topic '\(subscribed.name, privacy: .private)' beendet")
            }
        }

        // 2. Neue Topics abonnieren
        for topic in currentTopics where subscribedTopicIds[topic.id] == nil {
            subscribe(to: topic)
        }
    }

    private func subscribe(to topic: Topic) {
        let context = modelContext

        subscribedTopicIds[topic.id] = SubscribedTopic(serverURL: topic.serverURL, name: topic.name)

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
                // Topic kann inzwischen geloescht sein — dann nichts mehr schreiben
                guard !topicRef.isDeleted, topicRef.modelContext != nil else { return }
                ntfyService.storeMessages(for: topicRef, messages: [message], context: context)
                ntfyService.writeWidgetData(context: context)
            },
            onDelete: { @MainActor event in
                // message_delete: Ziel ueber sequence_id — Nachricht aus DB und Mitteilungszentrale entfernen
                guard !topicRef.isDeleted, topicRef.modelContext != nil else { return }
                ntfyService.storeMessages(for: topicRef, messages: [event], context: context)
                ntfyService.writeWidgetData(context: context)
            },
            onClear: { @MainActor event in
                // message_clear: Ziel ueber sequence_id — nur als gelesen markieren + Mitteilung entfernen
                guard !topicRef.isDeleted, topicRef.modelContext != nil else { return }
                ntfyService.storeMessages(for: topicRef, messages: [event], context: context)
                ntfyService.writeWidgetData(context: context)
            }
        )
    }
}

/// Server/Name einer aktiven Subscription (Schluessel fuer NtfyService.unsubscribe)
private struct SubscribedTopic: Hashable {
    let serverURL: String
    let name: String
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
