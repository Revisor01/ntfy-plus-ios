import SwiftUI
import Observation

// MARK: - Attachment Image Disk Cache

@MainActor
final class AttachmentImageCache {
    static let shared = AttachmentImageCache()

    private let cacheDirectory: URL?

    private init() {
        cacheDirectory = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.de.godsapp.ntfy")?
            .appendingPathComponent("image_cache/")
        if let dir = cacheDirectory {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    private func cacheKey(for urlString: String) -> String {
        let hash = urlString.utf8.reduce(UInt(5381)) { ($0 << 5) &+ $0 &+ UInt($1) }
        return String(format: "%016lx.img", hash)
    }

    func loadFromDisk(for urlString: String) -> UIImage? {
        guard let dir = cacheDirectory else { return nil }
        let fileURL = dir.appendingPathComponent(cacheKey(for: urlString))

        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        // Expiry-Check: Datei aelter als 7 Tage loeschen
        if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let creationDate = attrs[.creationDate] as? Date {
            let age = Date().timeIntervalSince(creationDate)
            if age > 7 * 24 * 3600 {
                try? FileManager.default.removeItem(at: fileURL)
                return nil
            }
        }

        return UIImage(contentsOfFile: fileURL.path)
    }

    func saveToDisk(_ data: Data, for urlString: String) {
        guard let dir = cacheDirectory else { return }
        let fileURL = dir.appendingPathComponent(cacheKey(for: urlString))
        try? data.write(to: fileURL)
    }

    func clearDiskCache() {
        guard let dir = cacheDirectory else { return }
        let contents = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for file in contents {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Belegter Speicher des Disk-Caches in Bytes.
    func diskCacheSize() -> Int {
        guard let dir = cacheDirectory else { return 0 }
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey]
        )) ?? []
        return contents.reduce(0) { total, file in
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return total + size
        }
    }
}

// MARK: - Icon Manager

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

struct CachedAsyncImage<Placeholder: View, Failure: View>: View {
    let url: String?
    var useDiskCache: Bool = false
    @ViewBuilder let content: (Image) -> AnyView
    @ViewBuilder let placeholder: () -> Placeholder
    @ViewBuilder let failure: () -> Failure

    @State private var image: UIImage?
    @State private var isLoading = false
    @State private var didFail = false

    var body: some View {
        Group {
            if let image = image {
                content(Image(uiImage: image))
            } else if didFail {
                failure()
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            await loadImage()
        }
    }

    private func loadImage() async {
        image = nil
        didFail = false
        isLoading = false

        guard let urlString = url, !urlString.isEmpty else { return }

        if useDiskCache {
            // Disk-Cache pruefen
            if let cached = AttachmentImageCache.shared.loadFromDisk(for: urlString) {
                image = cached
                return
            }

            // Netzwerk-Download
            isLoading = true
            guard let url = URL(string: urlString) else {
                isLoading = false
                didFail = true
                return
            }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200,
                      let downloaded = UIImage(data: data) else {
                    isLoading = false
                    didFail = true
                    return
                }
                // Auf Disk speichern
                AttachmentImageCache.shared.saveToDisk(data, for: urlString)
                image = downloaded
            } catch {
                print("❌ CachedAsyncImage disk fetch failed: \(error)")
                didFail = true
            }
            isLoading = false
        } else {
            // NSCache-basiertes Verhalten (IconManager)
            isLoading = true
            image = await IconManager.shared.loadIcon(from: urlString)
            if image == nil { didFail = true }
            isLoading = false
        }
    }
}

// Convenience-Init fuer die einfache SF-Symbol-Platzhalter-Variante (Icons/Topics)
extension CachedAsyncImage where Placeholder == AnyView, Failure == AnyView {
    init(url: String?, placeholder: String, useDiskCache: Bool = false) {
        self.url = url
        self.useDiskCache = useDiskCache
        self.content = { img in
            AnyView(img.resizable().aspectRatio(contentMode: .fit))
        }
        self.placeholder = {
            AnyView(ProgressView())
        }
        self.failure = {
            AnyView(
                Image(systemName: placeholder)
                    .font(.title2)
                    .foregroundStyle(.secondary)
            )
        }
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
