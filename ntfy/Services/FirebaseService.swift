import Foundation
#if canImport(FirebaseMessaging)
import FirebaseMessaging
#endif

/// Service to manage Firebase Cloud Messaging topic subscriptions
/// ntfy server sends to FCM topics using plain topic names
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

        // Listen for APNs token received notification
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

        // Process all pending subscriptions
        for pending in pendingSubscriptions {
            performSubscription(serverURL: pending.serverURL, topic: pending.topic)
        }
        pendingSubscriptions.removeAll()
    }

    /// Subscribe to a ntfy topic via Firebase
    /// - Parameters:
    ///   - serverURL: The ntfy server URL (e.g., "https://push.godsapp.de")
    ///   - topic: The topic name (e.g., "mytopic")
    func subscribeToTopic(serverURL: String, topic: String) {
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
        // ntfy server sends to FCM topic using the plain topic name (not hashed)
        // So we subscribe directly to the topic name
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

    /// Unsubscribe from a ntfy topic via Firebase
    /// - Parameters:
    ///   - serverURL: The ntfy server URL
    ///   - topic: The topic name
    func unsubscribeFromTopic(serverURL: String, topic: String) {
        #if canImport(FirebaseMessaging)
        // Use plain topic name to match subscription
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
