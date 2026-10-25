import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

/// Lokal ausgewaehlte Datei (Foto oder Datei aus "Dateien") fuer den Upload per PUT
private struct LocalAttachment {
    let data: Data
    let filename: String

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
    }
}

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

    // Zeitversetzte Zustellung per Datumsauswahl
    @State private var useScheduledDate = false
    @State private var scheduledDate = Date().addingTimeInterval(3600)

    // Datei-Anhang
    @State private var localAttachment: LocalAttachment?
    @State private var photoItem: PhotosPickerItem?
    @State private var showingFileImporter = false
    @State private var isLoadingAttachment = false
    @State private var attachmentError: String?

    @State private var showAdvanced = false
    @State private var isLoading = false
    @State private var error: String?
    @State private var showingSuccess = false
    @State private var successText = "Die Nachricht wurde erfolgreich gesendet."

    /// Limits laut ntfy-Server (Header-Groessen)
    private static let maxTitleBytes = 1024
    private static let maxTagsBytes = 512

    /// Standardlimits des ntfy-Servers fuer `delay` (message-delay-limit)
    private static let minScheduleInterval: TimeInterval = 10
    private static let maxScheduleInterval: TimeInterval = 3 * 24 * 3600

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

    /// Pruefung des gewaehlten Zeitpunkts (mind. 10 s in der Zukunft, max. 3 Tage)
    private var scheduleError: String? {
        guard useScheduledDate else { return nil }
        let interval = scheduledDate.timeIntervalSinceNow
        if interval < Self.minScheduleInterval {
            return "Der Zeitpunkt muss mindestens 10 Sekunden in der Zukunft liegen."
        }
        if interval > Self.maxScheduleInterval {
            return "Der Zeitpunkt darf höchstens 3 Tage in der Zukunft liegen (Standardlimit des ntfy-Servers)."
        }
        return nil
    }

    private var hasValidTarget: Bool {
        if useCustomTopic {
            // Bei "Anderes Topic" zaehlt nur der eingegebene Name, nicht die Picker-Auswahl
            return customTopicName.trimmed().isValidNtfyTopicName
        }
        return topic != nil || topics.first != nil
    }

    private var isValid: Bool {
        // Mit Anhang ist die Nachricht optional (ntfy setzt dann einen Standardtext)
        (!message.trimmed().isEmpty || localAttachment != nil) &&
        hasValidTarget &&
        titleError == nil &&
        tagsError == nil &&
        scheduleError == nil &&
        !isLoadingAttachment
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

                // Datei-Anhang
                attachmentSection

                // Zeitversetzte Zustellung
                scheduleSection

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
                            .disabled(localAttachment != nil)

                        if localAttachment != nil {
                            Text("Wird ignoriert, solange eine Datei angehängt ist.")
                                .font(AppFonts.caption)
                                .foregroundStyle(.secondary)
                        }

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
                Text(successText)
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
            .onChange(of: photoItem) { _, newItem in
                guard let newItem else { return }
                loadPhoto(newItem)
            }
            .onChange(of: useScheduledDate) { _, isOn in
                // Beim Einschalten einen gueltigen Zeitpunkt vorbelegen
                if isOn && scheduleError != nil {
                    scheduledDate = Date().addingTimeInterval(3600)
                }
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

    // MARK: - Anhang

    @ViewBuilder
    private var attachmentSection: some View {
        Section {
            if let attachment = localAttachment {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "paperclip")
                        .foregroundStyle(AppColors.primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(attachment.filename)
                            .lineLimit(1)
                        Text(attachment.formattedSize)
                            .font(AppFonts.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        removeAttachment()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Anhang entfernen")
                }
            }

            if isLoadingAttachment {
                HStack(spacing: AppSpacing.sm) {
                    ProgressView()
                    Text("Anhang wird geladen …")
                        .foregroundStyle(.secondary)
                }
            }

            PhotosPicker(
                selection: $photoItem,
                matching: .images,
                preferredItemEncoding: .compatible
            ) {
                Label("Foto auswählen", systemImage: "photo.on.rectangle")
            }
            .disabled(isLoadingAttachment)

            Button {
                showingFileImporter = true
            } label: {
                Label("Datei auswählen", systemImage: "doc")
            }
            .disabled(isLoadingAttachment)
        } header: {
            Text("Anhang")
        } footer: {
            if let attachmentError {
                Text(attachmentError)
                    .foregroundStyle(.red)
            } else {
                Text("Optional, max. \(Self.formattedUploadLimit). Der Server kann ein niedrigeres Limit haben; hochgeladene Anhänge laufen nach einiger Zeit ab (ntfy.sh: 3 Stunden).")
            }
        }
    }

    private static var formattedUploadLimit: String {
        ByteCountFormatter.string(fromByteCount: Int64(NtfyUploadLimits.maxAttachmentBytes), countStyle: .file)
    }

    private func removeAttachment() {
        localAttachment = nil
        photoItem = nil
        attachmentError = nil
    }

    /// Uebernimmt die Datei, sofern sie das Upload-Limit nicht ueberschreitet
    private func setAttachment(data: Data, filename: String) {
        guard data.count <= NtfyUploadLimits.maxAttachmentBytes else {
            let size = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
            attachmentError = "Die Datei ist zu groß (\(size), max. \(Self.formattedUploadLimit))."
            return
        }
        localAttachment = LocalAttachment(data: data, filename: filename)
        attachmentError = nil
    }

    private func loadPhoto(_ item: PhotosPickerItem) {
        isLoadingAttachment = true
        attachmentError = nil
        let contentType = item.supportedContentTypes.first

        Task {
            do {
                let data = try await item.loadTransferable(type: Data.self)
                await MainActor.run {
                    if let data {
                        let prepared = Self.preparePhoto(data: data, contentType: contentType)
                        setAttachment(data: prepared.data, filename: prepared.filename)
                    } else {
                        attachmentError = "Das Foto konnte nicht geladen werden."
                    }
                    isLoadingAttachment = false
                }
            } catch {
                let description = error.localizedDescription
                await MainActor.run {
                    attachmentError = "Das Foto konnte nicht geladen werden: \(description)"
                    isLoadingAttachment = false
                }
            }
        }
    }

    /// Dateiname aus Zeitstempel + Endung; HEIC/HEIF wird zu JPEG umgewandelt,
    /// da viele Empfaenger (Web-App, aeltere Android-Geraete) HEIC nicht anzeigen.
    private static func preparePhoto(data: Data, contentType: UTType?) -> (data: Data, filename: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let baseName = "foto-\(formatter.string(from: Date()))"

        if let contentType,
           contentType.conforms(to: .heic) || contentType.conforms(to: .heif),
           let image = UIImage(data: data),
           let jpeg = image.jpegData(compressionQuality: 0.85) {
            return (jpeg, "\(baseName).jpg")
        }

        let fileExtension = contentType?.preferredFilenameExtension ?? "jpg"
        return (data, "\(baseName).\(fileExtension)")
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        attachmentError = nil
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            // Dateien ausserhalb der Sandbox: Security-Scoped-Zugriff anfordern
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            // Groesse vor dem Einlesen pruefen — grosse Dateien nicht in den Speicher laden
            if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
               size > NtfyUploadLimits.maxAttachmentBytes {
                let formatted = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
                attachmentError = "Die Datei ist zu groß (\(formatted), max. \(Self.formattedUploadLimit))."
                return
            }

            do {
                let data = try Data(contentsOf: url)
                setAttachment(data: data, filename: url.lastPathComponent)
                // Foto-Auswahl zuruecksetzen, damit dasselbe Foto spaeter erneut waehlbar ist
                photoItem = nil
            } catch {
                AppLog.ui.error("❌ Anhang: Datei nicht lesbar: \(error.localizedDescription, privacy: .public)")
                attachmentError = "Die Datei konnte nicht gelesen werden: \(error.localizedDescription)"
            }

        case .failure(let error):
            AppLog.ui.error("❌ Anhang: Dateiauswahl fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            attachmentError = "Die Datei konnte nicht ausgewählt werden: \(error.localizedDescription)"
        }
    }

    // MARK: - Zeitversetzt senden

    @ViewBuilder
    private var scheduleSection: some View {
        Section {
            Toggle("Zeitpunkt wählen", isOn: $useScheduledDate)

            if useScheduledDate {
                DatePicker(
                    "Zeitpunkt",
                    selection: $scheduledDate,
                    in: Date()...Date().addingTimeInterval(Self.maxScheduleInterval),
                    displayedComponents: [.date, .hourAndMinute]
                )
            } else {
                TextField("Verzögerung (z.B. 30min, 9am)", text: $delay)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        } header: {
            Text("Zeitversetzt senden")
        } footer: {
            if let scheduleError {
                Text(scheduleError)
                    .foregroundStyle(.red)
            } else {
                Text("Optional. Frühestens 10 Sekunden, höchstens 3 Tage im Voraus (Standardlimit des ntfy-Servers).")
            }
        }
    }

    /// RFC-3339-Zeitstempel mit lokalem Offset (z.B. 2026-10-25T14:30:00+01:00)
    private static func rfc3339String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }

    // MARK: - Senden

    private func publish() {
        guard isValid else { return }

        // Zeitpunkt erneut pruefen — seit dem Rendern kann Zeit vergangen sein
        if let scheduleError {
            error = scheduleError
            return
        }

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
        let publishMessage = message.trimmed()
        let publishClick: String? = clickURL.trimmed().isEmpty ? nil : clickURL.trimmed()
        let publishIcon: String? = iconURL.trimmed().isEmpty ? nil : iconURL.trimmed()
        let publishAttach: String? = attachURL.trimmed().isEmpty ? nil : attachURL.trimmed()
        let publishEmail: String? = email.trimmed().isEmpty ? nil : email.trimmed()
        let publishMarkdown = useMarkdown
        let publishPriority = priority
        let attachment = localAttachment

        // Zeitversetzt: Datumsauswahl als RFC-3339-Zeitstempel, sonst Freitext (30min, 9am …).
        // Die Geraete-Zeitzone (IANA) erlaubt dem Server, Angaben wie "9am" korrekt aufzuloesen.
        let publishDelay: String?
        if useScheduledDate {
            publishDelay = Self.rfc3339String(from: scheduledDate)
        } else {
            let trimmedDelay = delay.trimmed()
            publishDelay = trimmedDelay.isEmpty ? nil : trimmedDelay
        }
        let publishTimezone: String? = publishDelay == nil ? nil : TimeZone.current.identifier
        let isScheduled = publishDelay != nil

        Task {
            do {
                if let attachment {
                    try await ntfyService.publishAttachment(
                        serverURL: serverURL,
                        topic: topicName,
                        data: attachment.data,
                        filename: attachment.filename,
                        message: publishMessage.isEmpty ? nil : publishMessage,
                        title: publishTitle,
                        priority: publishPriority,
                        tags: publishTags,
                        click: publishClick,
                        icon: publishIcon,
                        delay: publishDelay,
                        timezone: publishTimezone,
                        email: publishEmail,
                        markdown: publishMarkdown,
                        username: credentials?.username,
                        password: credentials?.password,
                        token: token
                    )
                } else {
                    try await ntfyService.publish(
                        serverURL: serverURL,
                        topic: topicName,
                        message: publishMessage,
                        title: publishTitle,
                        priority: publishPriority,
                        tags: publishTags,
                        click: publishClick,
                        attach: publishAttach,
                        icon: publishIcon,
                        delay: publishDelay,
                        timezone: publishTimezone,
                        email: publishEmail,
                        markdown: publishMarkdown,
                        username: credentials?.username,
                        password: credentials?.password,
                        token: token
                    )
                }

                await MainActor.run {
                    if AppSettings.hapticFeedback {
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
                    }
                    successText = isScheduled
                        ? "Die Nachricht wurde zur zeitversetzten Zustellung an den Server übergeben."
                        : "Die Nachricht wurde erfolgreich gesendet."
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
