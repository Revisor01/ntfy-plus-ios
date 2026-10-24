import SwiftUI
import SwiftData

@main
struct ntfyApp: App {
    // Register AppDelegate for Firebase
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @State private var modelContainer: ModelContainer?

    @State private var ntfyService = NtfyService.shared
    @State private var iconManager = IconManager.shared
    @State private var containerInitError: Error?
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Register notification categories (delegate is now handled by AppDelegate)
        NotificationService.shared.registerNotificationCategories()
    }

    var body: some Scene {
        WindowGroup {
            Group {
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
            .onAppear {
                if modelContainer == nil && containerInitError == nil {
                    retryModelContainer()
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                // Von der NotificationServiceExtension abgelegte Push-Nachrichten uebernehmen
                if newPhase == .active, let container = modelContainer {
                    PendingMessageImporter.importPendingMessages(context: container.mainContext)
                }
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

    private func retryModelContainer() {
        do {
            let container = try SharedModel.makeContainer()
            modelContainer = container
            containerInitError = nil
            PendingMessageImporter.importPendingMessages(context: container.mainContext)
        } catch {
            modelContainer = nil
            containerInitError = error
        }
    }

    private func deleteAndRetryModelContainer() {
        // Alten Container verwerfen, bevor die Store-Dateien geloescht werden
        modelContainer = nil
        SharedModel.container = nil
        // Delete SwiftData store files (base store + WAL/SHM sibling files)
        let directory = URL.applicationSupportDirectory
        for suffix in ["", "-shm", "-wal"] {
            let fileURL = directory.appendingPathComponent("default.store" + suffix)
            try? FileManager.default.removeItem(at: fileURL)
        }
        retryModelContainer()
    }
}

// MARK: - SharedModel

/// Einziger ModelContainer der App. Wird von ntfyApp (UI) und AppDelegate
/// (Notification-Actions, auch wenn die UI nicht geladen ist) gemeinsam genutzt,
/// damit nie zwei Container parallel auf denselben Store schreiben.
@MainActor
enum SharedModel {
    static var container: ModelContainer?

    /// Liefert den bestehenden Container oder legt ihn an.
    static func makeContainer() throws -> ModelContainer {
        if let existing = container {
            return existing
        }
        let schema = Schema(NtfySchema.models)
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        let newContainer = try ModelContainer(
            for: schema,
            configurations: [modelConfiguration]
        )
        container = newContainer
        return newContainer
    }
}

// MARK: - PendingMessageImporter

/// Format der von der NotificationServiceExtension geschriebenen Dateien
/// (`pending-messages/<id>.json` im App-Group-Container).
private struct PendingMessageEnvelope: Decodable {
    let serverURL: String?
    let message: NtfyMessage
}

/// Uebernimmt Push-Nachrichten, die die NSE im App-Group-Container abgelegt hat,
/// in SwiftData (via NtfyService.storeMessages — Dedup/Upsert inklusive) und
/// loescht die Dateien danach.
@MainActor
enum PendingMessageImporter {
    static let appGroup = "group.de.godsapp.ntfy"
    static let directoryName = "pending-messages"

    static func importPendingMessages(context: ModelContext) {
        let fileManager = FileManager.default
        guard let directory = fileManager
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(directoryName, isDirectory: true),
              let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return
        }

        let pendingFiles = files.filter { $0.pathExtension == "json" && !$0.lastPathComponent.hasPrefix(".") }
        guard !pendingFiles.isEmpty else { return }

        let topics = (try? context.fetch(FetchDescriptor<Topic>())) ?? []
        var topicsById: [String: Topic] = [:]
        var messagesByTopicId: [String: [NtfyMessage]] = [:]
        let decoder = JSONDecoder()

        for file in pendingFiles {
            // Datei in jedem Fall entfernen — auch unlesbare oder nicht zuordenbare,
            // sonst sammeln sie sich dauerhaft an
            defer { try? fileManager.removeItem(at: file) }

            guard let data = try? Data(contentsOf: file),
                  let envelope = try? decoder.decode(PendingMessageEnvelope.self, from: data),
                  envelope.message.event == "message" else {
                continue
            }
            let message = envelope.message

            // Topic per (serverURL, name) suchen — ist der Server unbekannt
            // (Topic-Name auf mehreren Servern), nur per Name
            let matchedTopic: Topic?
            if let serverURL = envelope.serverURL {
                matchedTopic = topics.first(where: { $0.name == message.topic && $0.serverURL == serverURL })
            } else {
                matchedTopic = topics.first(where: { $0.name == message.topic })
            }
            guard let topic = matchedTopic else { continue }

            topicsById[topic.id] = topic
            messagesByTopicId[topic.id, default: []].append(message)
        }

        var importedCount = 0
        for (topicId, messages) in messagesByTopicId {
            guard let topic = topicsById[topicId] else { continue }
            NtfyService.shared.storeMessages(for: topic, messages: messages, context: context)
            importedCount += messages.count
        }

        if importedCount > 0 {
            AppLog.notifications.info("📥 \(importedCount, privacy: .public) Push-Nachricht(en) aus der NotificationServiceExtension uebernommen")
        }
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
