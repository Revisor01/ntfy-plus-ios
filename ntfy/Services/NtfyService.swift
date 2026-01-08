import Foundation
import Observation

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
        onMessage: @escaping @MainActor (NtfyMessage) -> Void
    ) {
        let key = "\(serverURL)/\(topic)"

        // Cancel existing subscription
        activeTasks[key]?.cancel()

        let task = Task.detached { [weak self] in
            guard let self else { return }

            let urlString = "\(serverURL)/\(topic)/sse"
            guard let url = URL(string: urlString) else { return }

            let auth = await self.authHeader(username: username, password: password, token: token)
            var request = await self.createRequest(url: url, auth: auth)
            request.timeoutInterval = TimeInterval.infinity

            do {
                let (bytes, response) = try await self.session.bytes(for: request)

                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    return
                }

                for try await line in bytes.lines {
                    if Task.isCancelled { break }

                    if line.hasPrefix("data: ") {
                        let jsonString = String(line.dropFirst(6))
                        if let data = jsonString.data(using: .utf8),
                           let message = try? JSONDecoder().decode(NtfyMessage.self, from: data),
                           message.event == "message" {
                            await onMessage(message)
                        }
                    }
                }
            } catch {
                if !Task.isCancelled {
                    print("SSE Error: \(error)")
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
