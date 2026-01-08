import SwiftUI
import SwiftData

struct EditTopicView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var topic: Topic

    @State private var selectedColor: Color
    @State private var customLetter: String
    @State private var selectedIcon: String?
    @State private var useMessageIcon: Bool

    private let availableColors: [Color] = [
        .red, .orange, .yellow, .green, .mint, .teal,
        .cyan, .blue, .indigo, .purple, .pink, .brown
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
        _selectedColor = State(initialValue: topic.colorHex != nil ? Color(hex: topic.colorHex!) : .blue)
        _customLetter = State(initialValue: topic.customLetter ?? "")
        _selectedIcon = State(initialValue: topic.iconName)
        _useMessageIcon = State(initialValue: topic.shouldUseMessageIcon)
    }

    var body: some View {
        NavigationStack {
            Form {
                // Preview
                Section {
                    HStack {
                        Spacer()
                        topicPreview
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                // Message Icon Toggle
                Section {
                    Toggle("Icon aus Nachricht verwenden", isOn: $useMessageIcon)
                } footer: {
                    Text("Wenn aktiviert, wird das Icon der letzten Nachricht (z.B. Sonarr-Logo) angezeigt, falls vorhanden.")
                }

                // Custom Letter
                Section("Buchstabe") {
                    TextField("Buchstabe (leer = erster Buchstabe)", text: $customLetter)
                        .textInputAutocapitalization(.characters)
                        .onChange(of: customLetter) { _, newValue in
                            if newValue.count > 2 {
                                customLetter = String(newValue.prefix(2))
                            }
                        }
                }

                // Color Selection
                Section("Farbe") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(availableColors, id: \.self) { color in
                            Circle()
                                .fill(color.gradient)
                                .frame(width: 44, height: 44)
                                .overlay {
                                    if colorMatches(color) {
                                        Image(systemName: "checkmark")
                                            .font(.headline)
                                            .foregroundStyle(.white)
                                    }
                                }
                                .onTapGesture {
                                    selectedColor = color
                                    selectedIcon = nil
                                }
                        }
                    }
                    .padding(.vertical, 8)
                }

                // Icon Selection
                Section("Icon (optional)") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        // No icon option
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.secondary.opacity(0.2))
                                .frame(width: 44, height: 44)

                            Image(systemName: "xmark")
                                .foregroundStyle(.secondary)
                        }
                        .overlay {
                            if selectedIcon == nil {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(selectedColor, lineWidth: 2)
                            }
                        }
                        .onTapGesture {
                            selectedIcon = nil
                        }

                        ForEach(availableIcons, id: \.self) { icon in
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
                            .onTapGesture {
                                selectedIcon = icon
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
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
    private var topicPreview: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(selectedColor.gradient)
                    .frame(width: 80, height: 80)

                if let icon = selectedIcon {
                    Image(systemName: icon)
                        .font(.system(size: 36))
                        .foregroundStyle(.white)
                } else {
                    Text(customLetter.isEmpty ? String(topic.name.prefix(1)).uppercased() : customLetter)
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }

            Text(topic.name)
                .font(.headline)
        }
        .padding()
    }

    private func colorMatches(_ color: Color) -> Bool {
        let colorHex = color.toHex()
        let selectedHex = selectedColor.toHex()
        return colorHex == selectedHex
    }

    private func saveChanges() {
        topic.colorHex = selectedColor.toHex()
        topic.customLetter = customLetter.isEmpty ? nil : customLetter
        topic.iconName = selectedIcon
        topic.useMessageIcon = useMessageIcon
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Topic.self, configurations: config)
    let topic = Topic(name: "test-topic", serverURL: "https://ntfy.sh")
    container.mainContext.insert(topic)

    return EditTopicView(topic: topic)
        .modelContainer(container)
}
