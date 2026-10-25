import Foundation
import UserNotifications
import UIKit
import SwiftData

@MainActor
final class NotificationService: NSObject {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()
    /// Gesammelte Nachrichten-IDs fuer den gebuendelten Abgleich mit der Mitteilungszentrale
    private var pendingRemovalIds: Set<String> = []
    private var removalTask: Task<Void, Never>?

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
        await center.deliveredNotifications().count
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

    /// Entfernt die Mitteilung(en) zu einer Request- oder ntfy-Nachrichten-ID. Push-
    /// Mitteilungen haben eine von APNs vergebene Request-ID — sie werden ueber
    /// `userInfo["id"]` gefunden. Aufrufe im selben Durchlauf (z.B. Schleifen) werden
    /// zu einem einzigen Abgleich mit der Mitteilungszentrale gebuendelt.
    func removeNotification(withIdentifier identifier: String) {
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        pendingRemovalIds.insert(identifier)
        guard removalTask == nil else { return }
        removalTask = Task {
            let ids = self.pendingRemovalIds
            self.pendingRemovalIds.removeAll()
            self.removalTask = nil
            await self.removeDeliveredNotifications(matchingMessageIds: ids)
        }
    }

    /// Entfernt zugestellte Mitteilungen, deren Request-ID oder `userInfo["id"]` /
    /// `userInfo["messageId"]` einer der IDs entspricht. `sequence_id` wird bewusst
    /// nicht verglichen: sonst verschwaende beim Ersetzen der alten Version auch die
    /// Mitteilung des Updates (gleiche sequence_id).
    func removeDeliveredNotifications(matchingMessageIds messageIds: Set<String>) async {
        guard !messageIds.isEmpty else { return }
        let delivered = await center.deliveredNotifications()
        let identifiers = delivered.compactMap { notification -> String? in
            let request = notification.request
            if messageIds.contains(request.identifier) {
                return request.identifier
            }
            let userInfo = request.content.userInfo
            for key in ["id", "messageId"] {
                if let value = userInfo[key] as? String, messageIds.contains(value) {
                    return request.identifier
                }
            }
            return nil
        }
        guard !identifiers.isEmpty else { return }
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
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
    /// Server-URL oder Zugangsdaten eines Servers wurden geaendert — userInfo["serverURL"] = (neue) URL
    static let serverConfigurationChanged = Notification.Name("serverConfigurationChanged")
}
