import UIKit
import UserNotifications
#if canImport(FirebaseCore)
import FirebaseCore
import FirebaseMessaging
#endif

class AppDelegate: NSObject, UIApplicationDelegate {

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

        // Request notification authorization
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if granted {
                AppLog.app.info("Notification permission granted")
            }
            if let error = error {
                AppLog.app.error("Notification authorization error: \(error.localizedDescription, privacy: .public)")
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
        // Show the notification as-is (subtitle already removed by extension)
        completionHandler([.banner, .sound, .badge])
    }

    // Handle notification tap and actions
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo

        switch response.actionIdentifier {
        case "MARK_READ":
            // userInfo key "messageId" for local notifications, "id" for push
            let messageId = (userInfo["messageId"] as? String) ?? (userInfo["id"] as? String)
            if let messageId = messageId {
                Task { @MainActor in
                    // 1. Badge via shared file dekrementieren
                    if let url = FileManager.default
                        .containerURL(forSecurityApplicationGroupIdentifier: "group.de.godsapp.ntfy")?
                        .appendingPathComponent("badge_count.txt") {
                        let current = (try? String(contentsOf: url, encoding: .utf8))
                            .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? 0
                        let newCount = max(0, current - 1)
                        try? String(newCount).write(to: url, atomically: true, encoding: .utf8)
                        await NotificationService.shared.setBadgeCount(newCount)
                    }
                    // 2. Notification entfernen
                    NotificationService.shared.removeNotification(withIdentifier: messageId)
                    // 3. SwiftData-Update delegieren
                    NotificationCenter.default.post(
                        name: .markMessageRead,
                        object: nil,
                        userInfo: ["messageId": messageId]
                    )
                }
            }

        case "REPLY":
            if let textResponse = response as? UNTextInputNotificationResponse,
               let topicName = userInfo["topic"] as? String {
                let replyText = textResponse.userText
                Task { @MainActor in
                    let serverURL = AppSettings.defaultServerURL
                    let token = KeychainManager.shared.loadToken(serverURL: serverURL)
                    let credentials = KeychainManager.shared.loadCredentials(serverURL: serverURL)
                    try? await NtfyService.shared.publish(
                        serverURL: serverURL,
                        topic: topicName,
                        message: replyText,
                        username: credentials?.username,
                        password: credentials?.password,
                        token: token
                    )
                }
            }

        case "OPEN_URL":
            // URL aus userInfo["url"] lesen (ntfy action-spezifisches Feld)
            // Fallback auf userInfo["click"] falls kein "url"-Key vorhanden
            let urlString = (userInfo["url"] as? String) ?? (userInfo["click"] as? String)
            if let urlString = urlString, let url = URL(string: urlString) {
                AppLog.app.info("🔗 OPEN_URL action: \(urlString, privacy: .private)")
                Task { @MainActor in
                    UIApplication.shared.open(url)
                }
            }

        default:
            // Normal tap (UNNotificationDefaultActionIdentifier) — open app and navigate
            // Handle click URL if present (ntfy v2.16+)
            if let clickURLString = userInfo["click"] as? String,
               let clickURL = URL(string: clickURLString) {
                AppLog.app.info("🔗 Opening click URL: \(clickURLString, privacy: .private)")
                Task { @MainActor in
                    UIApplication.shared.open(clickURL)
                }
            }

            // Navigate to topic if available
            if let topic = userInfo["topic"] as? String {
                Task { @MainActor in
                    NotificationCenter.default.post(
                        name: .navigateToTopic,
                        object: nil,
                        userInfo: ["topic": topic]
                    )
                }
            }
        }

        completionHandler()
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
