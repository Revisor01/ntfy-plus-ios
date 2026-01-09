import UserNotifications
import os.log

private let logger = Logger(subsystem: "de.godsapp.ntfy.NotificationServiceExtension", category: "NotificationService")

class NotificationService: UNNotificationServiceExtension {

    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    // File-based badge counter (works without App Group entitlement issues)
    private var badgeFileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.de.godsapp.ntfy")?
            .appendingPathComponent("badge_count.txt")
    }

    private func getBadgeCount() -> Int {
        guard let url = badgeFileURL,
              let content = try? String(contentsOf: url, encoding: .utf8),
              let count = Int(content.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return 0
        }
        return count
    }

    private func setBadgeCount(_ count: Int) {
        guard let url = badgeFileURL else { return }
        try? String(count).write(to: url, atomically: true, encoding: .utf8)
    }

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        logger.info("🔔 NotificationServiceExtension didReceive called!")

        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)

        if let bestAttemptContent = bestAttemptContent {
            logger.info("🔔 Processing notification: \(bestAttemptContent.title)")

            // Clear subtitle (this removes the topic)
            bestAttemptContent.subtitle = ""

            // Increment badge count
            let newBadge = getBadgeCount() + 1
            setBadgeCount(newBadge)
            bestAttemptContent.badge = NSNumber(value: newBadge)

            logger.info("🔔 Removed subtitle, badge: \(newBadge), delivering notification")
            contentHandler(bestAttemptContent)
        } else {
            logger.error("🔔 Could not create mutable content")
            contentHandler(request.content)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        if let contentHandler = contentHandler, let bestAttemptContent = bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }
}
