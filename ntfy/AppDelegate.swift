import UIKit
import UserNotifications
import SwiftData
#if canImport(FirebaseCore)
import FirebaseCore
import FirebaseMessaging
#endif

class AppDelegate: NSObject, UIApplicationDelegate {

    /// Topic aus einem Mitteilungs-Tap, das noch keine UI angesteuert hat (Kaltstart:
    /// `.navigateToTopic` wird gepostet, bevor ContentView existiert). ContentView
    /// uebernimmt und leert es — bei aktiver Sperre erst nach der Entsperrung.
    @MainActor static var pendingNotificationTopic: String?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {

        #if canImport(FirebaseCore)
        // Configure Firebase
        FirebaseApp.configure()

        // Set messaging delegate
        Messaging.messaging().delegate = self
        #endif

        // Set notification delegate
        UNUserNotificationCenter.current().delegate = self

        // Request notification authorization — einziger automatischer Aufruf beim Start
        // (ContentView fragt nicht mehr zusaetzlich; SettingsView nur auf Nutzeraktion)
        Task { @MainActor in
            let granted = await NotificationService.shared.requestAuthorization()
            if granted {
                AppLog.app.info("Notification permission granted")
            }
        }

        // Register for remote notifications
        application.registerForRemoteNotifications()

        return true
    }

    // MARK: - Remote Notifications

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        #if canImport(FirebaseMessaging)
        // Pass device token to Firebase
        Messaging.messaging().apnsToken = deviceToken
        #endif

        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        AppLog.app.info("APNs Device Token: \(tokenString, privacy: .private)")

        // Notify FirebaseService that APNs token is available
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

        // The NotificationServiceExtension already handles the push notification
        // and removes the subtitle. This method is called for background fetch
        // but we don't need to create additional notifications.

        // Just acknowledge receipt
        completionHandler(.newData)
    }

}

// MARK: - UNUserNotificationCenterDelegate
extension AppDelegate: UNUserNotificationCenterDelegate {
    // Show notification when app is in foreground
    // NotificationServiceExtension already removed the subtitle, so just show it
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Von der NSE abgelegte Nachricht direkt in SwiftData uebernehmen
        Task { @MainActor in
            if let container = SharedModel.container {
                PendingMessageImporter.importPendingMessages(context: container.mainContext)
            }
        }

        // Show the notification as-is (subtitle already removed by extension)
        completionHandler([.banner, .sound, .badge])
    }

    // Handle notification tap and actions
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
            // URL aus userInfo["url"] lesen (ntfy action-spezifisches Feld)
            // Fallback auf userInfo["click"] falls kein "url"-Key vorhanden
            let urlString = (userInfo["url"] as? String) ?? clickString
            if let url = AppDelegate.safeWebURL(from: urlString) {
                AppLog.app.info("🔗 OPEN_URL action: \(url.absoluteString, privacy: .private)")
                Task { @MainActor in
                    UIApplication.shared.open(url)
                }
            }
            completion.call()

        default:
            // Normal tap (UNNotificationDefaultActionIdentifier) — open app and navigate
            // Handle click URL if present (ntfy v2.16+)
            if let clickURL = AppDelegate.safeWebURL(from: clickString) {
                AppLog.app.info("🔗 Opening click URL: \(clickURL.absoluteString, privacy: .private)")
                Task { @MainActor in
                    UIApplication.shared.open(clickURL)
                }
            }

            // Navigate to topic if available
            if let topic = topicName {
                Task { @MainActor in
                    // Beim Kaltstart existiert ContentView noch nicht und verpasst die
                    // Notification — Ziel puffern; ContentView uebernimmt es beim Erscheinen
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
    /// Nur sichere Web-Schemes oeffnen (gleiche Regel wie MessageRow.openURL) —
    /// verhindert javascript:/data:/file:/Custom-Schemes aus fremden Nachrichten.
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

    /// MARK_READ: SwiftData direkt aktualisieren (funktioniert auch, wenn die UI nicht
    /// geladen ist), danach Badge aus den ungelesenen Nachrichten neu setzen.
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

    /// REPLY: an den Server des Topics (nicht den Default-Server) mit dessen
    /// Zugangsdaten publizieren. Laeuft in einem Background-Task; Fehler werden
    /// geloggt und per lokaler Notification gemeldet.
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

    /// Server des Topics: userInfo["serverURL"] (von der NSE gesetzt) → eindeutige
    /// Topic→Server-Map → SwiftData-Topic → erster Map-Eintrag → Default-Server.
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

/// Reicht den nicht-Sendable completionHandler der Delegate-Methode in MainActor-Tasks
/// weiter. UIKit erlaubt den Aufruf von beliebigen Threads; hier erfolgt er auf Main.
private struct CompletionHandlerBox: @unchecked Sendable {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    func call() {
        handler()
    }
}

/// Haelt die Background-Task-ID, damit Expiration-Handler und regulaeres Ende
/// sie genau einmal beenden.
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

        // Store token for later use
        try? KeychainManager.shared.saveFCMToken(fcmToken)

        // Post notification so other parts of the app can use the token
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
