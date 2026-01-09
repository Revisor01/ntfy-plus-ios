import Foundation
import UserNotifications
import UIKit

@MainActor
final class NotificationService: NSObject {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()

    override private init() {
        super.init()
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound, .provisional])
            if granted {
                registerForRemoteNotifications()
            }
            return granted
        } catch {
            print("Notification authorization error: \(error)")
            return false
        }
    }

    func checkAuthorizationStatus() async -> UNAuthorizationStatus {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus
    }

    private func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    // MARK: - Local Notifications

    func scheduleLocalNotification(for message: NtfyMessage, topic: String) async {
        let content = UNMutableNotificationContent()

        // Title - don't show topic as subtitle
        if let title = message.title {
            content.title = title
            // No subtitle - we don't want to show the topic
        } else {
            content.title = topic
        }

        // Body
        if let body = message.message {
            content.body = body
        }

        // Sound based on priority
        switch message.priorityLevel {
        case .min:
            content.sound = nil
        case .low:
            content.sound = .default
        case .default:
            content.sound = .default
        case .high:
            content.sound = .defaultCritical
        case .urgent:
            content.sound = .defaultCriticalSound(withAudioVolume: 1.0)
        }

        // Category for actions
        content.categoryIdentifier = "NTFY_MESSAGE"

        // User info
        content.userInfo = [
            "messageId": message.id,
            "topic": topic,
            "time": message.time
        ]

        // Badge
        content.badge = NSNumber(value: await getBadgeCount() + 1)

        // Thread identifier for grouping
        content.threadIdentifier = topic

        // Interruption level based on priority
        if message.priorityLevel == .urgent {
            content.interruptionLevel = .timeSensitive
        } else if message.priorityLevel == .min {
            content.interruptionLevel = .passive
        }

        // Create request
        let request = UNNotificationRequest(
            identifier: message.id,
            content: content,
            trigger: nil // Deliver immediately
        )

        do {
            try await center.add(request)
        } catch {
            print("Failed to schedule notification: \(error)")
        }
    }

    // MARK: - Badge Management

    func getBadgeCount() async -> Int {
        do {
            let delivered = await center.deliveredNotifications()
            return delivered.count
        }
    }

    func setBadgeCount(_ count: Int) async {
        do {
            try await center.setBadgeCount(count)
        } catch {
            print("Failed to set badge: \(error)")
        }
    }

    func clearBadge() async {
        // Reset shared badge counter (used by NotificationServiceExtension)
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.de.godsapp.ntfy")?
            .appendingPathComponent("badge_count.txt") {
            try? "0".write(to: url, atomically: true, encoding: .utf8)
        }

        await setBadgeCount(0)
    }

    // MARK: - Notification Management

    func removeNotification(withIdentifier identifier: String) {
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    func removeAllNotifications() {
        center.removeAllDeliveredNotifications()
        center.removeAllPendingNotificationRequests()
    }

    func removeNotifications(forTopic topic: String) async {
        let delivered = await center.deliveredNotifications()
        let identifiers = delivered
            .filter { $0.request.content.threadIdentifier == topic }
            .map { $0.request.identifier }

        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    // MARK: - Categories & Actions

    func registerNotificationCategories() {
        // Mark as read action
        let markReadAction = UNNotificationAction(
            identifier: "MARK_READ",
            title: "Als gelesen markieren",
            options: []
        )

        // Open URL action (if message has click URL)
        let openURLAction = UNNotificationAction(
            identifier: "OPEN_URL",
            title: "Link öffnen",
            options: [.foreground]
        )

        // Reply action
        let replyAction = UNTextInputNotificationAction(
            identifier: "REPLY",
            title: "Antworten",
            options: [],
            textInputButtonTitle: "Senden",
            textInputPlaceholder: "Nachricht eingeben..."
        )

        // Message category
        let messageCategory = UNNotificationCategory(
            identifier: "NTFY_MESSAGE",
            actions: [markReadAction, openURLAction, replyAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        center.setNotificationCategories([messageCategory])
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Show notification even when app is in foreground
        return [.banner, .sound, .badge, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo

        switch response.actionIdentifier {
        case "MARK_READ":
            if let messageId = userInfo["messageId"] as? String {
                // Mark message as read in database
                await markMessageAsRead(messageId: messageId)
            }

        case "OPEN_URL":
            if let urlString = userInfo["click"] as? String,
               let url = URL(string: urlString) {
                await MainActor.run {
                    UIApplication.shared.open(url)
                }
            }

        case "REPLY":
            if let textResponse = response as? UNTextInputNotificationResponse,
               let topic = userInfo["topic"] as? String {
                await handleReply(text: textResponse.userText, topic: topic)
            }

        case UNNotificationDefaultActionIdentifier:
            // User tapped on notification
            if let topic = userInfo["topic"] as? String {
                await navigateToTopic(topic)
            }

        default:
            break
        }
    }

    private func markMessageAsRead(messageId: String) async {
        // Will be implemented with SwiftData integration
        print("Marking message as read: \(messageId)")
    }

    private func handleReply(text: String, topic: String) async {
        // Will publish reply to topic
        print("Reply to \(topic): \(text)")
    }

    private func navigateToTopic(_ topic: String) async {
        // Will be handled by app navigation
        NotificationCenter.default.post(
            name: .navigateToTopic,
            object: nil,
            userInfo: ["topic": topic]
        )
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let navigateToTopic = Notification.Name("navigateToTopic")
    static let messageReceived = Notification.Name("messageReceived")
    static let apnsTokenReceived = Notification.Name("apnsTokenReceived")
}
