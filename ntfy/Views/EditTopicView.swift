import SwiftUI
import SwiftData

struct EditTopicView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var topic: Topic

    @State private var selectedColor: Color
    @State private var colorIsAutomatic: Bool
    @State private var customLetter: String
    @State private var selectedIcon: String?
    @State private var useMessageIcon: Bool
    @State private var selectedDefaultPriority: Int

    private let availableColors: [Color] = [
        .red, .orange, .yellow, .green, .mint, .teal,
        .cyan, .blue, .indigo, .purple, .pink, .brown
    ]

    /// VoiceOver-Namen passend zu `availableColors` (gleiche Reihenfolge)
    private let colorNames: [String] = [
        "Rot", "Orange", "Gelb", "Grün", "Mint", "Petrol",
        "Cyan", "Blau", "Indigo", "Lila", "Pink", "Braun"
    ]

    private let availableIcons: [String] = [
        "bell.fill", "envelope.fill", "message.fill", "bubble.left.fill",
        "server.rack", "desktopcomputer", "laptopcomputer", "iphone",
        "tv.fill", "film.fill", "play.rectangle.fill", "music.note",
        "house.fill", "building.2.fill", "car.fill", "airplane",
        "cloud.fill", "bolt.fill", "flame.fill", "drop.fill",
        "leaf.fill", "star.fill", "heart.fill", "flag.fill",
        "tag.fill", "bookmark.fill", "folder.fill", "doc.fill",
        "creditcard.fill", "cart.fill", "bag.fill", "gift.fill",
        "person.fill", "person.2.fill", "figure.run", "pawprint.fill",
        "camera.fill", "photo.fill", "globe", "map.fill",
        "lock.fill", "key.fill", "shield.fill", "eye.fill",
        "bell.badge.fill", "exclamationmark.triangle.fill", "checkmark.circle.fill", "xmark.circle.fill"
    ]

    init(topic: Topic) {
        self.topic = topic
        _selectedColor = State(initialValue: TopicAvatar.color(topicName: topic.name, colorHex: topic.colorHex))
        _colorIsAutomatic = State(initialValue: topic.colorHex == nil)
        _customLetter = State(initialValue: topic.customLetter ?? "")
        _selectedIcon = State(initialValue: topic.iconName)
        _useMessageIcon = State(initialValue: topic.shouldUseMessageIcon)
        _selectedDefaultPriority = State(initialValue: topic.defaultPriority)
    }

    var body: some View {
        NavigationStack {
            Form {
                formTopSections
                formBottomSections
            }
            .navigationTitle("Topic anpassen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        saveChanges()
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var formTopSections: some View {
        Section {
            HStack {
                Spacer()
                topicPreview
                Spacer()
            }
            .listRowBackground(Color.clear)
        }

        Section {
            Toggle("Icon aus Nachricht verwenden", isOn: $useMessageIcon)
        } footer: {
            Text("Wenn aktiviert, wird das Icon der letzten Nachricht (z.B. Sonarr-Logo) angezeigt, falls vorhanden.")
        }

        Section {
            TextField("Buchstabe (leer = automatisch)", text: $customLetter)
                .textInputAutocapitalization(.characters)
                .onChange(of: customLetter) { _, newValue in
                    if newValue.count > 2 {
                        customLetter = String(newValue.prefix(2))
                    }
                }
        } header: {
            Text("Buchstabe")
        } footer: {
            Text("Ohne eigenes Icon und Buchstaben zeigt die App ein zum Topic-Namen passendes Symbol, sonst den Anfangsbuchstaben.")
        }
    }

    @ViewBuilder
    private var formBottomSections: some View {
        colorSection
        iconSection
        notificationsSection
    }

    @ViewBuilder
    private var colorSection: some View {
        Section("Farbe") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                Button {
                    colorIsAutomatic = true
                    selectedColor = TopicAvatar.color(topicName: topic.name, colorHex: nil)
                } label: {
                    Circle()
                        .fill(TopicAvatar.color(topicName: topic.name, colorHex: nil).gradient)
                        .frame(width: 44, height: 44)
                        .overlay {
                            Image(systemName: colorIsAutomatic ? "checkmark" : "wand.and.stars")
                                .font(.headline)
                                .foregroundStyle(.white)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Automatisch")
                .accessibilityAddTraits(colorIsAutomatic ? .isSelected : [])

                ForEach(Array(availableColors.enumerated()), id: \.offset) { item in
                    let color = item.element
                    let isSelected = colorMatches(color)
                    Button {
                        selectedColor = color
                        colorIsAutomatic = false
                    } label: {
                        Circle()
                            .fill(color.gradient)
                            .frame(width: 44, height: 44)
                            .overlay {
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                }
                            }
                    }
                    // .plain: in Form-Zeilen sonst loest ein Tap alle Buttons der Zeile aus
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.offset < colorNames.count ? colorNames[item.offset] : "Farbe")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var iconSection: some View {
        Section("Icon") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                Button {
                    selectedIcon = nil
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.2))
                            .frame(width: 44, height: 44)

                        Image(systemName: "wand.and.stars")
                            .foregroundStyle(.secondary)
                    }
                    .overlay {
                        if selectedIcon == nil {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selectedColor, lineWidth: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Automatisch")
                .accessibilityAddTraits(selectedIcon == nil ? .isSelected : [])

                ForEach(availableIcons, id: \.self) { icon in
                    Button {
                        selectedIcon = icon
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedColor.gradient)
                                .frame(width: 44, height: 44)

                            Image(systemName: icon)
                                .foregroundStyle(.white)
                        }
                        .overlay {
                            if selectedIcon == icon {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(.white, lineWidth: 2)
                            }
                        }
                    }
                    // .plain: in Form-Zeilen sonst loest ein Tap alle Buttons der Zeile aus
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedIcon == icon ? .isSelected : [])
                }
            }
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var notificationsSection: some View {
        Section {
            Picker("Standard-Priorität", selection: $selectedDefaultPriority) {
                ForEach(Priority.allCases, id: \.rawValue) { priority in
                    Label(priority.name, systemImage: priority.icon)
                        .tag(priority.rawValue)
                }
            }
        } header: {
            Text("Benachrichtigungen")
        } footer: {
            Text("Standard-Priorität wird für neue Nachrichten dieses Topics vorbelegt. Der Benachrichtigungston richtet sich nach der Priorität der jeweiligen Nachricht (Standard bzw. kritisch/laut bei hoher/dringender Priorität).")
                .font(.caption)
        }
    }

    @ViewBuilder
    private var topicPreview: some View {
        VStack(spacing: 8) {
            TopicAvatar(
                topicName: topic.name,
                iconName: selectedIcon,
                customLetter: customLetter,
                colorHex: colorIsAutomatic ? nil : selectedColor.toHex(),
                size: 80
            )

            Text(topic.name)
                .font(.headline)
        }
        .padding()
    }

    private func colorMatches(_ color: Color) -> Bool {
        guard !colorIsAutomatic else { return false }
        let colorHex = color.toHex()
        let selectedHex = selectedColor.toHex()
        return colorHex == selectedHex
    }

    private func saveChanges() {
        topic.colorHex = colorIsAutomatic ? nil : selectedColor.toHex()
        topic.customLetter = customLetter.isEmpty ? nil : customLetter
        topic.iconName = selectedIcon
        topic.useMessageIcon = useMessageIcon
        topic.defaultPriority = selectedDefaultPriority
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Topic.self, configurations: config)
    let topic = Topic(name: "test-topic", serverURL: "https://push.godsapp.de")
    container.mainContext.insert(topic)

    return EditTopicView(topic: topic)
        .modelContainer(container)
}
