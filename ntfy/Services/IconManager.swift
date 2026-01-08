import SwiftUI
import Observation

@Observable
@MainActor
final class IconManager {
    static let shared = IconManager()

    private let cache = NSCache<NSString, UIImage>()
    private var loadingTasks: [String: Task<UIImage?, Never>] = [:]

    private init() {
        cache.countLimit = 100
        cache.totalCostLimit = 50 * 1024 * 1024 // 50MB
    }

    // MARK: - Icon Loading

    func loadIcon(from urlString: String) async -> UIImage? {
        // Check cache first
        if let cached = cache.object(forKey: urlString as NSString) {
            return cached
        }

        // Check if already loading
        if let existingTask = loadingTasks[urlString] {
            return await existingTask.value
        }

        // Start new loading task
        let task = Task<UIImage?, Never> {
            guard let url = URL(string: urlString) else { return nil }

            do {
                let (data, response) = try await URLSession.shared.data(from: url)

                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200,
                      let image = UIImage(data: data) else {
                    return nil
                }

                // Resize if too large
                let resized = resizeImageIfNeeded(image, maxSize: CGSize(width: 128, height: 128))

                // Cache the result
                cache.setObject(resized, forKey: urlString as NSString)

                return resized
            } catch {
                print("Failed to load icon: \(error)")
                return nil
            }
        }

        loadingTasks[urlString] = task
        let result = await task.value
        loadingTasks.removeValue(forKey: urlString)

        return result
    }

    // MARK: - Image Processing

    private func resizeImageIfNeeded(_ image: UIImage, maxSize: CGSize) -> UIImage {
        let size = image.size

        guard size.width > maxSize.width || size.height > maxSize.height else {
            return image
        }

        let ratio = min(maxSize.width / size.width, maxSize.height / size.height)
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    // MARK: - Cache Management

    func clearCache() {
        cache.removeAllObjects()
    }

    func removeFromCache(urlString: String) {
        cache.removeObject(forKey: urlString as NSString)
    }

    // MARK: - SF Symbol Icons for Topics

    static let topicIcons: [(name: String, icon: String)] = [
        ("Standard", "bell.fill"),
        ("Nachricht", "envelope.fill"),
        ("Warnung", "exclamationmark.triangle.fill"),
        ("Fehler", "xmark.circle.fill"),
        ("Erfolg", "checkmark.circle.fill"),
        ("Info", "info.circle.fill"),
        ("Server", "server.rack"),
        ("Datenbank", "externaldrive.fill"),
        ("Code", "chevron.left.forwardslash.chevron.right"),
        ("Wolke", "cloud.fill"),
        ("Download", "arrow.down.circle.fill"),
        ("Upload", "arrow.up.circle.fill"),
        ("Sync", "arrow.triangle.2.circlepath"),
        ("Backup", "externaldrive.badge.timemachine"),
        ("Sicherheit", "lock.shield.fill"),
        ("Benutzer", "person.fill"),
        ("Gruppe", "person.3.fill"),
        ("Kalender", "calendar"),
        ("Uhr", "clock.fill"),
        ("Ort", "location.fill"),
        ("Haus", "house.fill"),
        ("Auto", "car.fill"),
        ("Flugzeug", "airplane"),
        ("Einkauf", "cart.fill"),
        ("Geld", "creditcard.fill"),
        ("Gesundheit", "heart.fill"),
        ("Sport", "figure.run"),
        ("Musik", "music.note"),
        ("Video", "play.rectangle.fill"),
        ("Foto", "photo.fill"),
        ("Dokument", "doc.fill"),
        ("Ordner", "folder.fill"),
        ("Link", "link"),
        ("Stern", "star.fill"),
        ("Herz", "heart.fill"),
        ("Flagge", "flag.fill"),
        ("Werkzeug", "wrench.and.screwdriver.fill"),
        ("Blitz", "bolt.fill"),
        ("Batterie", "battery.100"),
        ("WLAN", "wifi"),
        ("Bluetooth", "wave.3.right"),
    ]

    static func randomTopicIcon() -> String {
        topicIcons.randomElement()?.icon ?? "bell.fill"
    }
}

// MARK: - AsyncImage with Caching

struct CachedAsyncImage: View {
    let url: String?
    let placeholder: String

    @State private var image: UIImage?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if isLoading {
                ProgressView()
            } else {
                Image(systemName: placeholder)
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let urlString = url, !urlString.isEmpty else { return }

        isLoading = true
        image = await IconManager.shared.loadIcon(from: urlString)
        isLoading = false
    }
}

// MARK: - Topic Icon Picker

struct TopicIconPicker: View {
    @Binding var selectedIcon: String
    @Environment(\.dismiss) private var dismiss

    let columns = [
        GridItem(.adaptive(minimum: 60))
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: AppSpacing.md) {
                    ForEach(IconManager.topicIcons, id: \.icon) { item in
                        Button {
                            selectedIcon = item.icon
                            dismiss()
                        } label: {
                            VStack(spacing: AppSpacing.xs) {
                                Image(systemName: item.icon)
                                    .font(.title)
                                    .frame(width: 50, height: 50)
                                    .background(
                                        selectedIcon == item.icon
                                            ? AppColors.primary.opacity(0.2)
                                            : Color.clear
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.small))

                                Text(item.name)
                                    .font(AppFonts.caption2)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("Icon wählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Color Picker for Topics

struct TopicColorPicker: View {
    @Binding var selectedColor: Color
    @Environment(\.dismiss) private var dismiss

    let columns = [
        GridItem(.adaptive(minimum: 50))
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: AppSpacing.md) {
                    ForEach(Color.predefinedColors, id: \.name) { item in
                        Button {
                            selectedColor = item.color
                            dismiss()
                        } label: {
                            Circle()
                                .fill(item.color)
                                .frame(width: 44, height: 44)
                                .overlay {
                                    if selectedColor == item.color {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.white)
                                            .font(.headline)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("Farbe wählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }
            }
        }
    }
}
