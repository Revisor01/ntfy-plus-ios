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
                print("Notification permission granted")
            }
            if let error = error {
                print("Notification authorization error: \(error)")
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
        print("APNs Device Token: \(tokenString)")
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register for remote notifications: \(error)")
    }

    // MARK: - Handle Background Notifications (Silent Push)

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {

        // This is called when a silent push (poll request) arrives from ntfy
        print("Received remote notification: \(userInfo)")

        // Check if this is a poll request from ntfy
        if let pollId = userInfo["poll_id"] as? String {
            print("Poll request received with ID: \(pollId)")
            // The app will fetch the actual message from the server
            // This happens automatically through our SSE subscription
        }

        completionHandler(.newData)
    }

}

// MARK: - UNUserNotificationCenterDelegate
extension AppDelegate: @preconcurrency UNUserNotificationCenterDelegate {
    // Show notification when app is in foreground
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    // Handle notification tap
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo

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

        completionHandler()
    }
}

#if canImport(FirebaseMessaging)
extension AppDelegate: @preconcurrency MessagingDelegate {
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken = fcmToken else { return }
        print("Firebase FCM Token: \(fcmToken)")

        // Store token for later use
        UserDefaults.standard.set(fcmToken, forKey: "fcmToken")

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
