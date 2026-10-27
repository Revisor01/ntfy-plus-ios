import UIKit
import UserNotifications
import SwiftData
#if canImport(FirebaseCore)
import FirebaseCore
import FirebaseMessaging
#endif

class AppDelegate: NSObject, UIApplicationDelegate {

    /// Topic aus einem Mitteilungs-Tap beim Kaltstart; ContentView übernimmt es, bei Sperre erst nach dem Entsperren.
    @MainActor static var pendingNotificationTopic: String?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {

        #if canImport(FirebaseCore)
        FirebaseApp.configure()

        Messaging.messaging().delegate = self
        #endif

        UNUserNotificationCenter.current().delegate = self

        // Einziger automatischer Aufruf beim Start; SettingsView fragt nur auf Nutzeraktion.
        Task { @MainActor in
            let granted = await NotificationService.shared.requestAuthorization()
            if granted {
                AppLog.app.info("Notification permission granted")
            }
        }

        application.registerForRemoteNotifications()

        return true
    }

    // MARK: - Remote Notifications

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        #if canImport(FirebaseMessaging)
        Messaging.messaging().apnsToken = deviceToken
        #endif

        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        AppLog.app.info("APNs Device Token: \(tokenString, privacy: .private)")

        NotificationCenter.default.post(name: .apnsTokenReceived, object: nil)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        AppLog.app.error("Failed to register for remote notifications: \(error.localizedDescription, privacy: .public)")
    }

    // MARK: - Handle Background Notifications

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {

        AppLog.app.info("📬 Received remote notification (background fetch)")

        // Die NSE stellt die Mitteilung schon zu; hier keine zusätzliche.

        completionHandler(.newData)
    }

}

// MARK: - UNUserNotificationCenterDelegate
extension AppDelegate: UNUserNotificationCenterDelegate {
    // Mitteilung auch im Vordergrund zeigen.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Von der NSE abgelegte Nachricht direkt in SwiftData uebernehmen
        Task { @MainActor in
            if let container = SharedModel.container {
                PendingMessageImporter.importPendingMessages(context: container.mainContext)
            }
        }

        completionHandler([.banner, .sound, .badge])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        // Nur Sendable-Werte in die MainActor-Tasks mitnehmen
        let userInfo = response.notification.request.content.userInfo
        let notificationIdentifier = response.notification.request.identifier
        let completion = CompletionHandlerBox(completionHandler)

        let topicName = userInfo["topic"] as? String
        let serverURLHint = userInfo["serverURL"] as? String
        // userInfo key "messageId" for local notifications, "id" for push
        let messageId = (userInfo["messageId"] as? String) ?? (userInfo["id"] as? String)
        let clickString = userInfo["click"] as? String

        switch response.actionIdentifier {
        case "MARK_READ":
            Task { @MainActor in
                await AppDelegate.markMessageRead(messageId: messageId, notificationIdentifier: notificationIdentifier)
                completion.call()
            }

        case "REPLY":
            guard let textResponse = response as? UNTextInputNotificationResponse,
                  let topicName = topicName, !topicName.isEmpty else {
                completion.call()
                return
            }
            let replyText = textResponse.userText
            guard !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                completion.call()
                return
            }
            // completionHandler erst nach abgeschlossenem Publish aufrufen
            Task { @MainActor in
                await AppDelegate.sendReply(text: replyText, topicName: topicName, serverURLHint: serverURLHint)
                completion.call()
            }

        case "OPEN_URL":
            // userInfo["url"] der Action, sonst userInfo["click"]
            let urlString = (userInfo["url"] as? String) ?? clickString
            if let url = AppDelegate.safeWebURL(from: urlString) {
                AppLog.app.info("🔗 OPEN_URL action: \(url.absoluteString, privacy: .private)")
                Task { @MainActor in
                    UIApplication.shared.open(url)
                }
            }
            completion.call()

        default:
            // Normaler Tap: App öffnen und navigieren, Klick-URL beachten.
            if let clickURL = AppDelegate.safeWebURL(from: clickString) {
                AppLog.app.info("🔗 Opening click URL: \(clickURL.absoluteString, privacy: .private)")
                Task { @MainActor in
                    UIApplication.shared.open(clickURL)
                }
            }

            if let topic = topicName {
                Task { @MainActor in
                    // Beim Kaltstart gibt es ContentView noch nicht, daher Ziel puffern.
                    AppDelegate.pendingNotificationTopic = topic
                    NotificationCenter.default.post(
                        name: .navigateToTopic,
                        object: nil,
                        userInfo: ["topic": topic]
                    )
                }
            }
            completion.call()
        }
    }
}

// MARK: - Notification Action Handling

extension AppDelegate {
    /// Nur http(s) öffnen, keine javascript:/data:/file:-Schemes aus fremden Nachrichten.
    nonisolated static func safeWebURL(from string: String?) -> URL? {
        guard let string = string, !string.isEmpty else { return nil }
        guard let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            AppLog.app.error("❌ Notification-URL mit unsicherem Schema abgelehnt")
            return nil
        }
        return url
    }

    /// MARK_READ direkt in SwiftData, damit es auch ohne geladene UI wirkt.
    @MainActor
    static func markMessageRead(messageId: String?, notificationIdentifier: String) async {
        NotificationService.shared.removeNotification(withIdentifier: notificationIdentifier)

        guard let messageId = messageId else { return }
        NotificationService.shared.removeNotification(withIdentifier: messageId)

        guard let container = try? SharedModel.makeContainer() else {
            // Fallback: alter Weg ueber ContentView
            AppLog.app.error("MARK_READ: ModelContainer nicht verfuegbar — delegiere an UI")
            NotificationCenter.default.post(
                name: .markMessageRead,
                object: nil,
                userInfo: ["messageId": messageId]
            )
            return
        }
        let context = container.mainContext

        // Nachricht ggf. erst aus dem NSE-Ablageordner uebernehmen
        PendingMessageImporter.importPendingMessages(context: context)

        let predicate = #Predicate<StoredMessage> { $0.messageId == messageId }
        let descriptor = FetchDescriptor(predicate: predicate)
        if let message = (try? context.fetch(descriptor))?.first, !message.isRead {
            message.isRead = true
            if let topic = message.topic {
                topic.unreadCount = max(0, topic.unreadCount - 1)
            }
            try? context.save()
            NtfyService.shared.writeWidgetData(context: context)
        }

        await NotificationService.shared.syncBadgeWithUnreadCount(context: context)
    }

    /// REPLY an den Server des Topics mit dessen Zugangsdaten, im Background-Task.
    @MainActor
    static func sendReply(text: String, topicName: String, serverURLHint: String?) async {
        let backgroundTask = BackgroundTaskToken()
        backgroundTask.identifier = UIApplication.shared.beginBackgroundTask(withName: "ntfy-reply") {
            MainActor.assumeIsolated {
                backgroundTask.end()
            }
        }
        defer { backgroundTask.end() }

        let serverURL = resolveServerURL(topicName: topicName, hint: serverURLHint)
        let token = KeychainManager.shared.loadToken(serverURL: serverURL)
        let credentials = KeychainManager.shared.loadCredentials(serverURL: serverURL)

        do {
            try await NtfyService.shared.publish(
                serverURL: serverURL,
                topic: topicName,
                message: text,
                username: credentials?.username,
                password: credentials?.password,
                token: token
            )
            AppLog.app.info("↩️ Antwort an \(topicName, privacy: .private) gesendet")
        } catch {
            AppLog.app.error("↩️ Antwort an \(topicName, privacy: .private) fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            await postReplyFailedNotification(topicName: topicName)
        }
    }

    /// Server des Topics: userInfo, Topic-Map, SwiftData, erster Map-Eintrag, Default-Server.
    @MainActor
    private static func resolveServerURL(topicName: String, hint: String?) -> String {
        if let hint = hint, !hint.isEmpty {
            return hint
        }

        let mappedServers = TopicServerMap.servers(for: topicName)
        if mappedServers.count == 1, let server = mappedServers.first {
            return server
        }

        if let container = try? SharedModel.makeContainer() {
            let predicate = #Predicate<Topic> { $0.name == topicName }
            let descriptor = FetchDescriptor(predicate: predicate)
            if let topic = (try? container.mainContext.fetch(descriptor))?.first {
                return topic.serverURL
            }
        }

        return mappedServers.first ?? AppSettings.defaultServerURL
    }

    @MainActor
    private static func postReplyFailedNotification(topicName: String) async {
        let content = UNMutableNotificationContent()
        content.title = "Antwort nicht gesendet"
        content.body = "Deine Antwort an „\(topicName)“ konnte nicht zugestellt werden."
        content.threadIdentifier = topicName
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "reply-failed-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            AppLog.app.error("Fehler-Notification konnte nicht angezeigt werden: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Reicht den nicht-Sendable completionHandler an MainActor-Tasks weiter.
private struct CompletionHandlerBox: @unchecked Sendable {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    func call() {
        handler()
    }
}

/// Hält die Background-Task-ID, damit sie genau einmal beendet wird.
@MainActor
private final class BackgroundTaskToken {
    var identifier: UIBackgroundTaskIdentifier = .invalid

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}

#if canImport(FirebaseMessaging)
extension AppDelegate: MessagingDelegate {
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken = fcmToken else { return }
        AppLog.app.info("Firebase FCM Token: \(fcmToken, privacy: .private)")

        try? KeychainManager.shared.saveFCMToken(fcmToken)

        Task { @MainActor in
            NotificationCenter.default.post(
                name: Notification.Name("FCMTokenReceived"),
                object: nil,
                userInfo: ["token": fcmToken]
            )
        }
    }
}
#endif
