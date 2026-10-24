import Foundation
import Network
import Observation
import SwiftData
import WidgetKit

enum NtfyError: LocalizedError {
    case invalidURL
    case unauthorized
    case forbidden
    case notFound
    case serverError(Int)
    case networkError(Error)
    case decodingError(Error)
    case badRequest(String?)
    case rateLimited
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
        case .badRequest(let detail):
            if let detail, !detail.isEmpty {
                return "Ungültige Anfrage: \(detail)"
            }
            return "Ungültige Anfrage"
        case .rateLimited:
            return "Zu viele Anfragen – bitte später erneut versuchen"
        case .unknown:
            return "Unbekannter Fehler"
        }
    }
}

// MARK: - Event-Typen & Sequenz-Schluessel

extension NtfyMessage {
    /// Schluessel, ueber den message_delete/message_clear und Updates eine Nachricht
    /// identifizieren (ntfy: `sequence_id`, Fallback auf die eigene `id`).
    var sequenceKey: String {
        if let sequenceId, !sequenceId.isEmpty {
            return sequenceId
        }
        return id
    }
}

private enum NtfyEventType {
    static let message = "message"
    static let messageDelete = "message_delete"
    static let messageClear = "message_clear"

    /// Events, die den lokalen Nachrichtenbestand veraendern (open/keepalive/poll_request nicht)
    static let stateChanging: Set<String> = [message, messageDelete, messageClear]
}

// MARK: - SSE-Konfiguration

private enum SSEConfig {
    /// Server schickt alle ~45 s ein keepalive — nach 120 s ohne Daten gilt die Verbindung als tot.
    static let idleTimeout: TimeInterval = 120
    /// Gesamtlaufzeit eines Streams praktisch unbegrenzt (7 Tage), sonst bricht URLSession ab.
    static let resourceTimeout: TimeInterval = 7 * 24 * 3600
    static let maxBackoffSeconds: UInt64 = 60
    /// Bei 429 nicht schneller als alle 30 s erneut versuchen
    static let rateLimitBackoffSeconds: UInt64 = 30
    /// Anzahl zuletzt gesehener Event-IDs fuer die Dedup nach Reconnect (since=<id>)
    static let dedupWindow = 200
}

// MARK: - URL-Bau & HTTP-Helfer

private enum NtfyHTTP {
    /// Erlaubte Zeichen fuer ein einzelnes Pfadsegment — "/" und ";" werden kodiert,
    /// damit Topic-Namen wie "a/b" oder "x?y" den Pfad nicht veraendern koennen.
    static let pathSegmentAllowed: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.remove(charactersIn: "/;")
        return set
    }()

    static func encodePathSegment(_ segment: String) -> String? {
        // "." und ".." wuerden als Dot-Segmente den Pfad verlassen
        if segment == "." || segment == ".." {
            return segment.replacingOccurrences(of: ".", with: "%2E")
        }
        return segment.addingPercentEncoding(withAllowedCharacters: pathSegmentAllowed)
    }

    /// Baut `<serverURL>/<seg1>/<seg2>…?<query>` mit einzeln kodierten Pfadsegmenten.
    /// Ohne Segmente entsteht `<serverURL>/` (z.B. fuer JSON-Publish).
    static func url(serverURL: String, pathSegments: [String], queryItems: [URLQueryItem]? = nil) -> URL? {
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = components.host, !host.isEmpty else {
            return nil
        }

        var encodedSegments: [String] = []
        for segment in pathSegments {
            guard let encoded = encodePathSegment(segment), !encoded.isEmpty else { return nil }
            encodedSegments.append(encoded)
        }

        var basePath = components.percentEncodedPath
        while basePath.hasSuffix("/") {
            basePath.removeLast()
        }
        components.percentEncodedPath = basePath + "/" + encodedSegments.joined(separator: "/")
        components.queryItems = (queryItems?.isEmpty ?? true) ? nil : queryItems
        components.fragment = nil
        return components.url
    }

    /// ntfy-Fehlerantwort: {"code":40001,"http":400,"error":"…","link":"…"}
    private struct ServerErrorResponse: Decodable {
        let error: String?
    }

    static func serverErrorMessage(from data: Data) -> String? {
        guard let response = try? JSONDecoder().decode(ServerErrorResponse.self, from: data),
              let message = response.error?.trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty else {
            return nil
        }
        return message
    }
}

// MARK: - JSON-Publish Payload

/// Body fuer `POST <serverURL>/` (docs.ntfy.sh/publish/#publish-as-json).
/// nil-Felder werden vom synthetisierten Encoder weggelassen.
private struct PublishPayload: Encodable {
    let topic: String
    let message: String
    let title: String?
    let tags: [String]?
    let priority: Int?
    let click: String?
    let attach: String?
    let icon: String?
    let delay: String?
    let email: String?
    let markdown: Bool?
    let actions: [NtfyAction]?
}

// MARK: - Redirect-Schutz

/// Entfernt den Authorization-Header, wenn ein Redirect auf einen anderen
/// Scheme/Host/Port zeigt als der urspruengliche Request — Zugangsdaten
/// duerfen nicht an fremde Server weitergereicht werden.
/// Keine gespeicherten Properties → echtes Sendable ohne @unchecked.
final class RedirectAuthGuard: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        let originalURL = task.originalRequest?.url ?? response.url
        guard request.value(forHTTPHeaderField: "Authorization") != nil,
              !Self.isSameOrigin(originalURL, request.url) else {
            return request
        }
        var stripped = request
        stripped.setValue(nil, forHTTPHeaderField: "Authorization")
        AppLog.network.info("🔒 Redirect auf anderen Host — Authorization-Header entfernt")
        return stripped
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

@Observable
@MainActor
final class NtfyService {
    static let shared = NtfyService()

    private let session: URLSession
    /// Eigene Session fuer SSE: langer Resource-Timeout, Idle-Timeout passend zu den keepalives
    private let sseSession: URLSession
    @ObservationIgnored private var activeTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var activeConfigs: [String: SubscriptionConfig] = [:]
    /// Pro Subscription eine Generation — Status-Updates alter (ersetzter) Tasks werden verworfen
    @ObservationIgnored private var subscriptionGenerations: [String: UUID] = [:]
    /// Verbindungsstatus pro Subscription; `connectionStatus` ist das Aggregat daraus
    @ObservationIgnored private var subscriptionStates: [String: ConnectionStatus] = [:]
    /// Zuletzt empfangene Event-ID pro Subscription fuer Reconnect mit `since=<id>`
    @ObservationIgnored private var lastEventIds: [String: String] = [:]

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
        let onDelete: (@MainActor @Sendable (NtfyMessage) -> Void)?
        let onClear: (@MainActor @Sendable (NtfyMessage) -> Void)?
    }

    private init() {
        let redirectGuard = RedirectAuthGuard()

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config, delegate: redirectGuard, delegateQueue: nil)

        let sseConfig = URLSessionConfiguration.default
        sseConfig.timeoutIntervalForRequest = SSEConfig.idleTimeout
        sseConfig.timeoutIntervalForResource = SSEConfig.resourceTimeout
        sseConfig.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.sseSession = URLSession(configuration: sseConfig, delegate: redirectGuard, delegateQueue: nil)

        startNetworkMonitor()
    }

    // MARK: - Authentication

    private nonisolated func authHeader(username: String?, password: String?, token: String?) -> String? {
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

    /// Liefert den effektiven Nachrichtenbestand (neueste zuerst): Updates mit gleicher
    /// sequence_id ersetzen fruehere Versionen, per message_delete geloeschte Nachrichten fehlen.
    /// Fuer das vollstaendige Event-Protokoll (inkl. delete/clear) siehe `fetchEvents`.
    func fetchMessages(
        serverURL: String,
        topic: String,
        since: String = "24h",
        username: String? = nil,
        password: String? = nil,
        token: String? = nil
    ) async throws -> [NtfyMessage] {
        let events = try await fetchEvents(
            serverURL: serverURL,
            topic: topic,
            since: since,
            username: username,
            password: password,
            token: token
        )

        // Events in Server-Reihenfolge anwenden: letzte Version je Sequenz gewinnt
        var latestBySequence: [String: NtfyMessage] = [:]
        for event in events {
            switch event.event {
            case NtfyEventType.message:
                latestBySequence[event.sequenceKey] = event
            case NtfyEventType.messageDelete:
                latestBySequence.removeValue(forKey: event.sequenceKey)
            default:
                break
            }
        }

        return latestBySequence.values.sorted { $0.time > $1.time }
    }

    /// Pollt alle zustandsrelevanten Events (message, message_delete, message_clear)
    /// in Server-Reihenfolge (chronologisch). Wird von `refreshTopics` genutzt, damit
    /// Loesch-/Clear-Events auch beim Polling angewendet werden.
    func fetchEvents(
        serverURL: String,
        topic: String,
        since: String = "24h",
        username: String? = nil,
        password: String? = nil,
        token: String? = nil
    ) async throws -> [NtfyMessage] {
        guard let url = NtfyHTTP.url(
            serverURL: serverURL,
            pathSegments: [topic, "json"],
            queryItems: [
                URLQueryItem(name: "poll", value: "1"),
                URLQueryItem(name: "since", value: since)
            ]
        ) else {
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
            case 200..<300:
                break
            case 400:
                throw NtfyError.badRequest(NtfyHTTP.serverErrorMessage(from: data))
            case 401:
                throw NtfyError.unauthorized
            case 403:
                throw NtfyError.forbidden
            case 404:
                throw NtfyError.notFound
            case 429:
                throw NtfyError.rateLimited
            default:
                throw NtfyError.serverError(httpResponse.statusCode)
            }

            // Parse newline-delimited JSON
            let lines = String(data: data, encoding: .utf8)?.split(separator: "\n") ?? []
            let decoder = JSONDecoder()

            var events: [NtfyMessage] = []
            for line in lines {
                guard let lineData = line.data(using: .utf8),
                      let event = try? decoder.decode(NtfyMessage.self, from: lineData),
                      NtfyEventType.stateChanging.contains(event.event) else {
                    continue
                }
                events.append(event)
            }

            return events

        } catch let error as NtfyError {
            throw error
        } catch {
            throw NtfyError.networkError(error)
        }
    }

    // MARK: - Publish Message

    /// Veroeffentlicht per JSON-Publish (`POST <serverURL>/`). Anders als HTTP-Header
    /// transportiert JSON Umlaute/Emoji in Titel und Tags korrekt.
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
        delay: String? = nil,
        email: String? = nil,
        markdown: Bool = false,
        actions: [NtfyAction]? = nil,
        username: String? = nil,
        password: String? = nil,
        token: String? = nil
    ) async throws {
        guard let url = NtfyHTTP.url(serverURL: serverURL, pathSegments: []) else {
            throw NtfyError.invalidURL
        }

        let cleanedTags = tags?.filter { !$0.isEmpty }
        let payload = PublishPayload(
            topic: topic,
            message: message,
            title: title,
            tags: (cleanedTags?.isEmpty ?? true) ? nil : cleanedTags,
            priority: priority == .default ? nil : priority.rawValue,
            click: click,
            attach: attach,
            icon: icon,
            delay: (delay?.isEmpty ?? true) ? nil : delay,
            email: (email?.isEmpty ?? true) ? nil : email,
            markdown: markdown ? true : nil,
            actions: (actions?.isEmpty ?? true) ? nil : actions
        )

        var request = createRequest(
            url: url,
            method: "POST",
            auth: authHeader(username: username, password: password, token: token)
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONEncoder().encode(payload)
        } catch {
            throw NtfyError.decodingError(error)
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NtfyError.unknown
        }

        switch httpResponse.statusCode {
        case 200..<300:
            return
        case 400:
            let detail = NtfyHTTP.serverErrorMessage(from: data)
            AppLog.network.error("📤 Publish abgelehnt (400): \(detail ?? "-", privacy: .private)")
            throw NtfyError.badRequest(detail)
        case 401:
            throw NtfyError.unauthorized
        case 403:
            throw NtfyError.forbidden
        case 429:
            throw NtfyError.rateLimited
        default:
            throw NtfyError.serverError(httpResponse.statusCode)
        }
    }

    // MARK: - Subscribe (SSE)

    /// Abonniert ein Topic per SSE. Reconnects laufen mit exponentiellem Backoff und
    /// `since=<letzte Event-ID>`, damit waehrend der Unterbrechung verpasste Events nachgeliefert werden.
    /// - Parameters:
    ///   - onMessage: neues/aktualisiertes `message`-Event
    ///   - onDelete: `message_delete`-Event (Ziel steht in `sequenceId` bzw. `sequenceKey`)
    ///   - onClear: `message_clear`-Event (Ziel steht in `sequenceId` bzw. `sequenceKey`)
    func subscribe(
        serverURL: String,
        topic: String,
        username: String? = nil,
        password: String? = nil,
        token: String? = nil,
        onMessage: @escaping @MainActor @Sendable (NtfyMessage) -> Void,
        onDelete: (@MainActor @Sendable (NtfyMessage) -> Void)? = nil,
        onClear: (@MainActor @Sendable (NtfyMessage) -> Void)? = nil
    ) {
        let key = subscriptionKey(serverURL: serverURL, topic: topic)

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

        // Neue Generation — Status-Updates eines evtl. noch auslaufenden alten Tasks ignorieren
        let generation = UUID()
        subscriptionGenerations[key] = generation
        updateSubscriptionState(key: key, generation: generation, state: .connecting)

        AppLog.network.info("🔌 SSE: Subscribing to \(topic, privacy: .private)")

        // WICHTIG: Alle Werte als lokale lets capturen BEVOR Task.detached startet.
        // So wird activeConfigs im detached Task NIE referenziert — kein MainActor-Isolation-Problem.
        let capturedServerURL = serverURL
        let capturedTopic = topic
        let capturedAuth = authHeader(username: username, password: password, token: token)
        let capturedSession = sseSession
        let initialSince = lastEventIds[key]
        let capturedOnMessage = onMessage
        let capturedOnDelete = onDelete
        let capturedOnClear = onClear

        let task = Task.detached { [weak self] in
            guard let self else { return }

            var backoffSeconds: UInt64 = 1
            var attempt = 0

            // Letzte Event-ID fuer since=<id>; ohne bekannte ID Fallback auf den
            // Zeitpunkt der ersten erfolgreichen Verbindung (Unix-Sekunden).
            var lastEventId: String? = initialSince
            var fallbackSince: Int?

            // Dedup: Server >= 2.31 liefert bei since=<id> ggf. Nachrichten derselben Sekunde erneut
            var recentIds: [String] = []
            var recentIdSet: Set<String> = []
            if let initialSince {
                recentIds.append(initialSince)
                recentIdSet.insert(initialSince)
            }

            while !Task.isCancelled {
                var queryItems: [URLQueryItem] = []
                if let since = lastEventId ?? fallbackSince.map({ String($0) }) {
                    queryItems.append(URLQueryItem(name: "since", value: since))
                }

                guard let url = NtfyHTTP.url(
                    serverURL: capturedServerURL,
                    pathSegments: [capturedTopic, "sse"],
                    queryItems: queryItems
                ) else {
                    AppLog.network.error("🔌 SSE: Invalid URL for \(capturedTopic, privacy: .private)")
                    await self.updateSubscriptionState(key: key, generation: generation, state: .disconnected)
                    return
                }

                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                if let capturedAuth {
                    request.setValue(capturedAuth, forHTTPHeaderField: "Authorization")
                }
                // Idle-Timeout statt .infinity — tote Verbindungen ohne keepalive werden erkannt
                request.timeoutInterval = SSEConfig.idleTimeout

                do {
                    AppLog.network.info("🔌 SSE: Connecting to \(capturedTopic, privacy: .private)...")

                    let (bytes, response) = try await capturedSession.bytes(for: request)
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1

                    if statusCode != 200 {
                        bytes.task.cancel()
                        switch statusCode {
                        case 401, 403, 404:
                            // Nicht retrybar — Zugangsdaten/Topic muessen erst korrigiert werden
                            AppLog.network.error("🔌 SSE: Bad response \(statusCode, privacy: .public) for \(capturedTopic, privacy: .private) — kein erneuter Versuch")
                            await self.updateSubscriptionState(key: key, generation: generation, state: .disconnected)
                            return
                        case 429:
                            backoffSeconds = max(backoffSeconds, SSEConfig.rateLimitBackoffSeconds)
                            AppLog.network.error("🔌 SSE: Rate limit (429) for \(capturedTopic, privacy: .private), retry in \(backoffSeconds, privacy: .public)s")
                        default:
                            AppLog.network.error("🔌 SSE: Bad response \(statusCode, privacy: .public) for \(capturedTopic, privacy: .private), retry in \(backoffSeconds, privacy: .public)s")
                        }
                    } else {
                        // Verbindung erfolgreich — Backoff zuruecksetzen
                        backoffSeconds = 1
                        attempt = 0
                        if lastEventId == nil && fallbackSince == nil {
                            fallbackSince = Int(Date().timeIntervalSince1970)
                        }
                        await self.updateSubscriptionState(key: key, generation: generation, state: .connected)
                        AppLog.network.info("🔌 SSE: Connected to \(capturedTopic, privacy: .private)")

                        for try await line in bytes.lines {
                            if Task.isCancelled {
                                AppLog.network.info("🔌 SSE: Cancelled for \(capturedTopic, privacy: .private)")
                                return
                            }

                            guard line.hasPrefix("data:") else { continue }
                            let jsonString = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                            guard let data = jsonString.data(using: .utf8),
                                  let event = try? JSONDecoder().decode(NtfyMessage.self, from: data),
                                  NtfyEventType.stateChanging.contains(event.event) else {
                                // open, keepalive, poll_request oder unlesbar
                                continue
                            }

                            // Dedup nach Reconnect — bereits verarbeitete Events nicht erneut zustellen
                            if recentIdSet.contains(event.id) {
                                AppLog.network.info("🔌 SSE: Duplikat uebersprungen for \(capturedTopic, privacy: .private)")
                                continue
                            }
                            recentIds.append(event.id)
                            recentIdSet.insert(event.id)
                            if recentIds.count > SSEConfig.dedupWindow {
                                let removed = recentIds.removeFirst()
                                recentIdSet.remove(removed)
                            }

                            lastEventId = event.id
                            await self.rememberLastEventId(event.id, key: key, generation: generation)

                            switch event.event {
                            case NtfyEventType.message:
                                AppLog.network.info("🔌 SSE: Received message for \(capturedTopic, privacy: .private)")
                                await capturedOnMessage(event)
                            case NtfyEventType.messageDelete:
                                AppLog.network.info("🔌 SSE: Received delete for \(capturedTopic, privacy: .private), sequence: \(event.sequenceKey, privacy: .private)")
                                await capturedOnDelete?(event)
                            case NtfyEventType.messageClear:
                                AppLog.network.info("🔌 SSE: Received clear for \(capturedTopic, privacy: .private), sequence: \(event.sequenceKey, privacy: .private)")
                                await capturedOnClear?(event)
                            default:
                                break
                            }
                        }

                        AppLog.network.info("🔌 SSE: Stream ended for \(capturedTopic, privacy: .private), reconnecting in \(backoffSeconds, privacy: .public)s")
                    }

                } catch {
                    if Task.isCancelled { return }
                    AppLog.network.error("🔌 SSE Error for \(capturedTopic, privacy: .private): \(error.localizedDescription, privacy: .public), retry in \(backoffSeconds, privacy: .public)s")
                }

                if Task.isCancelled { return }

                // Backoff-Sleep
                attempt += 1
                await self.updateSubscriptionState(key: key, generation: generation, state: .reconnecting(attempt: attempt))
                try? await Task.sleep(for: .seconds(backoffSeconds))

                // Exponentielles Erhoehen mit Cap
                backoffSeconds = min(backoffSeconds * 2, SSEConfig.maxBackoffSeconds)
            }
        }

        activeTasks[key] = task
    }

    func unsubscribe(serverURL: String, topic: String) {
        let key = subscriptionKey(serverURL: serverURL, topic: topic)
        activeTasks[key]?.cancel()
        activeTasks.removeValue(forKey: key)
        activeConfigs.removeValue(forKey: key)
        subscriptionGenerations.removeValue(forKey: key)
        subscriptionStates.removeValue(forKey: key)
        lastEventIds.removeValue(forKey: key)
        recomputeConnectionStatus()
    }

    func unsubscribeAll() {
        for task in activeTasks.values {
            task.cancel()
        }
        activeTasks.removeAll()
        activeConfigs.removeAll()
        subscriptionGenerations.removeAll()
        subscriptionStates.removeAll()
        lastEventIds.removeAll()
        connectionStatus = .disconnected
    }

    // MARK: - Connection Status (Aggregat)

    private func subscriptionKey(serverURL: String, topic: String) -> String {
        "\(serverURL)/\(topic)"
    }

    private func updateSubscriptionState(key: String, generation: UUID, state: ConnectionStatus) {
        guard subscriptionGenerations[key] == generation else { return }
        subscriptionStates[key] = state
        recomputeConnectionStatus()
    }

    private func rememberLastEventId(_ eventId: String, key: String, generation: UUID) {
        guard subscriptionGenerations[key] == generation else { return }
        lastEventIds[key] = eventId
    }

    /// Mindestens eine Verbindung steht → connected; sonst connecting > reconnecting > disconnected.
    private func recomputeConnectionStatus() {
        let states = Array(subscriptionStates.values)
        let reconnectAttempts: [Int] = states.compactMap { state -> Int? in
            if case .reconnecting(let attempt) = state {
                return attempt
            }
            return nil
        }

        let aggregated: ConnectionStatus
        if states.contains(.connected) {
            aggregated = .connected
        } else if states.contains(.connecting) {
            aggregated = .connecting
        } else if let attempt = reconnectAttempts.min() {
            aggregated = .reconnecting(attempt: attempt)
        } else {
            aggregated = .disconnected
        }

        if connectionStatus != aggregated {
            connectionStatus = aggregated
        }
    }

    private func markAllSubscriptionsDisconnected() {
        for key in subscriptionStates.keys {
            subscriptionStates[key] = .disconnected
        }
        recomputeConnectionStatus()
    }

    // MARK: - Network Monitoring

    private var reconnectTask: Task<Void, Never>?
    nonisolated(unsafe) private var lastPathSatisfied = true

    func startNetworkMonitor() {
        pathMonitor = NWPathMonitor()
        pathMonitor?.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let isSatisfied = path.status == .satisfied

            if isSatisfied && !lastPathSatisfied {
                // Nur reconnecten wenn vorher NICHT satisfied war (echte Wiederherstellung)
                lastPathSatisfied = true
                AppLog.network.info("🔌 Network: Path restored (\(path.availableInterfaces.map(\.name).joined(separator: ", "), privacy: .public))")
                Task { @MainActor in
                    self.reconnectTask?.cancel()
                    self.reconnectTask = Task {
                        try? await Task.sleep(for: .seconds(3))
                        guard !Task.isCancelled else { return }
                        await self.reconnectAll()
                    }
                }
            } else if !isSatisfied {
                lastPathSatisfied = false
                Task { @MainActor in
                    self.markAllSubscriptionsDisconnected()
                }
            }
            // Wenn satisfied UND vorher auch satisfied → ignorieren (kein Reconnect)
        }
        pathMonitor?.start(queue: monitorQueue)
    }

    func stopNetworkMonitor() {
        pathMonitor?.cancel()
        pathMonitor = nil
    }

    func reconnectAll() async {
        AppLog.network.info("🔌 Network: Reconnecting all \(self.activeConfigs.count, privacy: .public) subscriptions")

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
        guard let url = NtfyHTTP.url(serverURL: serverURL, pathSegments: [topic, sequenceId]) else {
            throw NtfyError.invalidURL
        }

        let auth = authHeader(username: username, password: password, token: token)
        let request = createRequest(url: url, method: "DELETE", auth: auth)

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
    /// Verarbeitet alle zustandsrelevanten Events in der uebergebenen (chronologischen) Reihenfolge:
    /// - `message`: Insert, Upsert per ID, oder Update per sequence_id (ersetzt die fruehere Version)
    /// - `message_delete`: entfernt die Nachricht(en) der Sequenz aus DB und Mitteilungszentrale
    /// - `message_clear`: markiert die Nachricht(en) der Sequenz als gelesen und entfernt die Mitteilung
    /// Aufrufer sollten danach `writeWidgetData(context:)` aufrufen.
    func storeMessages(
        for topic: Topic,
        messages: [NtfyMessage],
        context: ModelContext
    ) {
        // Topic koennte inzwischen geloescht sein (z.B. Unsubscribe waehrend laufendem Refresh)
        guard !topic.isDeleted, topic.modelContext != nil else { return }

        // Vorverarbeitung: Versionen, die im selben Batch noch ersetzt oder geloescht werden,
        // gar nicht erst einfuegen (vermeidet Unread-Zaehler-Flackern bei jedem Poll).
        var lastMessageIndex: [String: Int] = [:]
        var lastDeleteIndex: [String: Int] = [:]
        for (index, event) in messages.enumerated() {
            switch event.event {
            case NtfyEventType.message:
                lastMessageIndex[event.sequenceKey] = index
            case NtfyEventType.messageDelete:
                lastDeleteIndex[event.sequenceKey] = index
            default:
                break
            }
        }

        var didChange = false

        for (index, event) in messages.enumerated() {
            let sequenceKey = event.sequenceKey

            switch event.event {
            case NtfyEventType.message:
                if let laterIndex = lastMessageIndex[sequenceKey], laterIndex > index { continue }
                if let deleteIndex = lastDeleteIndex[sequenceKey], deleteIndex > index { continue }
                if upsertMessage(event, into: topic, context: context) {
                    didChange = true
                }
            case NtfyEventType.messageDelete:
                if applyDelete(sequenceKey: sequenceKey, in: topic, context: context) {
                    didChange = true
                }
            case NtfyEventType.messageClear:
                if applyClear(sequenceKey: sequenceKey, in: topic, context: context) {
                    didChange = true
                }
            default:
                break
            }
        }

        guard didChange else { return }

        // Erst speichern, damit geloeschte Nachrichten beim Neuberechnen nicht mehr auftauchen
        try? context.save()
        refreshLastMessageInfo(for: topic, context: context)
        try? context.save()
    }

    /// Wendet ein `message`-Event an. Rueckgabe: ob sich der Bestand geaendert hat.
    private func upsertMessage(_ message: NtfyMessage, into topic: Topic, context: ModelContext) -> Bool {
        let messageId = message.id

        // 1. Check: existiert bereits?
        let existingPredicate = #Predicate<StoredMessage> { $0.messageId == messageId }
        let descriptor = FetchDescriptor(predicate: existingPredicate)

        if let existing = (try? context.fetch(descriptor))?.first(where: { !$0.isDeleted }) {
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
            return true
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
        guard (try? context.fetch(deletedDescriptor))?.isEmpty ?? true else { return false }

        // 3. Update per sequence_id: neue Nachricht ersetzt die fruehere Version derselben Sequenz
        let previousVersions = storedMessages(matching: message.sequenceKey, in: topic, context: context)
            .filter { $0.messageId != messageId }
        if let target = previousVersions.max(by: { $0.time < $1.time }) {
            // Aelteres Event (z.B. erneut gepollt) darf die neuere Version nicht ueberschreiben
            guard message.time >= target.time else { return false }

            NotificationService.shared.removeNotification(withIdentifier: target.messageId)

            target.messageId = message.id
            target.sequenceId = message.sequenceId ?? target.sequenceId
            target.time = message.time
            target.title = message.title
            target.message = message.message
            target.tags = message.tags
            target.priority = message.priority ?? 3
            target.clickURL = message.click
            target.iconURL = message.icon
            target.attachmentData = message.attachment.flatMap { try? JSONEncoder().encode(StoredAttachment(from: $0)) }
            if let actions = message.actions, !actions.isEmpty {
                target.actionsData = try? JSONEncoder().encode(actions.map { StoredAction(from: $0) })
            } else {
                target.actionsData = nil
            }
            target.receivedAt = Date()

            // Aktualisierte Nachricht gilt wieder als ungelesen
            if target.isRead {
                target.isRead = false
                topic.unreadCount += 1
            }

            // Evtl. weitere Duplikate derselben Sequenz entfernen
            for duplicate in previousVersions where duplicate !== target {
                if !duplicate.isRead {
                    topic.unreadCount = max(0, topic.unreadCount - 1)
                }
                NotificationService.shared.removeNotification(withIdentifier: duplicate.messageId)
                context.delete(duplicate)
            }
            return true
        }

        // 4. Insert
        let storedMessage = StoredMessage(from: message, topic: topic)
        context.insert(storedMessage)
        // Neue Messages sind immer ungelesen — denormalisierten Zaehler inkrementieren
        topic.unreadCount += 1
        return true
    }

    /// `message_delete`: Nachricht(en) der Sequenz aus DB und Mitteilungszentrale entfernen.
    private func applyDelete(sequenceKey: String, in topic: Topic, context: ModelContext) -> Bool {
        let matches = storedMessages(matching: sequenceKey, in: topic, context: context)
        guard !matches.isEmpty else { return false }

        for message in matches {
            if !message.isRead {
                topic.unreadCount = max(0, topic.unreadCount - 1)
            }
            NotificationService.shared.removeNotification(withIdentifier: message.messageId)
            context.delete(message)
        }
        AppLog.network.info("🗑️ Delete-Event: \(matches.count, privacy: .public) Nachricht(en) entfernt")
        return true
    }

    /// `message_clear`: Nachricht(en) der Sequenz als gelesen markieren und Mitteilung entfernen.
    /// Die Nachrichten selbst bleiben erhalten.
    private func applyClear(sequenceKey: String, in topic: Topic, context: ModelContext) -> Bool {
        let matches = storedMessages(matching: sequenceKey, in: topic, context: context)
        guard !matches.isEmpty else { return false }

        var didChange = false
        for message in matches {
            NotificationService.shared.removeNotification(withIdentifier: message.messageId)
            if !message.isRead {
                message.isRead = true
                topic.unreadCount = max(0, topic.unreadCount - 1)
                didChange = true
            }
        }
        return didChange
    }

    /// Alle gespeicherten Nachrichten dieses Topics, deren sequence_id (oder ID) dem Schluessel entspricht.
    private func storedMessages(matching sequenceKey: String, in topic: Topic, context: ModelContext) -> [StoredMessage] {
        let optionalKey: String? = sequenceKey
        let plainKey = sequenceKey
        let bySequence = FetchDescriptor(predicate: #Predicate<StoredMessage> { $0.sequenceId == optionalKey })
        let byMessageId = FetchDescriptor(predicate: #Predicate<StoredMessage> { $0.messageId == plainKey })

        let candidates = ((try? context.fetch(bySequence)) ?? []) + ((try? context.fetch(byMessageId)) ?? [])
        let topicId = topic.id

        var seen = Set<PersistentIdentifier>()
        var result: [StoredMessage] = []
        for candidate in candidates where !candidate.isDeleted {
            guard candidate.topic?.id == topicId else { continue }
            if seen.insert(candidate.persistentModelID).inserted {
                result.append(candidate)
            }
        }
        return result
    }

    /// Denormalisierte Topic-Properties (Zeit/Preview/Prioritaet/Icon) aus der neuesten gespeicherten Nachricht.
    private func refreshLastMessageInfo(for topic: Topic, context: ModelContext) {
        guard !topic.isDeleted, topic.modelContext != nil else { return }
        let topicId = topic.id
        var descriptor = FetchDescriptor<StoredMessage>(
            predicate: #Predicate<StoredMessage> { $0.topic?.id == topicId },
            sortBy: [SortDescriptor(\.time, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        guard let latest = (try? context.fetch(descriptor))?.first else {
            // Keine Nachrichten mehr — Preview leeren, Sortierzeitpunkt beibehalten
            topic.lastMessagePreview = nil
            topic.lastMessagePriority = 3
            topic.lastMessageIconURL = nil
            return
        }

        topic.lastMessageAt = latest.date
        topic.lastMessagePreview = latest.message ?? latest.title
        topic.lastMessagePriority = latest.priority
        topic.lastMessageIconURL = latest.iconURL
    }

    // MARK: - Cleanup

    /// Loescht DeletedMessage-Records aelter als 7 Tage.
    func cleanupDeletedMessages(context: ModelContext) {
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        let predicate = #Predicate<DeletedMessage> { $0.deletedAt < cutoff }
        let descriptor = FetchDescriptor(predicate: predicate)
        let stale = (try? context.fetch(descriptor)) ?? []
        for record in stale {
            context.delete(record)
        }
        if !stale.isEmpty {
            try? context.save()
            AppLog.network.info("🔄 Cleanup: deleted \(stale.count, privacy: .public) expired DeletedMessage records")
        }
    }

    /// Loescht StoredMessages aelter als die konfigurierte Retention.
    /// Dekrementiert topic.unreadCount fuer noch ungelesene Messages.
    func cleanupOldMessages(context: ModelContext) {
        let retentionDays = AppSettings.messageRetentionDays
        guard retentionDays != -1 else { return }

        let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 24 * 3600)
        let cutoffTimestamp = Int(cutoff.timeIntervalSince1970)

        let predicate = #Predicate<StoredMessage> { $0.time < cutoffTimestamp }
        let descriptor = FetchDescriptor(predicate: predicate)
        let old = (try? context.fetch(descriptor)) ?? []

        for message in old {
            if !message.isRead, let topic = message.topic {
                topic.unreadCount = max(0, topic.unreadCount - 1)
            }
            context.delete(message)
        }

        if !old.isEmpty {
            try? context.save()
            AppLog.network.info("🔄 Cleanup: deleted \(old.count, privacy: .public) messages older than \(retentionDays, privacy: .public) days")
        }
    }

    // MARK: - Refresh Topics

    /// Fetcht Events fuer alle Topics PARALLEL via TaskGroup und wendet sie via storeMessages an
    /// (inkl. message_delete/message_clear, damit Loeschungen auch beim Polling ankommen).
    /// Ersetzt ContentView.refreshAllTopics() und TopicsView.refreshAllTopics().
    /// Netzwerk-Requests laufen parallel, Ergebnisse werden sequentiell auf @MainActor gespeichert.
    func refreshTopics(
        _ topics: [Topic],
        context: ModelContext,
        since: String
    ) async {
        AppLog.network.info("🔄 Starting parallel refresh for \(topics.count, privacy: .public) topics (since: \(since, privacy: .public))")

        // Cleanup abgelaufener Records vor dem Refresh
        cleanupDeletedMessages(context: context)
        cleanupOldMessages(context: context)

        // Sendable Struktur fuer Fetch-Ergebnisse
        struct FetchResult: Sendable {
            let serverURL: String
            let topicName: String
            let events: [NtfyMessage]
        }

        // Bereits geloeschte Topics nicht anfassen (Zugriff auf Properties wuerde crashen)
        let liveTopics = topics.filter { !$0.isDeleted && $0.modelContext != nil }

        // Phase 1: Parallele Netzwerk-Requests — nur Sendable-Werte capturen
        let results: [FetchResult] = await withTaskGroup(of: FetchResult?.self) { group in
            for topic in liveTopics {
                let serverURL = topic.serverURL
                let topicName = topic.name
                let token = KeychainManager.shared.loadToken(serverURL: serverURL)
                let credentials = KeychainManager.shared.loadCredentials(serverURL: serverURL)

                group.addTask { [weak self] in
                    guard let self else { return nil }
                    do {
                        let events = try await self.fetchEvents(
                            serverURL: serverURL,
                            topic: topicName,
                            since: since,
                            username: credentials?.username,
                            password: credentials?.password,
                            token: token
                        )
                        AppLog.network.info("🔄 Fetched \(events.count, privacy: .public) events for \(topicName, privacy: .private)")
                        return FetchResult(serverURL: serverURL, topicName: topicName, events: events)
                    } catch {
                        AppLog.network.error("❌ Failed to refresh topic \(topicName, privacy: .private): \(error.localizedDescription, privacy: .public)")
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
            // Topic koennte waehrend der Requests entfernt worden sein — erneut pruefen
            if let topic = liveTopics.first(where: {
                !$0.isDeleted && $0.modelContext != nil &&
                $0.serverURL == result.serverURL && $0.name == result.topicName
            }) {
                storeMessages(for: topic, messages: result.events, context: context)
            }
        }

        writeWidgetData(context: context)
        AppLog.network.info("✅ Parallel refresh complete")
    }

    // MARK: - Test Authentication

    func testAuth(
        serverURL: String,
        topic: String,
        username: String?,
        password: String?,
        token: String?
    ) async throws -> Bool {
        guard let url = NtfyHTTP.url(serverURL: serverURL, pathSegments: [topic, "auth"]) else {
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

    // MARK: - Widget Data

    /// Schreibt die letzten 10 ungelesenen Nachrichten aller Topics als JSON
    /// in den App Group Container, damit das WidgetKit-Extension sie lesen kann.
    /// Wird nach jedem storeMessages()-Aufruf aufgerufen.
    func writeWidgetData(context: ModelContext) {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.de.godsapp.ntfy"
        ) else {
            AppLog.network.error("❌ Widget: App Group Container nicht erreichbar")
            return
        }

        let fileURL = containerURL.appendingPathComponent("widget_data.json")

        // Alle ungelesenen StoredMessages laden, nach Zeit absteigend, max 10
        var descriptor = FetchDescriptor<StoredMessage>(
            predicate: #Predicate<StoredMessage> { !$0.isRead },
            sortBy: [SortDescriptor(\.time, order: .reverse)]
        )
        descriptor.fetchLimit = 10

        let messages = (try? context.fetch(descriptor)) ?? []

        let entries: [[String: Any]] = messages.compactMap { msg in
            guard let topic = msg.topic else { return nil }
            return [
                "messageId": msg.messageId,
                "topic": topic.name,
                "title": msg.title ?? "",
                "message": msg.message ?? "",
                "time": msg.time,
                "priority": msg.priority
            ]
        }

        guard let data = try? JSONSerialization.data(withJSONObject: entries) else { return }
        try? data.write(to: fileURL, options: .atomic)

        // Widget-Timeline invalidieren
        WidgetCenter.shared.reloadAllTimelines()
        AppLog.network.info("✅ Widget: \(entries.count, privacy: .public) ungelesene Nachrichten in widget_data.json geschrieben")
    }
}
