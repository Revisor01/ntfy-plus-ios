import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var servers: [Server]
    @Query private var topics: [Topic]
    @Query private var messages: [StoredMessage]

    @State private var defaultServerURL = AppSettings.defaultServerURL
    @State private var selectedTheme = AppSettings.appTheme
    @State private var hapticFeedback = AppSettings.hapticFeedback
    @State private var notificationsEnabled = AppSettings.notificationsEnabled

    @State private var showingDeleteConfirmation = false
    @State private var showingAddServer = false
    @State private var showingServerEditor: Server?

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
                    .onDelete(perform: deleteServers)

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
                } header: {
                    Text("Darstellung")
                }

                // Notifications
                Section {
                    Toggle("Benachrichtigungen", isOn: $notificationsEnabled)
                        .onChange(of: notificationsEnabled) { _, newValue in
                            AppSettings.notificationsEnabled = newValue
                            if newValue {
                                Task {
                                    _ = await NotificationService.shared.requestAuthorization()
                                }
                            }
                        }

                    Button("Benachrichtigungseinstellungen öffnen") {
                        openNotificationSettings()
                    }
                } header: {
                    Text("Benachrichtigungen")
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
                        Text("\(messages.count)")
                            .foregroundStyle(.secondary)
                    }

                    Button("Cache leeren") {
                        IconManager.shared.clearCache()
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
                        Text("1.0.0")
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
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
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
        }
    }

    private func deleteServers(at offsets: IndexSet) {
        for index in offsets {
            let server = servers[index]
            try? KeychainManager.shared.deleteCredentials(serverURL: server.url)
            try? KeychainManager.shared.deleteToken(serverURL: server.url)
            modelContext.delete(server)
        }
    }

    private func deleteAllMessages() {
        for message in messages {
            modelContext.delete(message)
        }
        try? modelContext.save()

        Task {
            await NotificationService.shared.clearBadge()
        }
    }

    private func openNotificationSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
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

        let serverURL = url.trimmed().trimmingCharacters(in: CharacterSet(charactersIn: "/"))

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
                if let existingServer = server {
                    // Update existing
                    existingServer.name = name.trimmed()
                    existingServer.url = serverURL
                    existingServer.useAuth = useAuth

                    // Clear old credentials
                    try? KeychainManager.shared.deleteCredentials(serverURL: existingServer.url)
                    try? KeychainManager.shared.deleteToken(serverURL: existingServer.url)
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
                    // Make all other servers non-default
                    let descriptor = FetchDescriptor<Server>()
                    if let allServers = try? modelContext.fetch(descriptor) {
                        for s in allServers where s.id != server?.id {
                            s.isDefault = false
                        }
                    }
                    if let server = server {
                        server.isDefault = true
                    }
                    AppSettings.defaultServerURL = serverURL
                }

                try? modelContext.save()
                dismiss()
            }
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [Server.self, Topic.self, StoredMessage.self], inMemory: true)
}
