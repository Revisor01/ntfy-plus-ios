import Foundation
import UserNotifications
import UIKit
import SwiftData

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
            // Einziger Autorisierungs-Pfad der App (AppDelegate ruft ebenfalls hierher).
            // Ohne .provisional: sonst landet die App je nach Aufrufreihenfolge still
            // in der Mitteilungszentrale statt den regulaeren Dialog zu zeigen.
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            if granted {
                registerForRemoteNotifications()
            }
            return granted
        } catch {
            AppLog.notifications.error("Notification authorization error: \(error.localizedDescription, privacy: .public)")
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

    // MARK: - Badge Management

    func getBadgeCount() async -> Int {
        do {
            let delivered = await center.deliveredNotifications()
            return delivered.count
        }
    }

    /// Geteilter Badge-Zaehler im App-Group-Container. Die NotificationServiceExtension
    /// inkrementiert ihn pro Push; die App schreibt bei jedem Setzen den massgeblichen Wert,
    /// damit die NSE vom richtigen Stand aus weiterzaehlt.
    nonisolated static var sharedBadgeFileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.de.godsapp.ntfy")?
            .appendingPathComponent("badge_count.txt")
    }

    func setBadgeCount(_ count: Int) async {
        let safeCount = max(0, count)
        if let url = Self.sharedBadgeFileURL {
            try? String(safeCount).write(to: url, atomically: true, encoding: .utf8)
        }
        do {
            try await center.setBadgeCount(safeCount)
        } catch {
            AppLog.notifications.error("Failed to set badge: \(error.localizedDescription, privacy: .public)")
        }
    }

    func clearBadge() async {
        // setBadgeCount setzt auch den geteilten Zaehler der NotificationServiceExtension zurueck
        await setBadgeCount(0)
    }

    /// Setzt den Badge auf die Anzahl ungelesener Nachrichten in SwiftData.
    func syncBadgeWithUnreadCount(context: ModelContext) async {
        let unreadPredicate = #Predicate<StoredMessage> { !$0.isRead }
        let descriptor = FetchDescriptor(predicate: unreadPredicate)
        let unreadCount = (try? context.fetchCount(descriptor)) ?? 0
        await setBadgeCount(unreadCount)
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
            hiddenPreviewsBodyPlaceholder: "Neue Nachricht",
            categorySummaryFormat: "%u weitere Nachrichten",
            options: [.customDismissAction]
        )

        center.setNotificationCategories([messageCategory])
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let navigateToTopic = Notification.Name("navigateToTopic")
    static let messageReceived = Notification.Name("messageReceived")
    static let apnsTokenReceived = Notification.Name("apnsTokenReceived")
    static let markMessageRead = Notification.Name("markMessageRead")
}
