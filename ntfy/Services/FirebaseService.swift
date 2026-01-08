import Foundation
import CryptoKit
#if canImport(FirebaseMessaging)
import FirebaseMessaging
#endif

/// Service to manage Firebase Cloud Messaging topic subscriptions
/// ntfy uses SHA256 hash of the topic URL as the FCM topic name
@MainActor
final class FirebaseService {
    static let shared = FirebaseService()

    private init() {}

    /// Subscribe to a ntfy topic via Firebase
    /// - Parameters:
    ///   - serverURL: The ntfy server URL (e.g., "https://push.godsapp.de")
    ///   - topic: The topic name (e.g., "mytopic")
    func subscribeToTopic(serverURL: String, topic: String) {
        #if canImport(FirebaseMessaging)
        let fcmTopic = hashTopicURL(serverURL: serverURL, topic: topic)

        Messaging.messaging().subscribe(toTopic: fcmTopic) { error in
            if let error = error {
                print("Failed to subscribe to FCM topic \(fcmTopic): \(error)")
            } else {
                print("Successfully subscribed to FCM topic: \(fcmTopic)")
                print("  (for \(serverURL)/\(topic))")
            }
        }
        #else
        print("Firebase not configured - skipping FCM subscription for \(serverURL)/\(topic)")
        #endif
    }

    /// Unsubscribe from a ntfy topic via Firebase
    /// - Parameters:
    ///   - serverURL: The ntfy server URL
    ///   - topic: The topic name
    func unsubscribeFromTopic(serverURL: String, topic: String) {
        #if canImport(FirebaseMessaging)
        let fcmTopic = hashTopicURL(serverURL: serverURL, topic: topic)

        Messaging.messaging().unsubscribe(fromTopic: fcmTopic) { error in
            if let error = error {
                print("Failed to unsubscribe from FCM topic \(fcmTopic): \(error)")
            } else {
                print("Successfully unsubscribed from FCM topic: \(fcmTopic)")
            }
        }
        #else
        print("Firebase not configured - skipping FCM unsubscription for \(serverURL)/\(topic)")
        #endif
    }

    /// Generate the FCM topic name from server URL and topic
    /// ntfy uses SHA256 hash of the full topic URL
    /// - Parameters:
    ///   - serverURL: The ntfy server URL
    ///   - topic: The topic name
    /// - Returns: SHA256 hash of the topic URL (used as FCM topic name)
    private func hashTopicURL(serverURL: String, topic: String) -> String {
        // Normalize the server URL (remove trailing slash)
        var normalizedURL = serverURL
        if normalizedURL.hasSuffix("/") {
            normalizedURL = String(normalizedURL.dropLast())
        }

        // Create the full topic URL
        let topicURL = "\(normalizedURL)/\(topic)"

        // Calculate SHA256 hash
        let data = Data(topicURL.utf8)
        let hash = SHA256.hash(data: data)

        // Convert to hex string
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Get the current FCM token
    var currentToken: String? {
        return UserDefaults.standard.string(forKey: "fcmToken")
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
