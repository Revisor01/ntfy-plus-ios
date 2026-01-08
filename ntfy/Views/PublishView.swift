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

    @State private var showAdvanced = false
    @State private var isLoading = false
    @State private var error: String?
    @State private var showingSuccess = false

    private var isValid: Bool {
        !message.trimmed().isEmpty &&
        (topic != nil || (!useCustomTopic && topics.first != nil) || (useCustomTopic && !customTopicName.trimmed().isEmpty))
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
                }

                // Message
                Section {
                    TextField("Titel (optional)", text: $title)

                    TextEditor(text: $message)
                        .frame(minHeight: 100)
                } header: {
                    Text("Nachricht")
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

                        TextField("Klick-URL", text: $clickURL)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)

                        TextField("Icon-URL", text: $iconURL)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
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
            }
        }
    }

    private func publish() {
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

        let parsedTags: [String]? = tags.isEmpty ? nil : tags.split(separator: ",").map { String($0).trimmed() }

        Task {
            do {
                try await ntfyService.publish(
                    serverURL: serverURL,
                    topic: topicName,
                    message: message.trimmed(),
                    title: title.isEmpty ? nil : title.trimmed(),
                    priority: priority,
                    tags: parsedTags,
                    click: clickURL.isEmpty ? nil : clickURL.trimmed(),
                    attach: nil,
                    icon: iconURL.isEmpty ? nil : iconURL.trimmed(),
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
    PublishView(selectedTopic: nil)
        .modelContainer(for: [Topic.self], inMemory: true)
        .environment(NtfyService.shared)
}
