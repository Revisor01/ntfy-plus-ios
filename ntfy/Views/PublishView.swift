import SwiftUI
import SwiftData

struct PublishView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(NtfyService.self) private var ntfyService

    @Query private var topics: [Topic]

    let selectedTopic: Topic?

    @State private var topic: Topic?
    @State private var customTopicName = ""
    @State private var useCustomTopic = false

    @State private var message = ""
    @State private var title = ""
    @State private var priority: Priority = .default
    @State private var tags = ""
    @State private var clickURL = ""
    @State private var iconURL = ""
    @State private var attachURL = ""
    @State private var delay = ""
    @State private var email = ""
    @State private var useMarkdown = false

    @State private var showAdvanced = false
    @State private var isLoading = false
    @State private var error: String?
    @State private var showingSuccess = false

    /// Limits laut ntfy-Server (Header-Groessen)
    private static let maxTitleBytes = 1024
    private static let maxTagsBytes = 512

    private var trimmedTitle: String {
        title.trimmed()
    }

    private var parsedTags: [String] {
        tags.split(separator: ",")
            .map { String($0).trimmed() }
            .filter { !$0.isEmpty }
    }

    private var customTopicError: String? {
        guard useCustomTopic else { return nil }
        let name = customTopicName.trimmed()
        guard !name.isEmpty else { return nil }
        return name.isValidNtfyTopicName ? nil : "Nur Buchstaben (A–Z, a–z), Ziffern, „-“ und „_“ erlaubt, maximal 64 Zeichen."
    }

    private var titleError: String? {
        trimmedTitle.utf8.count > Self.maxTitleBytes ? "Der Titel ist zu lang (max. \(Self.maxTitleBytes) Bytes)." : nil
    }

    private var tagsError: String? {
        parsedTags.joined(separator: ",").utf8.count > Self.maxTagsBytes ? "Die Tags sind zu lang (max. \(Self.maxTagsBytes) Bytes)." : nil
    }

    private var hasValidTarget: Bool {
        if useCustomTopic {
            // Bei "Anderes Topic" zaehlt nur der eingegebene Name, nicht die Picker-Auswahl
            return customTopicName.trimmed().isValidNtfyTopicName
        }
        return topic != nil || topics.first != nil
    }

    private var isValid: Bool {
        !message.trimmed().isEmpty &&
        hasValidTarget &&
        titleError == nil &&
        tagsError == nil
    }

    var body: some View {
        NavigationStack {
            Form {
                // Topic selection
                Section {
                    if !topics.isEmpty && !useCustomTopic {
                        Picker("Topic", selection: $topic) {
                            ForEach(topics) { t in
                                Text(t.name).tag(t as Topic?)
                            }
                        }
                    }

                    Toggle("Anderes Topic", isOn: $useCustomTopic)

                    if useCustomTopic {
                        TextField("Topic-Name", text: $customTopicName)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                } header: {
                    Text("Ziel")
                } footer: {
                    if let customTopicError {
                        Text(customTopicError)
                            .foregroundStyle(.red)
                    }
                }

                // Message
                Section {
                    TextField("Titel (optional)", text: $title)

                    TextEditor(text: $message)
                        .frame(minHeight: 100)
                } header: {
                    Text("Nachricht")
                } footer: {
                    if let titleError {
                        Text(titleError)
                            .foregroundStyle(.red)
                    }
                }

                // Priority
                Section {
                    Picker("Priorität", selection: $priority) {
                        ForEach(Priority.allCases, id: \.self) { p in
                            HStack {
                                Image(systemName: p.icon)
                                Text(p.name)
                            }
                            .tag(p)
                        }
                    }
                } header: {
                    Text("Priorität")
                }

                // Advanced options
                Section {
                    DisclosureGroup("Erweiterte Optionen", isExpanded: $showAdvanced) {
                        TextField("Tags (kommagetrennt)", text: $tags)
                            .textInputAutocapitalization(.never)

                        if let tagsError {
                            Text(tagsError)
                                .font(AppFonts.caption)
                                .foregroundStyle(.red)
                        }

                        TextField("Klick-URL", text: $clickURL)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)

                        TextField("Icon-URL", text: $iconURL)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)

                        TextField("Anhang-URL", text: $attachURL)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)

                        TextField("Verzögerung (z.B. 30min, 9am)", text: $delay)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        TextField("E-Mail-Weiterleitung", text: $email)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()

                        Toggle("Markdown-Formatierung", isOn: $useMarkdown)
                    }
                }

                // Error message
                if let error = error {
                    Section {
                        Label(error, systemImage: AppIcons.error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Nachricht senden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        publish()
                    } label: {
                        if isLoading {
                            ProgressView()
                        } else {
                            Text("Senden")
                        }
                    }
                    .disabled(!isValid || isLoading)
                }
            }
            .alert("Gesendet", isPresented: $showingSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Die Nachricht wurde erfolgreich gesendet.")
            }
            .onAppear {
                topic = selectedTopic ?? topics.first
                if let t = topic, t.defaultPriority != 0 {
                    priority = Priority(rawValue: t.defaultPriority) ?? .default
                }
            }
            .onChange(of: topic) { _, newTopic in
                if let t = newTopic, t.defaultPriority != 0 {
                    priority = Priority(rawValue: t.defaultPriority) ?? .default
                }
            }
        }
    }

    private func publish() {
        guard isValid else { return }
        isLoading = true
        error = nil

        let targetTopic: Topic?
        let topicName: String
        let serverURL: String

        if useCustomTopic {
            targetTopic = nil
            topicName = customTopicName.trimmed()
            serverURL = AppSettings.defaultServerURL
        } else {
            targetTopic = topic ?? topics.first
            topicName = targetTopic?.name ?? ""
            serverURL = targetTopic?.serverURL ?? AppSettings.defaultServerURL
        }

        let token = KeychainManager.shared.loadToken(serverURL: serverURL)
        let credentials = KeychainManager.shared.loadCredentials(serverURL: serverURL)

        let tagList = parsedTags
        let publishTags: [String]? = tagList.isEmpty ? nil : tagList
        // Titel vor der Leer-Pruefung trimmen (sonst wird " " als Titel gesendet)
        let publishTitle: String? = trimmedTitle.isEmpty ? nil : trimmedTitle

        Task {
            do {
                try await ntfyService.publish(
                    serverURL: serverURL,
                    topic: topicName,
                    message: message.trimmed(),
                    title: publishTitle,
                    priority: priority,
                    tags: publishTags,
                    click: clickURL.trimmed().isEmpty ? nil : clickURL.trimmed(),
                    attach: attachURL.trimmed().isEmpty ? nil : attachURL.trimmed(),
                    icon: iconURL.trimmed().isEmpty ? nil : iconURL.trimmed(),
                    delay: delay.trimmed().isEmpty ? nil : delay.trimmed(),
                    email: email.trimmed().isEmpty ? nil : email.trimmed(),
                    markdown: useMarkdown,
                    username: credentials?.username,
                    password: credentials?.password,
                    token: token
                )

                await MainActor.run {
                    if AppSettings.hapticFeedback {
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
                    }
                    showingSuccess = true
                    isLoading = false
                }
            } catch let ntfyError as NtfyError {
                let description = ntfyError.errorDescription ?? ntfyError.localizedDescription
                await MainActor.run {
                    error = "Senden fehlgeschlagen: \(description)"
                    isLoading = false
                }
            } catch {
                let description = error.localizedDescription
                await MainActor.run {
                    self.error = "Senden fehlgeschlagen: \(description)"
                    isLoading = false
                }
            }
        }
    }
}

#Preview {
    PublishView(selectedTopic: nil)
        .modelContainer(for: [Topic.self], inMemory: true)
        .environment(NtfyService.shared)
}
