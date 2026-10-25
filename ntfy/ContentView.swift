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
    /// Sperrzustand ist app-weit (alle Fenster/Szenen teilen ihn, z.B. iPad-Multiwindow)
    @State private var lockState = AppLockState.shared
    /// Die UIWindowScene dieses ContentView — Ziel fuer das Sperrfenster
    @State private var sceneBox = WindowSceneBox()
    @State private var lastBackgroundDate: Date?
    @State private var hasEnteredBackground = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    private var isLocked: Bool {
        get { lockState.isLocked }
        nonmutating set { lockState.isLocked = newValue }
    }

    var body: some View {
        rootContent
            .background(
                // Ermittelt die eigene Szene, sobald die View im Fenster haengt
                WindowSceneReader { scene in
                    sceneBox.scene = scene
                    updateLockWindow()
                }
            )
            // Die Sperre selbst liegt in einem eigenen Fenster ueber allen Sheets/Alerts
            // (LockWindowPresenter). Darunter: Inhalte fuer VoiceOver ausblenden und
            // Views mitteilen, dass nichts als gelesen markiert werden darf.
            .accessibilityHidden(isLocked)
            .environment(\.isAppLocked, isLocked)
            .onOpenURL { url in
                handleDeepLink(url)
            }
            .onAppear {
                columnVisibility = horizontalSizeClass == .regular ? .all : .detailOnly
                updateLockWindow()
                MutedTopicsSync.write(topics: topics)
                if !hasInitialized {
                    hasInitialized = true
                    Task {
                        AppLog.ui.info("📱 Initial load - fetching messages")
                        await refreshAllTopics()
                        syncSubscriptions()
                    }
                }
            }
            .onChange(of: subscriptionSyncKeys) {
                // Geloeschtes Topic nicht weiter im Detail-Bereich halten (iPad: dismiss() wirkt dort nicht)
                validateSelectedTopic()
                // Reagiert auch auf geaenderte Server-URL (Server-Editor zieht Topics um)
                syncSubscriptions()
            }
            .onChange(of: muteSyncKeys) {
                // Stummschaltung fuer die NotificationServiceExtension spiegeln
                MutedTopicsSync.write(topics: topics)
            }
            .onChange(of: isLocked) {
                updateLockWindow()
                // Entsperrt (auch in einem anderen Fenster) — vorgemerktes Ziel ansteuern
                if !isLocked, let pendingTopic = pendingDeepLinkTopic {
                    pendingDeepLinkTopic = nil
                    navigate(toTopicNamed: pendingTopic)
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                // Beim Wechsel in den Hintergrund sofort sperren — Snapshot/Rueckkehr zeigt keine Inhalte
                // (iPad-Multiwindow: nicht, solange ein anderes Fenster der App sichtbar ist —
                // diese Szene selbst ist per Datenschutz-Abdeckung verdeckt)
                if newPhase == .background {
                    hasEnteredBackground = true
                    if AppSettings.biometricLockEnabled && !hasOtherForegroundScene {
                        isLocked = true
                    }
                }
                updateLockWindow()
            }
            .onChange(of: horizontalSizeClass) { _, newValue in
                columnVisibility = newValue == .regular ? .all : .detailOnly
            }
            .onReceive(NotificationCenter.default.publisher(for: .serverConfigurationChanged)) { notification in
                // Server-URL oder Zugangsdaten geaendert — SSE mit den aktuellen Keychain-Daten neu aufbauen
                if let serverURL = notification.userInfo?["serverURL"] as? String {
                    resubscribeTopics(ofServer: serverURL)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                hasEnteredBackground = true
                // Ganze App im Hintergrund — in jedem Fall sperren
                if AppSettings.biometricLockEnabled {
                    isLocked = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                guard hasInitialized else { return }
                if AppSettings.biometricLockEnabled && hasEnteredBackground {
                    isLocked = true
                }
                hasEnteredBackground = false
                AppLog.ui.info("📱 willEnterForeground - reconnecting SSE and refreshing messages")
                let context = modelContext
                Task {
                    // Im Hintergrund abgebrochene/haengende SSE-Streams sofort neu aufbauen
                    await ntfyService.reconnectAll()
                    await refreshAllTopics()
                    // Badge aus den ungelesenen Nachrichten setzen (nicht pauschal auf 0)
                    await NotificationService.shared.syncBadgeWithUnreadCount(context: context)
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

    /// Sperrbildschirm bzw. Datenschutz-Abdeckung im eigenen Fenster ueber allen
    /// Sheets und Alerts einblenden oder ausblenden.
    private func updateLockWindow() {
        let content: LockWindowContent
        if isLocked && scenePhase != .background {
            // Nicht im Hintergrund — LockScreenView authentifiziert erst bei aktiver Szene
            content = .lockScreen
        } else if (isLocked || AppSettings.biometricLockEnabled) && scenePhase != .active {
            // Datenschutz-Overlay fuer App-Switcher-Snapshot und inaktive Phasen
            content = .privacy
        } else {
            content = .hidden
        }
        LockWindowPresenter.shared.update(
            scene: sceneBox.scene,
            content: content,
            isSceneActive: scenePhase == .active,
            onUnlock: { unlock() }
        )
    }

    /// true, wenn eine andere Szene der App noch im Vordergrund ist (iPad-Multiwindow).
    private var hasOtherForegroundScene: Bool {
        let ownScene = sceneBox.scene
        return UIApplication.shared.connectedScenes.contains { scene in
            scene !== ownScene
                && (scene.activationState == .foregroundActive || scene.activationState == .foregroundInactive)
        }
    }

    private func unlock() {
        // Vorgemerktes Deep-Link-Ziel wird in onChange(of: isLocked) angesteuert
        isLocked = false
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
                    ntfyService.writeWidgetData(context: modelContext)
                }
            }
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

    /// "id|serverURL|name" der aktuell existierenden Topics — Ausloeser fuer den
    /// Subscription-Abgleich (auch wenn sich nur Server-URL oder Name aendert).
    private var subscriptionSyncKeys: Set<String> {
        Set(topics.filter { !$0.isDeleted && $0.modelContext != nil }.map { "\($0.id)|\($0.serverURL)|\($0.name)" })
    }

    /// "serverURL|name|isMuted" aller Topics — Ausloeser fuer den Abgleich der
    /// Stummschaltung mit der NotificationServiceExtension.
    private var muteSyncKeys: Set<String> {
        Set(topics.filter { !$0.isDeleted && $0.modelContext != nil }.map { "\($0.serverURL)|\($0.name)|\($0.isMuted)" })
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

        // 2. Neue Topics abonnieren, Topics mit geaenderter Server-URL/Name neu abonnieren
        for topic in currentTopics {
            guard let subscribed = subscribedTopicIds[topic.id] else {
                subscribe(to: topic)
                continue
            }
            if subscribed != SubscribedTopic(serverURL: topic.serverURL, name: topic.name) {
                resubscribe(topic, replacing: subscribed, currentKeys: currentKeys)
            }
        }
    }

    /// Baut die SSE-Subscriptions aller Topics eines Servers mit den aktuellen
    /// Zugangsdaten neu auf (nach Aenderung im Server-Editor).
    private func resubscribeTopics(ofServer serverURL: String) {
        let currentTopics = topics.filter { !$0.isDeleted && $0.modelContext != nil }
        let currentKeys = Set(currentTopics.map { SubscribedTopic(serverURL: $0.serverURL, name: $0.name) })
        for topic in currentTopics where topic.serverURL == serverURL {
            resubscribe(topic, replacing: subscribedTopicIds[topic.id], currentKeys: currentKeys)
        }
    }

    /// Abonniert das Topic neu (aktuelle URL + Keychain-Daten) und beendet danach die
    /// alte Subscription, sofern kein anderes Topic sie noch nutzt. Neu vor alt, damit
    /// der FCM-Refcount (TopicServerMap) bei gleichem Namen nie auf 0 faellt.
    private func resubscribe(_ topic: Topic, replacing old: SubscribedTopic?, currentKeys: Set<SubscribedTopic>) {
        subscribe(to: topic)

        guard let old,
              old != SubscribedTopic(serverURL: topic.serverURL, name: topic.name),
              !currentKeys.contains(old) else { return }
        ntfyService.unsubscribe(serverURL: old.serverURL, topic: old.name)
        FirebaseService.shared.unsubscribeFromTopic(serverURL: old.serverURL, topic: old.name)
        AppLog.ui.info("🔌 Subscription fuer '\(old.name, privacy: .private)' auf neuen Server umgezogen")
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
                Task {
                    await NotificationService.shared.syncBadgeWithUnreadCount(context: context)
                }
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

// MARK: - Stummgeschaltete Topics (App Group)

/// Schreibt die stummgeschalteten Topics in die App-Group-UserDefaults, damit die
/// NotificationServiceExtension Push-Mitteilungen dieser Topics still zustellt.
/// Format (siehe SharedStore in der NSE):
/// - `mutedTopicKeys`: ["<serverURL>|<name>"] aller stummen Topics
/// - `mutedTopicNames`: Namen, bei denen ALLE gleichnamigen Topics stumm sind
///   (fuer Pushes, deren Server die NSE nicht eindeutig kennt)
@MainActor
private enum MutedTopicsSync {
    static let appGroup = "group.de.godsapp.ntfy"
    static let keysKey = "mutedTopicKeys"
    static let namesKey = "mutedTopicNames"

    static func write(topics: [Topic]) {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return }
        let liveTopics = topics.filter { !$0.isDeleted && $0.modelContext != nil }

        var mutedKeys: Set<String> = []
        var allMutedByName: [String: Bool] = [:]
        for topic in liveTopics {
            if topic.isMuted {
                mutedKeys.insert("\(topic.serverURL)|\(topic.name)")
            }
            allMutedByName[topic.name] = (allMutedByName[topic.name] ?? true) && topic.isMuted
        }
        let mutedNames = allMutedByName.filter { $0.value }.map { $0.key }

        defaults.set(mutedKeys.sorted(), forKey: keysKey)
        defaults.set(mutedNames.sorted(), forKey: namesKey)
    }
}

// MARK: - App-Sperre (eigenes Fenster)

/// true, solange die App-Sperre aktiv ist — Views markieren dann nichts als gelesen.
private struct AppLockedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isAppLocked: Bool {
        get { self[AppLockedKey.self] }
        set { self[AppLockedKey.self] = newValue }
    }
}

/// Was das Sperrfenster gerade zeigt.
private enum LockWindowContent {
    case hidden
    case privacy
    case lockScreen
}

/// Inhalt des Sperrfensters. Stabile Wurzel, damit der LockScreenView-State
/// (z.B. "bereits automatisch authentifiziert") bei Phasenwechseln erhalten bleibt.
private struct LockWindowRootView: View {
    let content: LockWindowContent
    let isSceneActive: Bool
    let onUnlock: () -> Void

    var body: some View {
        if content == .lockScreen {
            ZStack {
                // Deckender Hintergrund — das Material allein darf keine Inhalte durchscheinen lassen
                Color(.systemBackground)
                    .ignoresSafeArea()
                LockScreenView(isSceneActive: isSceneActive, onUnlock: onUnlock)
            }
            .tint(Color(hex: AppSettings.accentColorHex))
        } else if content == .privacy {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()
                Image(systemName: "lock.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        } else {
            Color.clear
        }
    }
}

/// App-weiter Sperrzustand — von allen ContentViews (eine pro Szene) geteilt, damit
/// eine Entsperrung in einem Fenster alle Fenster freigibt.
@Observable
@MainActor
private final class AppLockState {
    static let shared = AppLockState()

    var isLocked: Bool

    private init() {
        isLocked = AppSettings.biometricLockEnabled
    }
}

/// Haelt die UIWindowScene eines ContentView (schwach, ohne View-Updates auszuloesen).
@MainActor
private final class WindowSceneBox {
    weak var scene: UIWindowScene?
}

/// Meldet die UIWindowScene, in deren Fenster die View haengt.
private struct WindowSceneReader: UIViewRepresentable {
    let onSceneChange: (UIWindowScene?) -> Void

    func makeUIView(context: Context) -> WindowSceneReaderView {
        let view = WindowSceneReaderView()
        view.onSceneChange = onSceneChange
        return view
    }

    func updateUIView(_ uiView: WindowSceneReaderView, context: Context) {
        uiView.onSceneChange = onSceneChange
    }
}

private final class WindowSceneReaderView: UIView {
    var onSceneChange: ((UIWindowScene?) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        backgroundColor = .clear
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        let scene = window?.windowScene
        // Nicht mitten im SwiftUI-Update andere Fenster umbauen
        Task { @MainActor [weak self] in
            self?.onSceneChange?(scene)
        }
    }
}

/// Zeigt Sperrbildschirm und Datenschutz-Abdeckung in je einem eigenen UIWindow pro
/// UIWindowScene oberhalb der Alert-Ebene — ein Overlay im SwiftUI-Baum liegt unter
/// Sheets, Alerts und Popovers und wuerde deren Inhalte nicht verdecken. Jede Szene
/// (iPad-Multiwindow) bekommt ihr eigenes Sperrfenster; getrennte Szenen werden entfernt.
@MainActor
private final class LockWindowPresenter {
    static let shared = LockWindowPresenter()

    @MainActor
    private final class Entry {
        weak var scene: UIWindowScene?
        let window: UIWindow
        let hostingController: UIHostingController<LockWindowRootView>
        var content: LockWindowContent = .hidden
        var isSceneActive = false
        var onUnlock: () -> Void = {}

        init(scene: UIWindowScene) {
            self.scene = scene
            let controller = UIHostingController(
                rootView: LockWindowRootView(content: .hidden, isSceneActive: false, onUnlock: {})
            )
            controller.view.backgroundColor = .clear
            // VoiceOver bleibt im Sperrfenster
            controller.view.accessibilityViewIsModal = true
            let window = UIWindow(windowScene: scene)
            window.windowLevel = .alert + 1
            window.rootViewController = controller
            window.isHidden = true
            self.window = window
            self.hostingController = controller
        }
    }

    private var entries: [ObjectIdentifier: Entry] = [:]
    /// Szene, deren Sperrbildschirm automatisch authentifizieren darf — nur eine
    /// gleichzeitig, sonst konkurrieren mehrere Face-ID-Dialoge.
    private var autoAuthSceneID: ObjectIdentifier?
    private var disconnectObserver: NSObjectProtocol?

    private init() {
        disconnectObserver = NotificationCenter.default.addObserver(
            forName: UIScene.didDisconnectNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let scene = notification.object as? UIWindowScene else { return }
            let sceneID = ObjectIdentifier(scene)
            MainActor.assumeIsolated {
                self?.removeEntry(for: sceneID)
            }
        }
    }

    /// - Parameter requestedScene: Szene des aufrufenden ContentView; nil, solange sie
    ///   noch nicht bekannt ist (dann nur bei genau einer verbundenen Szene diese nutzen).
    func update(scene requestedScene: UIWindowScene?,
                content: LockWindowContent,
                isSceneActive: Bool,
                onUnlock: @escaping () -> Void) {
        pruneDisconnectedEntries()

        guard let scene = requestedScene ?? Self.fallbackScene() else {
            if content != .hidden {
                AppLog.ui.error("🔒 Keine eindeutige UIWindowScene fuer das Sperrfenster gefunden")
            }
            return
        }
        let sceneID = ObjectIdentifier(scene)

        let entry: Entry
        if let existing = entries[sceneID] {
            entry = existing
        } else {
            // Fuer "nichts anzeigen" kein Fenster anlegen
            guard content != .hidden else { return }
            entry = Entry(scene: scene)
            entries[sceneID] = entry
        }
        entry.content = content
        entry.isSceneActive = isSceneActive
        entry.onUnlock = onUnlock

        let previousOwner = autoAuthSceneID
        updateAutoAuthOwner(preferring: sceneID)

        if previousOwner != autoAuthSceneID {
            // Besitzer gewechselt — alle Sperrfenster neu darstellen
            for (id, other) in entries {
                render(other, sceneID: id)
            }
        } else {
            render(entry, sceneID: sceneID)
        }
    }

    // MARK: Interna

    private func updateAutoAuthOwner(preferring sceneID: ObjectIdentifier) {
        if let owner = autoAuthSceneID {
            if let ownerEntry = entries[owner], ownerEntry.content == .lockScreen {
                return
            }
            autoAuthSceneID = nil
        }
        if let preferred = entries[sceneID], preferred.content == .lockScreen, preferred.isSceneActive {
            autoAuthSceneID = sceneID
            return
        }
        autoAuthSceneID = entries.first { $0.value.content == .lockScreen && $0.value.isSceneActive }?.key
    }

    private func render(_ entry: Entry, sceneID: ObjectIdentifier) {
        let mayAutoAuthenticate = entry.isSceneActive && autoAuthSceneID == sceneID
        entry.hostingController.rootView = LockWindowRootView(
            content: entry.content,
            isSceneActive: mayAutoAuthenticate,
            onUnlock: entry.onUnlock
        )

        guard entry.content != .hidden else {
            entry.window.isHidden = true
            return
        }

        entry.window.overrideUserInterfaceStyle = Self.interfaceStyle
        if entry.window.isHidden {
            // Offene Tastatur (z.B. in einem Sheet) schliessen — sie laege sonst ueber der Sperre
            _ = UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            entry.window.isHidden = false
        }
    }

    private func removeEntry(for sceneID: ObjectIdentifier) {
        guard let entry = entries.removeValue(forKey: sceneID) else { return }
        entry.window.isHidden = true
        if autoAuthSceneID == sceneID {
            autoAuthSceneID = nil
        }
    }

    /// Entfernt Fenster von Szenen, die nicht mehr verbunden sind.
    private func pruneDisconnectedEntries() {
        let connected = Set(UIApplication.shared.connectedScenes.map { ObjectIdentifier($0) })
        let staleIDs = entries.filter { $0.value.scene == nil || !connected.contains($0.key) }.map { $0.key }
        for id in staleIDs {
            removeEntry(for: id)
        }
    }

    /// Nur eindeutig: bei mehreren Szenen koennte sonst die falsche abgedeckt werden.
    private static func fallbackScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.count == 1 ? scenes.first : nil
    }

    /// Eigenes Fenster erbt .preferredColorScheme der App nicht — Theme direkt setzen.
    private static var interfaceStyle: UIUserInterfaceStyle {
        switch AppSettings.appTheme {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
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
