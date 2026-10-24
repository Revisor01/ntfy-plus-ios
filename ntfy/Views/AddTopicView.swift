import SwiftUI
import SwiftData

struct AddTopicView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(NtfyService.self) private var ntfyService

    @Query private var servers: [Server]
    @Query private var existingTopics: [Topic]

    @State private var topicName = ""
    @State private var selectedServer: Server?
    @State private var useCustomServer = false
    @State private var customServerURL = ""
    @State private var useAuth = true
    @State private var username = ""
    @State private var password = ""
    @State private var useToken = false
    @State private var token = ""

    @State private var selectedIcon: String? = nil
    @State private var selectedColor = Color.blue
    @State private var customLetter = ""
    @State private var useIcon = false

    @State private var isLoading = false
    @State private var error: String?
    @State private var showingIconPicker = false
    @State private var showingColorPicker = false

    private var defaultServer: Server? {
        servers.first { $0.isDefault }
    }

    /// Server-URL, unter der das Topic angelegt wuerde (nil = noch keine gueltige Auswahl)
    private var targetServerURL: String? {
        if useCustomServer {
            let trimmedURL = customServerURL.trimmed()
            guard trimmedURL.isValidURL else { return nil }
            return trimmedURL.normalizedServerURL(addProtocolIfMissing: false)
        }
        return selectedServer?.url
    }

    private var topicNameError: String? {
        let name = topicName.trimmed()
        guard !name.isEmpty else { return nil }
        if !name.isValidNtfyTopicName {
            return "Nur Buchstaben (A–Z, a–z), Ziffern, „-“ und „_“ erlaubt, maximal 64 Zeichen."
        }
        if isDuplicate {
            return "Dieses Topic ist auf diesem Server bereits abonniert."
        }
        return nil
    }

    private var customServerURLError: String? {
        guard useCustomServer else { return nil }
        let trimmedURL = customServerURL.trimmed()
        guard !trimmedURL.isEmpty else { return nil }
        return trimmedURL.isValidURL ? nil : "Ungültige URL — bitte mit http:// oder https:// angeben."
    }

    /// Gleiches Topic auf gleichem Server bereits abonniert?
    private var isDuplicate: Bool {
        guard let serverURL = targetServerURL else { return false }
        let name = topicName.trimmed()
        return existingTopics.contains { $0.serverURL == serverURL && $0.name == name }
    }

    private var isValid: Bool {
        let name = topicName.trimmed()
        // Bei "Eigener Server" muss die eingegebene URL gueltig sein —
        // ein vorher gewaehlter Server zaehlt dann nicht
        return name.isValidNtfyTopicName && targetServerURL != nil && !isDuplicate
    }

    var body: some View {
        NavigationStack {
            Form {
                // Topic name
                Section {
                    TextField("Topic-Name", text: $topicName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Topic")
                } footer: {
                    if let topicNameError {
                        Text(topicNameError)
                            .foregroundStyle(.red)
                    } else {
                        Text("Der Name des Topics, das du abonnieren möchtest.")
                    }
                }

                // Server selection
                Section {
                    if !servers.isEmpty && !useCustomServer {
                        Picker("Server", selection: $selectedServer) {
                            ForEach(servers) { server in
                                Text(server.name)
                                    .tag(server as Server?)
                            }
                        }
                    }

                    Toggle("Eigener Server", isOn: $useCustomServer)

                    if useCustomServer {
                        TextField("Server URL", text: $customServerURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                    }
                } header: {
                    Text("Server")
                } footer: {
                    if let customServerURLError {
                        Text(customServerURLError)
                            .foregroundStyle(.red)
                    }
                }

                // Authentication
                if useCustomServer || (selectedServer?.useAuth ?? false) {
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
                }

                // Appearance
                Section {
                    // Preview
                    HStack {
                        Spacer()
                        topicPreview
                        Spacer()
                    }
                    .listRowBackground(Color.clear)

                    // Toggle between letter and icon
                    Picker("Anzeige", selection: $useIcon) {
                        Text("Buchstabe").tag(false)
                        Text("Icon").tag(true)
                    }
                    .pickerStyle(.segmented)

                    if useIcon {
                        // Icon picker
                        Button {
                            showingIconPicker = true
                        } label: {
                            HStack {
                                Text("Icon")
                                Spacer()
                                Image(systemName: selectedIcon ?? "bell.fill")
                                    .font(.title2)
                                    .foregroundStyle(selectedColor)
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        // Letter input
                        HStack {
                            Text("Buchstabe")
                            Spacer()
                            TextField(String(topicName.prefix(1)).uppercased().isEmpty ? "A" : String(topicName.prefix(1)).uppercased(), text: $customLetter)
                                .multilineTextAlignment(.trailing)
                                .textInputAutocapitalization(.characters)
                                .frame(width: 60)
                                .onChange(of: customLetter) { _, newValue in
                                    if newValue.count > 2 {
                                        customLetter = String(newValue.prefix(2))
                                    }
                                }
                        }
                    }

                    // Color picker
                    Button {
                        showingColorPicker = true
                    } label: {
                        HStack {
                            Text("Farbe")
                            Spacer()
                            Circle()
                                .fill(selectedColor)
                                .frame(width: 24, height: 24)
                        }
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("Darstellung")
                } footer: {
                    Text("Du kannst einen Buchstaben (1-2 Zeichen) oder ein Icon wählen.")
                }

                // Error message
                if let error = error {
                    Section {
                        Label(error, systemImage: AppIcons.error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Topic abonnieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Abonnieren") {
                        subscribe()
                    }
                    .disabled(!isValid || isLoading)
                }
            }
            .sheet(isPresented: $showingIconPicker) {
                TopicIconPicker(selectedIcon: Binding(
                    get: { selectedIcon ?? "bell.fill" },
                    set: { selectedIcon = $0 }
                ))
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingColorPicker) {
                TopicColorPicker(selectedColor: $selectedColor)
                    .presentationDetents([.medium])
            }
            .onAppear {
                selectedServer = defaultServer
                if let server = defaultServer {
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

    @ViewBuilder
    private var topicPreview: some View {
        let displayLetter = customLetter.isEmpty ? String(topicName.prefix(1)).uppercased() : customLetter
        let letterToShow = displayLetter.isEmpty ? "?" : displayLetter

        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(selectedColor.gradient)
                .frame(width: 64, height: 64)

            if useIcon {
                Image(systemName: selectedIcon ?? "bell.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white)
            } else {
                Text(letterToShow)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }

    private func subscribe() {
        guard isValid, let serverURL = targetServerURL else { return }

        isLoading = true
        error = nil

        let topicNameTrimmed = topicName.trimmed()

        Task {
            do {
                // Test connection first
                let authUsername = useAuth && !useToken ? username : nil
                let authPassword = useAuth && !useToken ? password : nil
                let authToken = useAuth && useToken ? token : nil

                let messages = try await ntfyService.fetchMessages(
                    serverURL: serverURL,
                    topic: topicNameTrimmed,
                    since: "1h",
                    username: authUsername,
                    password: authPassword,
                    token: authToken
                )

                // Doppelt-Check direkt vor dem Anlegen (Eingabe koennte sich geaendert haben)
                let duplicatePredicate = #Predicate<Topic> { existing in
                    existing.serverURL == serverURL && existing.name == topicNameTrimmed
                }
                let duplicateCount = (try? modelContext.fetchCount(FetchDescriptor<Topic>(predicate: duplicatePredicate))) ?? 0
                if duplicateCount > 0 {
                    self.error = "Dieses Topic ist auf diesem Server bereits abonniert."
                    isLoading = false
                    return
                }

                // Success - create topic
                let topic = Topic(
                    name: topicNameTrimmed,
                    serverURL: serverURL,
                    useAuth: useAuth,
                    iconName: useIcon ? (selectedIcon ?? "bell.fill") : nil,
                    colorHex: selectedColor.toHex()
                )
                topic.customLetter = useIcon ? nil : (customLetter.isEmpty ? nil : customLetter)

                modelContext.insert(topic)

                // Store messages ueber den zentralen Pfad — setzt unreadCount,
                // lastMessagePreview/-Priority/-IconURL und lastMessageAt korrekt
                ntfyService.storeMessages(for: topic, messages: messages, context: modelContext)

                // Save credentials if authentication is used (including the default server)
                if useAuth {
                    if useToken {
                        if !token.isEmpty {
                            try? KeychainManager.shared.saveToken(serverURL: serverURL, token: token)
                        }
                    } else if !username.isEmpty {
                        try? KeychainManager.shared.saveCredentials(
                            serverURL: serverURL,
                            username: username,
                            password: password
                        )
                    }
                }

                try? modelContext.save()
                ntfyService.writeWidgetData(context: modelContext)

                // Subscribe to Firebase topic for push notifications
                FirebaseService.shared.subscribeToTopic(serverURL: serverURL, topic: topicNameTrimmed)

                await MainActor.run {
                    dismiss()
                }
            } catch let ntfyError as NtfyError {
                await MainActor.run {
                    error = ntfyError.localizedDescription
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}

#Preview {
    AddTopicView()
        .modelContainer(for: [Topic.self, Server.self], inMemory: true)
        .environment(NtfyService.shared)
}
