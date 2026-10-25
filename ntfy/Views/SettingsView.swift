import SwiftUI
import SwiftData
import LocalAuthentication
import UserNotifications

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var servers: [Server]
    @Query private var topics: [Topic]

    @State private var defaultServerURL = AppSettings.defaultServerURL
    @State private var selectedTheme = AppSettings.appTheme
    @State private var hapticFeedback = AppSettings.hapticFeedback
    @State private var biometricLockEnabled = AppSettings.biometricLockEnabled
    /// Tatsaechlicher Berechtigungsstatus aus UNUserNotificationCenter
    /// (wird beim Anzeigen und bei Rueckkehr in die App aktualisiert)
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    @State private var retentionDays = AppSettings.messageRetentionDays
    @State private var showingDeleteConfirmation = false
    @State private var showingAddServer = false
    @State private var showingServerEditor: Server?
    @State private var cacheSize: Int = 0
    /// Nachrichtenanzahl per fetchCount statt @Query (laedt sonst alle Nachrichten in den Speicher)
    @State private var messageCount: Int = 0
    @State private var serverToDelete: ServerDeletionInfo?
    @State private var showingDeleteServerConfirmation = false
    @State private var showingLockUnavailable = false
    @State private var lockUnavailableMessage = ""

    private var formattedCacheSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(cacheSize), countStyle: .file)
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                // Server section
                Section {
                    ForEach(servers) { server in
                        Button {
                            showingServerEditor = server
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(server.name)
                                        .foregroundStyle(.primary)
                                    Text(server.url)
                                        .font(AppFonts.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if server.isDefault {
                                    Text("Standard")
                                        .font(AppFonts.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.secondary.opacity(0.2))
                                        .clipShape(Capsule())
                                }

                                Image(systemName: AppIcons.forward)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: confirmDeleteServers)

                    Button {
                        showingAddServer = true
                    } label: {
                        Label("Server hinzufügen", systemImage: AppIcons.add)
                    }
                } header: {
                    Text("Server")
                }

                // Appearance
                Section {
                    Picker("Design", selection: $selectedTheme) {
                        ForEach(AppTheme.allCases, id: \.self) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }
                    .onChange(of: selectedTheme) { _, newValue in
                        AppSettings.appTheme = newValue
                    }

                    Toggle("Haptisches Feedback", isOn: $hapticFeedback)
                        .onChange(of: hapticFeedback) { _, newValue in
                            AppSettings.hapticFeedback = newValue
                        }

                    Toggle(DeviceAuth.lockToggleTitle(), isOn: $biometricLockEnabled)
                        .onChange(of: biometricLockEnabled) { _, newValue in
                            if newValue {
                                // Ohne Geraetecode gibt es keinen Entsperr-Weg — sonst Aussperrung
                                let context = LAContext()
                                var authError: NSError?
                                guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
                                    lockUnavailableMessage = DeviceAuth.unavailableMessage(for: authError)
                                    showingLockUnavailable = true
                                    biometricLockEnabled = false
                                    AppSettings.biometricLockEnabled = false
                                    return
                                }
                            }
                            AppSettings.biometricLockEnabled = newValue
                        }
                } header: {
                    Text("Darstellung")
                }

                // Notifications
                Section {
                    Toggle("Benachrichtigungen", isOn: Binding(
                        get: { notificationsAuthorized },
                        set: { setNotificationsEnabled($0) }
                    ))

                    Button("Benachrichtigungseinstellungen öffnen") {
                        openNotificationSettings()
                    }
                } header: {
                    Text("Benachrichtigungen")
                } footer: {
                    if notificationStatus == .denied {
                        Text("Mitteilungen sind in den iOS-Einstellungen deaktiviert. Aktiviere sie dort, um Push-Benachrichtigungen zu erhalten.")
                    } else if notificationsAuthorized {
                        Text("Mitteilungen lassen sich in den iOS-Einstellungen deaktivieren.")
                    }
                }

                // Data management
                Section {
                    HStack {
                        Text("Topics")
                        Spacer()
                        Text("\(topics.count)")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Nachrichten")
                        Spacer()
                        Text("\(messageCount)")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Bild-Cache")
                        Spacer()
                        Text(formattedCacheSize)
                            .foregroundStyle(.secondary)
                    }

                    Button("Cache leeren") {
                        IconManager.shared.clearCache()
                        AttachmentImageCache.shared.clearDiskCache()
                        cacheSize = AttachmentImageCache.shared.diskCacheSize()
                    }
                    .disabled(cacheSize == 0)

                    Picker("Nachrichten aufbewahren", selection: $retentionDays) {
                        Text("7 Tage").tag(7)
                        Text("14 Tage").tag(14)
                        Text("30 Tage").tag(30)
                        Text("60 Tage").tag(60)
                        Text("90 Tage").tag(90)
                        Text("Unbegrenzt").tag(-1)
                    }
                    .onChange(of: retentionDays) { _, newValue in
                        AppSettings.messageRetentionDays = newValue
                    }

                    Button("Alle Nachrichten löschen", role: .destructive) {
                        showingDeleteConfirmation = true
                    }
                } header: {
                    Text("Daten")
                }

                // About
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersion)
                            .foregroundStyle(.secondary)
                    }

                    Link(destination: URL(string: "https://ntfy.sh/docs/")!) {
                        HStack {
                            Text("ntfy Dokumentation")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Link(destination: URL(string: "https://github.com/binwiederhier/ntfy")!) {
                        HStack {
                            Text("GitHub")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Info")
                }

                // Footer
                Section {
                } footer: {
                    HStack {
                        Spacer()
                        HStack(spacing: 4) {
                            Text("Gemacht mit")
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.red)
                            Text("in Hennstedt")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                cacheSize = AttachmentImageCache.shared.diskCacheSize()
                refreshMessageCount()
                await refreshNotificationStatus()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                // Rueckkehr aus den iOS-Einstellungen bzw. nach dem Berechtigungsdialog
                Task {
                    await refreshNotificationStatus()
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingAddServer) {
                ServerEditorView(server: nil)
            }
            .sheet(item: $showingServerEditor) { server in
                ServerEditorView(server: server)
            }
            .alert("Alle Nachrichten löschen?", isPresented: $showingDeleteConfirmation) {
                Button("Abbrechen", role: .cancel) {}
                Button("Löschen", role: .destructive) {
                    deleteAllMessages()
                }
            } message: {
                Text("Diese Aktion kann nicht rückgängig gemacht werden.")
            }
            .alert("Server entfernen?", isPresented: $showingDeleteServerConfirmation, presenting: serverToDelete) { info in
                Button("Abbrechen", role: .cancel) {
                    serverToDelete = nil
                }
                Button("Entfernen", role: .destructive) {
                    deleteServer(id: info.id)
                    serverToDelete = nil
                }
            } message: { info in
                Text(info.message)
            }
            .alert("Sperre nicht verfügbar", isPresented: $showingLockUnavailable) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(lockUnavailableMessage)
            }
        }
    }

    private func refreshMessageCount() {
        messageCount = (try? modelContext.fetchCount(FetchDescriptor<StoredMessage>())) ?? 0
    }

    private func confirmDeleteServers(at offsets: IndexSet) {
        // Swipe-to-Delete loescht nicht sofort — erst nach Bestaetigung
        guard let index = offsets.first, index < servers.count else { return }
        let server = servers[index]
        let serverURL = server.url
        let topicCount = topics.filter { $0.serverURL == serverURL }.count
        var text = "Der Server \"\(server.name)\" und seine Zugangsdaten werden entfernt."
        if topicCount == 1 {
            text += " Das zugehörige Topic und seine Nachrichten werden ebenfalls entfernt."
        } else if topicCount > 1 {
            text += " Die \(topicCount) zugehörigen Topics und ihre Nachrichten werden ebenfalls entfernt."
        }
        // Nur einfache Werte im Alert halten — nicht das Model, das gleich geloescht wird
        serverToDelete = ServerDeletionInfo(id: server.id, message: text)
        showingDeleteServerConfirmation = true
    }

    private func deleteServer(id serverId: String) {
        let idPredicate = #Predicate<Server> { $0.id == serverId }
        guard let server = (try? modelContext.fetch(FetchDescriptor<Server>(predicate: idPredicate)))?.first else { return }

        // Werte kopieren, bevor das Model geloescht wird
        let serverURL = server.url
        let wasDefault = server.isDefault || AppSettings.defaultServerURL == serverURL

        // Topics dieses Servers mit demselben Pfad wie "Topic entfernen" aufraeumen
        // (die Zugangsdaten werden gleich geloescht — die Topics waeren sonst verwaist)
        let topicPredicate = #Predicate<Topic> { $0.serverURL == serverURL }
        let serverTopics = (try? modelContext.fetch(FetchDescriptor<Topic>(predicate: topicPredicate))) ?? []
        for topic in serverTopics {
            TopicActions.remove(topic, context: modelContext, ntfyService: NtfyService.shared)
        }

        try? KeychainManager.shared.deleteCredentials(serverURL: serverURL)
        try? KeychainManager.shared.deleteToken(serverURL: serverURL)
        modelContext.delete(server)

        // War es der Standard-Server, einen anderen Server zum Standard machen
        if wasDefault {
            let remainingPredicate = #Predicate<Server> { $0.id != serverId }
            let remainingDescriptor = FetchDescriptor<Server>(
                predicate: remainingPredicate,
                sortBy: [SortDescriptor(\.addedAt)]
            )
            let remaining = (try? modelContext.fetch(remainingDescriptor)) ?? []
            if let newDefault = remaining.first(where: { $0.isDefault }) ?? remaining.first {
                for other in remaining {
                    other.isDefault = other.id == newDefault.id
                }
                AppSettings.defaultServerURL = newDefault.url
            }
        }

        try? modelContext.save()
        refreshMessageCount()
    }

    private func deleteAllMessages() {
        let allMessages = (try? modelContext.fetch(FetchDescriptor<StoredMessage>())) ?? []
        for message in allMessages {
            modelContext.delete(message)
        }

        // Denormalisierte Topic-Felder zuruecksetzen
        for topic in topics {
            topic.unreadCount = 0
            topic.lastMessagePreview = nil
            topic.lastMessagePriority = 3
            topic.lastMessageIconURL = nil
        }
        try? modelContext.save()

        NotificationService.shared.removeAllNotifications()
        NtfyService.shared.writeWidgetData(context: modelContext)
        messageCount = 0

        Task {
            await NotificationService.shared.clearBadge()
        }
    }

    private func openNotificationSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Mitteilungs-Berechtigung

    private var notificationsAuthorized: Bool {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    private func refreshNotificationStatus() async {
        let status = await NotificationService.shared.checkAuthorizationStatus()
        notificationStatus = status
        // Veraltetes Flag nur noch spiegeln (wird nirgends mehr ausgewertet)
        AppSettings.notificationsEnabled = notificationsAuthorized
    }

    /// Einschalten fragt die Berechtigung an (bzw. oeffnet bei Ablehnung die
    /// iOS-Einstellungen). Entziehen laesst sich die Berechtigung nur dort.
    private func setNotificationsEnabled(_ enabled: Bool) {
        if enabled {
            switch notificationStatus {
            case .notDetermined:
                Task {
                    _ = await NotificationService.shared.requestAuthorization()
                    await refreshNotificationStatus()
                }
            case .authorized, .provisional, .ephemeral:
                break
            default:
                openNotificationSettings()
            }
        } else if notificationsAuthorized {
            openNotificationSettings()
        }
    }
}

/// Daten fuer den Bestaetigungsdialog "Server entfernen"
struct ServerDeletionInfo: Identifiable {
    let id: String
    let message: String
}

// MARK: - Server Editor

struct ServerEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let server: Server?

    @State private var name = ""
    @State private var url = ""
    @State private var useAuth = false
    @State private var username = ""
    @State private var password = ""
    @State private var useToken = false
    @State private var token = ""
    @State private var isDefault = false

    @State private var isLoading = false
    @State private var error: String?

    private var isEditing: Bool {
        server != nil
    }

    private var isValid: Bool {
        !name.trimmed().isEmpty && !url.trimmed().isEmpty && url.isValidURL
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)

                    TextField("URL", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    Toggle("Standard-Server", isOn: $isDefault)
                } header: {
                    Text("Server")
                }

                Section {
                    Toggle("Authentifizierung", isOn: $useAuth)

                    if useAuth {
                        Picker("Methode", selection: $useToken) {
                            Text("Benutzername/Passwort").tag(false)
                            Text("Token").tag(true)
                        }
                        .pickerStyle(.segmented)

                        if useToken {
                            SecureField("Token", text: $token)
                                .textInputAutocapitalization(.never)
                        } else {
                            TextField("Benutzername", text: $username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()

                            SecureField("Passwort", text: $password)
                        }
                    }
                } header: {
                    Text("Authentifizierung")
                }

                if let error = error {
                    Section {
                        Label(error, systemImage: AppIcons.error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(isEditing ? "Server bearbeiten" : "Server hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Speichern" : "Hinzufügen") {
                        save()
                    }
                    .disabled(!isValid || isLoading)
                }
            }
            .onAppear {
                if let server = server {
                    name = server.name
                    url = server.url
                    useAuth = server.useAuth
                    isDefault = server.isDefault

                    if let credentials = KeychainManager.shared.loadCredentials(serverURL: server.url) {
                        username = credentials.username
                        password = credentials.password
                        useToken = false
                    } else if let savedToken = KeychainManager.shared.loadToken(serverURL: server.url) {
                        token = savedToken
                        useToken = true
                    }
                }
            }
        }
    }

    private func save() {
        isLoading = true
        error = nil

        let serverURL = url.trimmed().normalizedServerURL(addProtocolIfMissing: false)

        Task {
            // Test connection
            do {
                let healthy = try await NtfyService.shared.checkServer(url: serverURL)
                if !healthy {
                    await MainActor.run {
                        error = "Server nicht erreichbar"
                        isLoading = false
                    }
                    return
                }
            } catch {
                await MainActor.run {
                    self.error = "Verbindung fehlgeschlagen: \(error.localizedDescription)"
                    isLoading = false
                }
                return
            }

            await MainActor.run {
                let targetServer: Server
                if let existingServer = server {
                    // Alte URL sichern, BEVOR sie ueberschrieben wird — die Keychain-
                    // Eintraege sind unter der alten URL abgelegt
                    let oldURL = existingServer.url

                    // Clear old credentials (unter der alten URL)
                    try? KeychainManager.shared.deleteCredentials(serverURL: oldURL)
                    try? KeychainManager.shared.deleteToken(serverURL: oldURL)

                    // Update existing
                    existingServer.name = name.trimmed()
                    existingServer.url = serverURL
                    existingServer.useAuth = useAuth
                    existingServer.username = useAuth && !useToken ? username : nil

                    if oldURL != serverURL {
                        // Topics des Servers auf die neue URL umziehen
                        let topicPredicate = #Predicate<Topic> { $0.serverURL == oldURL }
                        let serverTopics = (try? modelContext.fetch(FetchDescriptor<Topic>(predicate: topicPredicate))) ?? []
                        for topic in serverTopics {
                            let topicName = topic.name
                            topic.serverURL = serverURL
                            // Alte SSE-Verbindung beenden; FCM/Topic→Server-Map umziehen —
                            // zuerst neu eintragen, damit der Refcount bei gleichem Namen
                            // nicht auf 0 faellt und das FCM-Abo bestehen bleibt.
                            // Das neue SSE-Abo baut ContentView auf (serverConfigurationChanged).
                            NtfyService.shared.unsubscribe(serverURL: oldURL, topic: topicName)
                            FirebaseService.shared.subscribeToTopic(serverURL: serverURL, topic: topicName)
                            FirebaseService.shared.unsubscribeFromTopic(serverURL: oldURL, topic: topicName)
                        }
                        // DeletedMessage-Records ebenfalls umziehen, sonst kommen
                        // geloeschte Nachrichten beim naechsten Refresh zurueck
                        let deletedPredicate = #Predicate<DeletedMessage> { $0.serverURL == oldURL }
                        let deletedRecords = (try? modelContext.fetch(FetchDescriptor<DeletedMessage>(predicate: deletedPredicate))) ?? []
                        for record in deletedRecords {
                            record.serverURL = serverURL
                        }
                        if AppSettings.defaultServerURL == oldURL {
                            AppSettings.defaultServerURL = serverURL
                        }
                    }
                    targetServer = existingServer
                } else {
                    // Create new
                    let newServer = Server(
                        url: serverURL,
                        name: name.trimmed(),
                        useAuth: useAuth,
                        username: useAuth && !useToken ? username : nil,
                        isDefault: isDefault
                    )
                    modelContext.insert(newServer)
                    targetServer = newServer
                }

                // Save credentials
                if useAuth {
                    if useToken {
                        try? KeychainManager.shared.saveToken(serverURL: serverURL, token: token)
                    } else {
                        try? KeychainManager.shared.saveCredentials(
                            serverURL: serverURL,
                            username: username,
                            password: password
                        )
                    }
                }

                // Handle default server
                if isDefault {
                    // Make all other servers non-default — gegen die tatsaechliche
                    // Ziel-ID vergleichen (bei neuem Server ist `server` nil)
                    let targetId = targetServer.id
                    let descriptor = FetchDescriptor<Server>()
                    if let allServers = try? modelContext.fetch(descriptor) {
                        for s in allServers where s.id != targetId {
                            s.isDefault = false
                        }
                    }
                    targetServer.isDefault = true
                    AppSettings.defaultServerURL = serverURL
                }

                try? modelContext.save()

                if isEditing {
                    // SSE-Abos dieses Servers mit neuer URL bzw. neuen Zugangsdaten neu aufbauen
                    NotificationCenter.default.post(
                        name: .serverConfigurationChanged,
                        object: nil,
                        userInfo: ["serverURL": serverURL]
                    )
                }
                dismiss()
            }
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [Server.self, Topic.self, StoredMessage.self], inMemory: true)
}
