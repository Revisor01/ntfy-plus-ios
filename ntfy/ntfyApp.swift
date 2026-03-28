import SwiftUI
import SwiftData

@main
struct ntfyApp: App {
    // Register AppDelegate for Firebase
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var modelContainer: ModelContainer?

    @State private var ntfyService = NtfyService.shared
    @State private var iconManager = IconManager.shared
    @State private var containerInitError: Error?

    init() {
        do {
            let schema = Schema(NtfySchemaV1.models)
            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )
            modelContainer = try ModelContainer(
                for: schema,
                migrationPlan: NtfyMigrationPlan.self,
                configurations: [modelConfiguration]
            )
        } catch {
            modelContainer = nil
            containerInitError = error
        }

        // Register notification categories (delegate is now handled by AppDelegate)
        NotificationService.shared.registerNotificationCategories()
    }

    var body: some Scene {
        WindowGroup {
            if let container = modelContainer {
                ContentView()
                    .modelContainer(container)
                    .environment(ntfyService)
                    .environment(iconManager)
                    .preferredColorScheme(colorScheme)
                    .tint(Color(hex: AppSettings.accentColorHex))
            } else {
                ModelContainerErrorView(
                    error: containerInitError,
                    onRetry: { retryModelContainer() },
                    onDeleteData: { deleteAndRetryModelContainer() }
                )
            }
        }
    }

    private var colorScheme: ColorScheme? {
        switch AppSettings.appTheme {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    private mutating func retryModelContainer() {
        do {
            let schema = Schema(NtfySchemaV1.models)
            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )
            modelContainer = try ModelContainer(
                for: schema,
                migrationPlan: NtfyMigrationPlan.self,
                configurations: [modelConfiguration]
            )
            containerInitError = nil
        } catch {
            containerInitError = error
        }
    }

    private mutating func deleteAndRetryModelContainer() {
        // Delete SwiftData store files
        let url = URL.applicationSupportDirectory.appending(path: "default.store")
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(at: url.appending(path: suffix))
        }
        retryModelContainer()
    }
}

// MARK: - ModelContainerErrorView

private struct ModelContainerErrorView: View {
    let error: Error?
    let onRetry: () -> Void
    let onDeleteData: () -> Void
    @State private var showingDeleteConfirm = false

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.red)

            Text("Datenbankfehler")
                .font(AppFonts.headline)

            Text(error?.localizedDescription ?? "Unbekannter Fehler beim Laden der Datenbank.")
                .font(AppFonts.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.xl)

            VStack(spacing: AppSpacing.md) {
                Button("Erneut versuchen", action: onRetry)
                    .buttonStyle(.borderedProminent)

                Button("Daten löschen und neu starten", role: .destructive) {
                    showingDeleteConfirm = true
                }
                .buttonStyle(.bordered)
            }
        }
        .alert("Alle Daten löschen?", isPresented: $showingDeleteConfirm) {
            Button("Abbrechen", role: .cancel) {}
            Button("Löschen", role: .destructive, action: onDeleteData)
        } message: {
            Text("Alle gespeicherten Topics und Nachrichten werden unwiderruflich gelöscht.")
        }
    }
}
