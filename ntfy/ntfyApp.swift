import SwiftUI
import SwiftData

@main
struct ntfyApp: App {
    let modelContainer: ModelContainer

    @State private var ntfyService = NtfyService.shared
    @State private var iconManager = IconManager.shared

    init() {
        do {
            let schema = Schema([
                Topic.self,
                StoredMessage.self,
                Server.self,
                DeletedMessage.self
            ])
            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )
            modelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
        }

        // Setup notification delegate
        UNUserNotificationCenter.current().delegate = NotificationService.shared

        // Register notification categories
        NotificationService.shared.registerNotificationCategories()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(ntfyService)
                .environment(iconManager)
                .preferredColorScheme(colorScheme)
                .tint(Color(hex: AppSettings.accentColorHex))
        }
        .modelContainer(modelContainer)
    }

    private var colorScheme: ColorScheme? {
        switch AppSettings.appTheme {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
