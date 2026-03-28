import Foundation
import Observation
import SwiftData

enum NtfyError: LocalizedError {
    case invalidURL
    case unauthorized
    case forbidden
    case notFound
    case serverError(Int)
    case networkError(Error)
    case decodingError(Error)
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Ungültige URL"
        case .unauthorized:
            return "Authentifizierung fehlgeschlagen"
        case .forbidden:
            return "Zugriff verweigert"
        case .notFound:
            return "Topic nicht gefunden"
        case .serverError(let code):
            return "Serverfehler (\(code))"
        case .networkError(let error):
            return "Netzwerkfehler: \(error.localizedDescription)"
        case .decodingError:
            return "Fehler beim Verarbeiten der Antwort"
        case .unknown:
            return "Unbekannter Fehler"
        }
    }
}

@Observable
@MainActor
final class NtfyService {
    static let shared = NtfyService()

    private let session: URLSession
    private var activeTasks: [String: Task<Void, Never>] = [:]

    var isConnecting = false
    var connectionError: NtfyError?

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    // MARK: - Authentication

    private func authHeader(username: String?, password: String?, token: String?) -> String? {
        if let token = token, !token.isEmpty {
            return "Bearer \(token)"
        } else if let username = username, let password = password, !username.isEmpty {
            let credentials = "\(username):\(password)"
            if let data = credentials.data(using: .utf8) {
                return "Basic \(data.base64EncodedString())"
            }
        }
        return nil
    }

    private func createRequest(url: URL, method: String = "GET", auth: String? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let auth = auth {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }

        return request
    }

    // MARK: - Fetch Messages

    func fetchMessages(
        serverURL: String,
        topic: String,
        since: String = "24h",
        username: String? = nil,
        password: String? = nil,
        token: String? = nil
    ) async throws -> [NtfyMessage] {
        let urlString = "\(serverURL)/\(topic)/json?poll=1&since=\(since)"
        guard let url = URL(string: urlString) else {
            throw NtfyError.invalidURL
        }

        let auth = authHeader(username: username, password: password, token: token)
        let request = createRequest(url: url, auth: auth)

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NtfyError.unknown
            }

            switch httpResponse.statusCode {
            case 200:
                break
            case 401:
                throw NtfyError.unauthorized
            case 403:
                throw NtfyError.forbidden
            case 404:
                throw NtfyError.notFound
            default:
                if httpResponse.statusCode >= 500 {
                    throw NtfyError.serverError(httpResponse.statusCode)
                }
            }

            // Parse newline-delimited JSON
            let lines = String(data: data, encoding: .utf8)?.split(separator: "\n") ?? []
            let decoder = JSONDecoder()

            var messages: [NtfyMessage] = []
            for line in lines {
                if let lineData = line.data(using: .utf8) {
                    if let message = try? decoder.decode(NtfyMessage.self, from: lineData) {
                        if message.event == "message" {
                            messages.append(message)
                        }
                    }
                }
            }

            return messages.sorted { $0.time > $1.time }

        } catch let error as NtfyError {
            throw error
        } catch {
            throw NtfyError.networkError(error)
        }
    }

    // MARK: - Publish Message

    func publish(
        serverURL: String,
        topic: String,
        message: String,
        title: String? = nil,
        priority: Priority = .default,
        tags: [String]? = nil,
        click: String? = nil,
        attach: String? = nil,
        icon: String? = nil,
        username: String? = nil,
        password: String? = nil,
        token: String? = nil
    ) async throws {
        let urlString = "\(serverURL)/\(topic)"
        guard let url = URL(string: urlString) else {
            throw NtfyError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = message.data(using: .utf8)

        if let auth = authHeader(username: username, password: password, token: token) {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }

        if let title = title {
            request.setValue(title, forHTTPHeaderField: "Title")
        }

        if priority != .default {
            request.setValue(String(priority.rawValue), forHTTPHeaderField: "Priority")
        }

        if let tags = tags, !tags.isEmpty {
            request.setValue(tags.joined(separator: ","), forHTTPHeaderField: "Tags")
        }

        if let click = click {
            request.setValue(click, forHTTPHeaderField: "Click")
        }

        if let attach = attach {
            request.setValue(attach, forHTTPHeaderField: "Attach")
        }

        if let icon = icon {
            request.setValue(icon, forHTTPHeaderField: "Icon")
        }

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NtfyError.unknown
        }

        switch httpResponse.statusCode {
        case 200..<300:
            return
        case 401:
            throw NtfyError.unauthorized
        case 403:
            throw NtfyError.forbidden
        default:
            throw NtfyError.serverError(httpResponse.statusCode)
        }
    }

    // MARK: - Subscribe (SSE)

    func subscribe(
        serverURL: String,
        topic: String,
        username: String? = nil,
        password: String? = nil,
        token: String? = nil,
        onMessage: @escaping @MainActor (NtfyMessage) -> Void,
        onDelete: (@MainActor (String) -> Void)? = nil,
        onClear: (@MainActor () -> Void)? = nil
    ) {
        let key = "\(serverURL)/\(topic)"

        // Cancel existing subscription
        activeTasks[key]?.cancel()

        print("🔌 SSE: Subscribing to \(topic)")

        let task = Task.detached { [weak self] in
            guard let self else { return }

            let urlString = "\(serverURL)/\(topic)/sse"
            guard let url = URL(string: urlString) else {
                print("🔌 SSE: Invalid URL for \(topic)")
                return
            }

            let auth = await self.authHeader(username: username, password: password, token: token)
            var request = await self.createRequest(url: url, auth: auth)
            request.timeoutInterval = TimeInterval.infinity

            do {
                print("🔌 SSE: Connecting to \(topic)...")
                let (bytes, response) = try await self.session.bytes(for: request)

                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                    print("🔌 SSE: Bad response \(code) for \(topic)")
                    return
                }

                print("🔌 SSE: Connected to \(topic)")

                for try await line in bytes.lines {
                    if Task.isCancelled {
                        print("🔌 SSE: Cancelled for \(topic)")
                        break
                    }

                    if line.hasPrefix("data: ") {
                        let jsonString = String(line.dropFirst(6))
                        if let data = jsonString.data(using: .utf8),
                           let message = try? JSONDecoder().decode(NtfyMessage.self, from: data) {
                            switch message.event {
                            case "message":
                                print("🔌 SSE: Received message for \(topic)")
                                await onMessage(message)
                            case "message_delete":
                                print("🔌 SSE: Received delete for \(topic), id: \(message.id)")
                                await onDelete?(message.id)
                            case "message_clear":
                                print("🔌 SSE: Received clear for \(topic)")
                                await onClear?()
                            default:
                                break
                            }
                        }
                    }
                }
                print("🔌 SSE: Stream ended for \(topic)")
            } catch {
                if !Task.isCancelled {
                    print("🔌 SSE Error for \(topic): \(error)")
                }
            }
        }

        activeTasks[key] = task
    }

    func unsubscribe(serverURL: String, topic: String) {
        let key = "\(serverURL)/\(topic)"
        activeTasks[key]?.cancel()
        activeTasks.removeValue(forKey: key)
    }

    func unsubscribeAll() {
        for task in activeTasks.values {
            task.cancel()
        }
        activeTasks.removeAll()
    }

    // MARK: - Delete Message

    /// Löscht eine Nachricht vom Server (ntfy v2.16+)
    /// - Parameters:
    ///   - serverURL: Server URL
    ///   - topic: Topic Name
    ///   - sequenceId: Die Sequence-ID der Nachricht (X-Sequence-ID)
    func deleteMessage(
        serverURL: String,
        topic: String,
        sequenceId: String,
        username: String? = nil,
        password: String? = nil,
        token: String? = nil
    ) async throws {
        let urlString = "\(serverURL)/\(topic)/\(sequenceId)"
        guard let url = URL(string: urlString) else {
            throw NtfyError.invalidURL
        }

        let auth = authHeader(username: username, password: password, token: token)
        var request = createRequest(url: url, method: "DELETE", auth: auth)

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NtfyError.unknown
        }

        switch httpResponse.statusCode {
        case 200..<300:
            return
        case 401:
            throw NtfyError.unauthorized
        case 403:
            throw NtfyError.forbidden
        case 404:
            throw NtfyError.notFound
        default:
            throw NtfyError.serverError(httpResponse.statusCode)
        }
    }

    // MARK: - Server Health Check

    func checkServer(url: String) async throws -> Bool {
        let urlString = "\(url)/v1/health"
        guard let healthURL = URL(string: urlString) else {
            throw NtfyError.invalidURL
        }

        let request = createRequest(url: healthURL)

        do {
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }
            return httpResponse.statusCode == 200
        } catch {
            throw NtfyError.networkError(error)
        }
    }

    // MARK: - Store Messages

    /// Zentrale Methode fuer Insert/Upsert/Dedup/Delete-Check.
    /// Ersetzt die 3x duplizierte Inline-Logik in ContentView, TopicsView und MessagesView.
    func storeMessages(
        for topic: Topic,
        messages: [NtfyMessage],
        context: ModelContext
    ) {
        for message in messages {
            let messageId = message.id

            // 1. Check: existiert bereits?
            let existingPredicate = #Predicate<StoredMessage> { $0.messageId == messageId }
            let descriptor = FetchDescriptor(predicate: existingPredicate)

            if let existing = (try? context.fetch(descriptor))?.first {
                // UPSERT (SERV-02): Server hat Message mit bekannter ID erneut gesendet -> Update
                existing.title = message.title
                existing.message = message.message
                existing.tags = message.tags
                existing.priority = message.priority ?? 3
                existing.clickURL = message.click
                existing.iconURL = message.icon
                if let attachment = message.attachment {
                    existing.attachmentData = try? JSONEncoder().encode(StoredAttachment(from: attachment))
                }
                if let actions = message.actions {
                    existing.actionsData = try? JSONEncoder().encode(actions.map { StoredAction(from: $0) })
                }
                continue
            }

            // 2. Deleted-Check: wurde vom User geloescht?
            let topicName = topic.name
            let serverURL = topic.serverURL
            let deletedPredicate = #Predicate<DeletedMessage> { deleted in
                deleted.messageId == messageId &&
                deleted.topicName == topicName &&
                deleted.serverURL == serverURL
            }
            let deletedDescriptor = FetchDescriptor(predicate: deletedPredicate)
            guard (try? context.fetch(deletedDescriptor))?.isEmpty ?? true else { continue }

            // 3. Insert
            let storedMessage = StoredMessage(from: message, topic: topic)
            context.insert(storedMessage)
        }

        // Update lastMessageAt mit dem neuesten Message-Timestamp
        if let latest = messages.max(by: { $0.time < $1.time }) {
            topic.lastMessageAt = Date(timeIntervalSince1970: TimeInterval(latest.time))
        }

        try? context.save()
    }

    // MARK: - Refresh Topics

    /// Fetcht Nachrichten fuer alle Topics PARALLEL via TaskGroup und speichert sie via storeMessages.
    /// Ersetzt ContentView.refreshAllTopics() und TopicsView.refreshAllTopics().
    /// Netzwerk-Requests laufen parallel, ModelContext-Zugriffe (storeMessages) auf @MainActor.
    func refreshTopics(
        _ topics: [Topic],
        context: ModelContext,
        since: String
    ) async {
        print("🔄 Starting parallel refresh for \(topics.count) topics (since: \(since))")

        await withTaskGroup(of: Void.self) { group in
            for topic in topics {
                group.addTask { [weak self] in
                    guard let self else { return }

                    let token = KeychainManager.shared.loadToken(serverURL: topic.serverURL)
                    let credentials = KeychainManager.shared.loadCredentials(serverURL: topic.serverURL)

                    do {
                        let messages = try await self.fetchMessages(
                            serverURL: topic.serverURL,
                            topic: topic.name,
                            since: since,
                            username: credentials?.username,
                            password: credentials?.password,
                            token: token
                        )

                        print("🔄 Fetched \(messages.count) messages for \(topic.name)")

                        // ModelContext ist nicht thread-safe — storeMessages auf MainActor ausfuehren
                        await MainActor.run {
                            self.storeMessages(for: topic, messages: messages, context: context)
                        }
                    } catch {
                        print("❌ Failed to refresh topic \(topic.name): \(error)")
                    }
                }
            }
        }

        print("✅ Parallel refresh complete")
    }

    // MARK: - Test Authentication

    func testAuth(
        serverURL: String,
        topic: String,
        username: String?,
        password: String?,
        token: String?
    ) async throws -> Bool {
        let urlString = "\(serverURL)/\(topic)/auth"
        guard let url = URL(string: urlString) else {
            throw NtfyError.invalidURL
        }

        let auth = authHeader(username: username, password: password, token: token)
        let request = createRequest(url: url, auth: auth)

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }

        return httpResponse.statusCode == 200
    }
}
