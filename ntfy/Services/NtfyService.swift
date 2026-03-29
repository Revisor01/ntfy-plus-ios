import Foundation
import Network
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
    private var activeConfigs: [String: SubscriptionConfig] = [:]

    var isConnecting = false
    var connectionError: NtfyError?
    var connectionStatus: ConnectionStatus = .disconnected

    private var pathMonitor: NWPathMonitor?
    private var monitorQueue = DispatchQueue(label: "de.godsapp.ntfy.networkmonitor")

    enum ConnectionStatus: Equatable {
        case connected
        case connecting
        case disconnected
        case reconnecting(attempt: Int)
    }

    private struct SubscriptionConfig: Sendable {
        let serverURL: String
        let topic: String
        let username: String?
        let password: String?
        let token: String?
        let onMessage: @MainActor @Sendable (NtfyMessage) -> Void
        let onDelete: (@MainActor @Sendable (String) -> Void)?
        let onClear: (@MainActor @Sendable () -> Void)?
    }

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
        startNetworkMonitor()
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
        onMessage: @escaping @MainActor @Sendable (NtfyMessage) -> Void,
        onDelete: (@MainActor @Sendable (String) -> Void)? = nil,
        onClear: (@MainActor @Sendable () -> Void)? = nil
    ) {
        let key = "\(serverURL)/\(topic)"

        // Cancel existing subscription
        activeTasks[key]?.cancel()

        // Store config for reconnect (im @MainActor-Kontext — korrekt)
        activeConfigs[key] = SubscriptionConfig(
            serverURL: serverURL,
            topic: topic,
            username: username,
            password: password,
            token: token,
            onMessage: onMessage,
            onDelete: onDelete,
            onClear: onClear
        )

        print("🔌 SSE: Subscribing to \(topic)")

        // WICHTIG: Alle Werte als lokale lets capturen BEVOR Task.detached startet.
        // So wird activeConfigs im detached Task NIE referenziert — kein MainActor-Isolation-Problem.
        let capturedServerURL = serverURL
        let capturedTopic = topic
        let capturedUsername = username
        let capturedPassword = password
        let capturedToken = token
        let capturedOnMessage = onMessage
        let capturedOnDelete = onDelete
        let capturedOnClear = onClear

        let task = Task.detached { [weak self] in
            guard let self else { return }

            let urlString = "\(capturedServerURL)/\(capturedTopic)/sse"
            guard let url = URL(string: urlString) else {
                print("🔌 SSE: Invalid URL for \(capturedTopic)")
                return
            }

            var backoffSeconds: UInt64 = 1
            let maxBackoff: UInt64 = 60

            while !Task.isCancelled {
                let auth = await self.authHeader(username: capturedUsername, password: capturedPassword, token: capturedToken)
                var request = await self.createRequest(url: url, auth: auth)
                request.timeoutInterval = TimeInterval.infinity

                do {
                    await MainActor.run { self.connectionStatus = .connecting }
                    print("🔌 SSE: Connecting to \(capturedTopic)...")

                    let (bytes, response) = try await self.session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200 else {
                        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                        print("🔌 SSE: Bad response \(code) for \(capturedTopic)")
                        break  // Nicht retrybar bei Auth-Fehlern etc.
                    }

                    // Verbindung erfolgreich — Backoff zuruecksetzen
                    backoffSeconds = 1
                    await MainActor.run { self.connectionStatus = .connected }
                    print("🔌 SSE: Connected to \(capturedTopic)")

                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            print("🔌 SSE: Cancelled for \(capturedTopic)")
                            return
                        }

                        if line.hasPrefix("data: ") {
                            let jsonString = String(line.dropFirst(6))
                            if let data = jsonString.data(using: .utf8),
                               let message = try? JSONDecoder().decode(NtfyMessage.self, from: data) {
                                switch message.event {
                                case "message":
                                    print("🔌 SSE: Received message for \(capturedTopic)")
                                    await capturedOnMessage(message)
                                case "message_delete":
                                    print("🔌 SSE: Received delete for \(capturedTopic), id: \(message.id)")
                                    await capturedOnDelete?(message.id)
                                case "message_clear":
                                    print("🔌 SSE: Received clear for \(capturedTopic)")
                                    await capturedOnClear?()
                                default:
                                    break
                                }
                            }
                        }
                    }

                    print("🔌 SSE: Stream ended for \(capturedTopic), reconnecting in \(backoffSeconds)s")

                } catch {
                    if Task.isCancelled { return }
                    print("🔌 SSE Error for \(capturedTopic): \(error), retry in \(backoffSeconds)s")
                }

                // Backoff-Sleep
                await MainActor.run {
                    self.connectionStatus = .reconnecting(attempt: Int(backoffSeconds))
                }
                try? await Task.sleep(for: .seconds(backoffSeconds))

                // Exponentielles Erhoehen mit Cap
                backoffSeconds = min(backoffSeconds * 2, maxBackoff)
            }

            await MainActor.run {
                if !Task.isCancelled {
                    self.connectionStatus = .disconnected
                }
            }
        }

        activeTasks[key] = task
    }

    func unsubscribe(serverURL: String, topic: String) {
        let key = "\(serverURL)/\(topic)"
        activeTasks[key]?.cancel()
        activeTasks.removeValue(forKey: key)
        activeConfigs.removeValue(forKey: key)
    }

    func unsubscribeAll() {
        for task in activeTasks.values {
            task.cancel()
        }
        activeTasks.removeAll()
        activeConfigs.removeAll()
        connectionStatus = .disconnected
    }

    // MARK: - Network Monitoring

    func startNetworkMonitor() {
        pathMonitor = NWPathMonitor()
        pathMonitor?.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            if path.status == .satisfied {
                print("🔌 Network: Path restored (\(path.availableInterfaces.map(\.name).joined(separator: ", ")))")
                Task { @MainActor in
                    await self.reconnectAll()
                }
            } else {
                Task { @MainActor in
                    self.connectionStatus = .disconnected
                }
            }
        }
        pathMonitor?.start(queue: monitorQueue)
    }

    func stopNetworkMonitor() {
        pathMonitor?.cancel()
        pathMonitor = nil
    }

    func reconnectAll() async {
        print("🔌 Network: Reconnecting all \(activeConfigs.count) subscriptions")

        // Alle aktiven Tasks canceln
        for task in activeTasks.values {
            task.cancel()
        }
        activeTasks.removeAll()

        // Sofort neu subscriben mit gespeicherten Configs
        // reconnectAll() laeuft im @MainActor-Kontext, daher ist Zugriff auf activeConfigs sicher.
        // subscribe() erstellt intern neue lokale Kopien fuer den Task.detached-Block.
        for (_, config) in activeConfigs {
            subscribe(
                serverURL: config.serverURL,
                topic: config.topic,
                username: config.username,
                password: config.password,
                token: config.token,
                onMessage: config.onMessage,
                onDelete: config.onDelete,
                onClear: config.onClear
            )
        }
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
            // Neue Messages sind immer ungelesen — denormalisierten Zaehler inkrementieren
            topic.unreadCount += 1
        }

        // Update lastMessageAt und denormalisierte Preview-Properties
        if let latest = messages.max(by: { $0.time < $1.time }) {
            topic.lastMessageAt = Date(timeIntervalSince1970: TimeInterval(latest.time))
            topic.lastMessagePreview = latest.message ?? latest.title
            topic.lastMessagePriority = latest.priority ?? 3
            topic.lastMessageIconURL = latest.icon
        }

        try? context.save()
    }

    // MARK: - Refresh Topics

    /// Fetcht Nachrichten fuer alle Topics PARALLEL via TaskGroup und speichert sie via storeMessages.
    /// Ersetzt ContentView.refreshAllTopics() und TopicsView.refreshAllTopics().
    /// Netzwerk-Requests laufen parallel, Ergebnisse werden sequentiell auf @MainActor gespeichert.
    func refreshTopics(
        _ topics: [Topic],
        context: ModelContext,
        since: String
    ) async {
        print("🔄 Starting parallel refresh for \(topics.count) topics (since: \(since))")

        // Sendable Struktur fuer Fetch-Ergebnisse
        struct FetchResult: Sendable {
            let serverURL: String
            let topicName: String
            let messages: [NtfyMessage]
        }

        // Phase 1: Parallele Netzwerk-Requests — nur Sendable-Werte capturen
        let results: [FetchResult] = await withTaskGroup(of: FetchResult?.self) { group in
            for topic in topics {
                let serverURL = topic.serverURL
                let topicName = topic.name
                let token = KeychainManager.shared.loadToken(serverURL: serverURL)
                let credentials = KeychainManager.shared.loadCredentials(serverURL: serverURL)

                group.addTask { [weak self] in
                    guard let self else { return nil }
                    do {
                        let messages = try await self.fetchMessages(
                            serverURL: serverURL,
                            topic: topicName,
                            since: since,
                            username: credentials?.username,
                            password: credentials?.password,
                            token: token
                        )
                        print("🔄 Fetched \(messages.count) messages for \(topicName)")
                        return FetchResult(serverURL: serverURL, topicName: topicName, messages: messages)
                    } catch {
                        print("❌ Failed to refresh topic \(topicName): \(error)")
                        return nil
                    }
                }
            }

            var collected: [FetchResult] = []
            for await result in group {
                if let result = result {
                    collected.append(result)
                }
            }
            return collected
        }

        // Phase 2: Sequentielles Speichern auf @MainActor (ModelContext ist nicht thread-safe)
        for result in results {
            if let topic = topics.first(where: { $0.serverURL == result.serverURL && $0.name == result.topicName }) {
                storeMessages(for: topic, messages: result.messages, context: context)
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
