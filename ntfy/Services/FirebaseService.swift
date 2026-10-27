import Foundation
#if canImport(FirebaseMessaging)
import FirebaseMessaging
#endif

/// Verwaltet die FCM-Topic-Abos; ntfy sendet an den unveränderten Topic-Namen.
@MainActor
final class FirebaseService {
    static let shared = FirebaseService()

    /// Whether APNs token has been received and FCM is ready
    private(set) var isReady = false

    /// Pending topic subscriptions waiting for APNs token
    private var pendingSubscriptions: [(serverURL: String, topic: String)] = []

    private init() {
        // Check if APNs token was already received (in case we're initialized late)
        #if canImport(FirebaseMessaging)
        if Messaging.messaging().apnsToken != nil {
            isReady = true
            AppLog.firebase.info("FirebaseService initialized - APNs token already available")
        }
        #endif

        NotificationCenter.default.addObserver(
            forName: .apnsTokenReceived,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleAPNsTokenReceived()
            }
        }
    }

    /// Called when APNs token is received - process pending subscriptions
    private func handleAPNsTokenReceived() {
        AppLog.firebase.info("APNs token received - processing \(self.pendingSubscriptions.count, privacy: .public) pending FCM subscriptions")
        isReady = true

        for pending in pendingSubscriptions {
            performSubscription(serverURL: pending.serverURL, topic: pending.topic)
        }
        pendingSubscriptions.removeAll()
    }

    /// Abonniert ein ntfy-Topic über Firebase.
    func subscribeToTopic(serverURL: String, topic: String) {
        // Map sofort pflegen, damit die NSE poll_requests dem Server zuordnen kann.
        TopicServerMap.add(serverURL: serverURL, topic: topic)

        #if canImport(FirebaseMessaging)
        // Check again if APNs token is now available (might have arrived since init)
        if !isReady && Messaging.messaging().apnsToken != nil {
            isReady = true
            AppLog.firebase.info("FirebaseService: APNs token now available")
        }
        #endif

        if isReady {
            performSubscription(serverURL: serverURL, topic: topic)
        } else {
            // Queue subscription for later when APNs token is available
            AppLog.firebase.info("APNs token not yet available - queuing FCM subscription for \(serverURL, privacy: .private)/\(topic, privacy: .private)")
            pendingSubscriptions.append((serverURL: serverURL, topic: topic))
        }
    }

    /// Actually perform the FCM subscription
    private func performSubscription(serverURL: String, topic: String) {
        #if canImport(FirebaseMessaging)
        // ntfy sendet an den unveränderten Topic-Namen.
        let fcmTopic = topic

        AppLog.firebase.info("🔔 Subscribing to FCM topic: '\(fcmTopic, privacy: .private)' (APNs token: \(Messaging.messaging().apnsToken != nil ? "✓" : "✗", privacy: .public))")

        Messaging.messaging().subscribe(toTopic: fcmTopic) { error in
            if let error = error {
                AppLog.firebase.error("🔔 ❌ Failed to subscribe to FCM topic '\(fcmTopic, privacy: .private)': \(error.localizedDescription, privacy: .public)")
            } else {
                AppLog.firebase.info("🔔 ✅ Successfully subscribed to FCM topic: '\(fcmTopic, privacy: .private)'")
            }
        }
        #else
        AppLog.firebase.info("Firebase not configured - skipping FCM subscription for \(serverURL, privacy: .private)/\(topic, privacy: .private)")
        #endif
    }

    /// Meldet ein ntfy-Topic bei Firebase ab.
    func unsubscribeFromTopic(serverURL: String, topic: String) {
        // Noch wartende Subscription fuer genau diesen Server verwerfen
        pendingSubscriptions.removeAll { $0.serverURL == serverURL && $0.topic == topic }

        // FCM kennt nur den Namen: nutzt ein anderer Server ihn noch, bleibt das Abo.
        let remainingServers = TopicServerMap.remove(serverURL: serverURL, topic: topic)
        guard remainingServers.isEmpty else {
            AppLog.firebase.info("FCM topic \(topic, privacy: .private) bleibt abonniert — noch \(remainingServers.count, privacy: .public) weitere(r) Server")
            return
        }

        #if canImport(FirebaseMessaging)
        let fcmTopic = topic

        Messaging.messaging().unsubscribe(fromTopic: fcmTopic) { error in
            if let error = error {
                AppLog.firebase.error("Failed to unsubscribe from FCM topic \(fcmTopic, privacy: .private): \(error.localizedDescription, privacy: .public)")
            } else {
                AppLog.firebase.info("Successfully unsubscribed from FCM topic: \(fcmTopic, privacy: .private)")
            }
        }
        #else
        AppLog.firebase.info("Firebase not configured - skipping FCM unsubscription for \(serverURL, privacy: .private)/\(topic, privacy: .private)")
        #endif
    }

    /// Get the current FCM token
    var currentToken: String? {
        return KeychainManager.shared.loadFCMToken()
    }

    /// Check if Firebase is properly configured
    var isConfigured: Bool {
        #if canImport(FirebaseMessaging)
        return currentToken != nil
        #else
        return false
        #endif
    }
}

// MARK: - Topic→Server-Map (App Group)

/// Topic-Name zu Servern in der App Group, damit die NSE bei poll_request den Server findet.
enum TopicServerMap {
    static let suiteName = "group.de.godsapp.ntfy"
    static let key = "topicServers"

    static func servers(for topic: String) -> [String] {
        load()[topic] ?? []
    }

    static func add(serverURL: String, topic: String) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        var map = load()
        var servers = map[topic] ?? []
        guard !servers.contains(serverURL) else { return }
        servers.append(serverURL)
        map[topic] = servers
        defaults.set(map, forKey: key)
    }

    /// Entfernt den Server fuer das Topic und liefert die verbleibenden Server zurueck.
    @discardableResult
    static func remove(serverURL: String, topic: String) -> [String] {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return [] }
        var map = load()
        var servers = map[topic] ?? []
        servers.removeAll { $0 == serverURL }
        if servers.isEmpty {
            map.removeValue(forKey: topic)
        } else {
            map[topic] = servers
        }
        defaults.set(map, forKey: key)
        return servers
    }

    private static func load() -> [String: [String]] {
        UserDefaults(suiteName: suiteName)?.dictionary(forKey: key) as? [String: [String]] ?? [:]
    }
}
