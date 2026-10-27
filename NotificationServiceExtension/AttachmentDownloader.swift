import Foundation
import UserNotifications
import UniformTypeIdentifiers
import os.log

private let logger = Logger(subsystem: "de.godsapp.ntfy.NotificationServiceExtension", category: "Attachment")

// MARK: - AttachmentInfo

/// Anhang einer ntfy-Nachricht (aus dem FCM-Payload oder der poll_request-Antwort).
struct AttachmentInfo: Sendable {
    let url: URL
    let type: String?
    let size: Int?
    let name: String?

    /// Bilder bis 10 MB werden als Vorschau an die Mitteilung gehaengt.
    static let maxImageBytes = 10 * 1024 * 1024

    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "heic"]

    /// Aus den Data-Feldern des FCM-Payloads (attachment_url/_type/_size/_name).
    init?(payload: PushPayload) {
        guard let urlString = payload.nonEmpty("attachment_url") else { return nil }
        self.init(urlString: urlString,
                  type: payload.nonEmpty("attachment_type"),
                  size: payload.nonEmpty("attachment_size").flatMap { Int($0) },
                  name: payload.nonEmpty("attachment_name"))
    }

    /// Aus dem `attachment`-Objekt einer ntfy-JSON-Nachricht.
    init?(message: [String: Any]) {
        guard let attachment = message["attachment"] as? [String: Any],
              let urlString = attachment["url"] as? String else { return nil }
        let size: Int?
        if let number = attachment["size"] as? NSNumber {
            size = number.intValue
        } else if let string = attachment["size"] as? String {
            size = Int(string)
        } else {
            size = nil
        }
        self.init(urlString: urlString,
                  type: attachment["type"] as? String,
                  size: size,
                  name: attachment["name"] as? String)
    }

    private init?(urlString: String, type: String?, size: Int?, name: String?) {
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host != nil else { return nil }
        self.url = url
        self.type = (type?.isEmpty ?? true) ? nil : type
        self.size = size
        self.name = name
    }

    /// Bild (MIME image/* oder bekannte Dateiendung) und nicht nachweislich zu gross.
    var isDownloadableImage: Bool {
        if let size, size > Self.maxImageBytes {
            return false
        }
        if let type, type.lowercased().hasPrefix("image/") {
            return true
        }
        return Self.imageExtensions.contains(url.pathExtension.lowercased())
    }

    /// Passende Dateiendung — UNNotificationAttachment erkennt den Typ ueber die Endung.
    func fileExtension(mimeType: String?) -> String {
        let candidates = [mimeType, type].compactMap { $0?.lowercased() }
        for mime in candidates {
            switch mime {
            case "image/jpeg", "image/jpg", "image/pjpeg": return "jpg"
            case "image/png": return "png"
            case "image/gif": return "gif"
            case "image/webp": return "webp"
            case "image/heic", "image/heif": return "heic"
            default: continue
            }
        }
        let urlExtension = url.pathExtension.lowercased()
        if Self.imageExtensions.contains(urlExtension) {
            return urlExtension
        }
        if let name, let nameExtension = name.split(separator: ".").last.map({ String($0).lowercased() }),
           Self.imageExtensions.contains(nameExtension) {
            return nameExtension
        }
        return "jpg"
    }
}

// MARK: - AttachmentDownloader

/// Lädt ein Bild-Attachment; Zugangsdaten nur für den Server des Topics, Fehler liefern nil statt die Mitteilung scheitern zu lassen.
final class AttachmentDownloader: @unchecked Sendable {
    // @unchecked: veraenderlicher Zustand (currentTask, isCancelled, isFinished) nur unter `lock`
    private let session: URLSession
    private let lock = NSLock()
    private var currentTask: URLSessionDownloadTask?
    private var isCancelled = false
    private var isFinished = false

    init(timeout: TimeInterval) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = min(10, timeout)
        configuration.timeoutIntervalForResource = timeout
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration,
                             delegate: AttachmentRedirectGuard(),
                             delegateQueue: nil)
    }

    /// Startet den Download; `completion` kommt genau einmal, mit nil bei Fehler oder zu großem Anhang.
    func download(_ info: AttachmentInfo,
                  authServers: [String],
                  completion: @escaping @Sendable (UNNotificationAttachment?) -> Void) {
        var request = URLRequest(url: info.url)
        request.httpMethod = "GET"
        if let authorization = Self.authorization(for: info.url, servers: authServers) {
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
        }

        // Pruefen + Anlegen unter dem Lock, damit ein paralleles cancel() den Task sicher erreicht
        lock.lock()
        if isCancelled {
            lock.unlock()
            finish(nil, completion: completion)
            return
        }
        let task = session.downloadTask(with: request) { [self] location, response, error in
            let attachment = Self.makeAttachment(info: info, location: location, response: response, error: error)
            finish(attachment, completion: completion)
        }
        currentTask = task
        lock.unlock()
        task.resume()
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let task = currentTask
        lock.unlock()
        task?.cancel()
    }

    private func finish(_ attachment: UNNotificationAttachment?,
                        completion: @Sendable (UNNotificationAttachment?) -> Void) {
        lock.lock()
        let alreadyFinished = isFinished
        isFinished = true
        lock.unlock()
        guard !alreadyFinished else { return }
        session.finishTasksAndInvalidate()
        completion(attachment)
    }

    // MARK: Auswertung

    private static func makeAttachment(info: AttachmentInfo,
                                       location: URL?,
                                       response: URLResponse?,
                                       error: Error?) -> UNNotificationAttachment? {
        if let error {
            logger.error("Anhang-Download fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        guard let location,
              let httpResponse = response as? HTTPURLResponse else {
            logger.error("Anhang-Download: keine Datei/Antwort")
            return nil
        }
        guard httpResponse.statusCode == 200 else {
            logger.error("Anhang-Download: HTTP \(httpResponse.statusCode, privacy: .public)")
            return nil
        }

        // Kein Bild (z.B. HTML-Fehlerseite) — nicht anhaengen
        let mimeType = httpResponse.mimeType?.lowercased()
        if let mimeType, !mimeType.hasPrefix("image/"), mimeType != "application/octet-stream" {
            logger.error("Anhang-Download: kein Bild (\(mimeType, privacy: .public))")
            return nil
        }

        let fileManager = FileManager.default
        let fileSize = ((try? fileManager.attributesOfItem(atPath: location.path))?[.size] as? NSNumber)?.intValue ?? 0
        guard fileSize > 0, fileSize <= AttachmentInfo.maxImageBytes else {
            logger.error("Anhang-Download: Groesse \(fileSize, privacy: .public) Bytes ausserhalb des Limits")
            return nil
        }

        // Die Download-Datei wird nach dem Callback geloescht — mit passender Endung verschieben
        let fileExtension = info.fileExtension(mimeType: mimeType)
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("ntfy-attachments", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let target = directory.appendingPathComponent("attachment.\(fileExtension)")
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try fileManager.moveItem(at: location, to: target)
        } catch {
            logger.error("Anhang-Download: Datei konnte nicht abgelegt werden: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        var options: [AnyHashable: Any] = [:]
        if let typeIdentifier = UTType(filenameExtension: fileExtension)?.identifier {
            options[UNNotificationAttachmentOptionsTypeHintKey] = typeIdentifier
        }
        do {
            // Verschiebt die Datei in den Attachment-Speicher des Systems
            return try UNNotificationAttachment(identifier: "image", url: target, options: options)
        } catch {
            logger.error("Anhang wird von iOS nicht unterstuetzt: \(error.localizedDescription, privacy: .public)")
            try? fileManager.removeItem(at: directory)
            return nil
        }
    }

    // MARK: Auth

    /// Authorization-Header nur für denselben Scheme, Host und Port.
    private static func authorization(for url: URL, servers: [String]) -> String? {
        for serverURL in servers {
            var base = serverURL
            while base.hasSuffix("/") {
                base.removeLast()
            }
            guard AttachmentRedirectGuard.isSameOrigin(URL(string: base), url) else { continue }

            // Wie NtfyService.authHeader: Token vor Basic-Auth, Keychain-Key mit unveränderter serverURL.
            if let token = SharedKeychain.loadToken(serverURL: serverURL), !token.isEmpty {
                return "Bearer \(token)"
            }
            if let credentials = SharedKeychain.loadCredentials(serverURL: serverURL),
               !credentials.username.isEmpty,
               let data = "\(credentials.username):\(credentials.password)".data(using: .utf8) {
                return "Basic \(data.base64EncodedString())"
            }
            return nil
        }
        return nil
    }
}

// MARK: - Redirect-Schutz

/// Entfernt den Authorization-Header bei Redirects auf einen anderen Scheme, Host oder Port.
final class AttachmentRedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    // Completion-Handler statt async: die async-Variante ließ den Compiler beim ObjC-Thunk abstürzen.
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        let originalURL = task.originalRequest?.url ?? response.url
        guard request.value(forHTTPHeaderField: "Authorization") != nil,
              !Self.isSameOrigin(originalURL, request.url) else {
            completionHandler(request)
            return
        }
        var stripped = request
        stripped.setValue(nil, forHTTPHeaderField: "Authorization")
        logger.info("Redirect auf anderen Host — Authorization-Header entfernt")
        completionHandler(stripped)
    }

    static func isSameOrigin(_ lhs: URL?, _ rhs: URL?) -> Bool {
        guard let lhs, let rhs,
              let lhsScheme = lhs.scheme?.lowercased(),
              let rhsScheme = rhs.scheme?.lowercased(),
              let lhsHost = lhs.host?.lowercased(),
              let rhsHost = rhs.host?.lowercased() else {
            return false
        }
        return lhsScheme == rhsScheme
            && lhsHost == rhsHost
            && effectivePort(of: lhs, scheme: lhsScheme) == effectivePort(of: rhs, scheme: rhsScheme)
    }

    private static func effectivePort(of url: URL, scheme: String) -> Int {
        if let port = url.port { return port }
        return scheme == "https" ? 443 : 80
    }
}
