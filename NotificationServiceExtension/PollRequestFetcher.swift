import Foundation
import os.log

private let logger = Logger(subsystem: "de.godsapp.ntfy.NotificationServiceExtension", category: "PollRequest")

// MARK: - PollRequestFetcher
//
// Bei Topics ohne anonymen Lesezugriff schickt der ntfy-Server statt des Inhalts ein
// "poll_request" (Platzhalter "New message" + poll_id). Der echte Inhalt wird hier per
// GET <server>/<topic>/json?poll=1&id=<poll_id> mit den Zugangsdaten aus der geteilten
// Keychain abgerufen. Ist das Topic auf mehreren Servern abonniert, werden diese der
// Reihe nach probiert, bis einer die Nachricht liefert.

final class PollRequestFetcher {
    struct Result {
        let serverURL: String
        let message: [String: Any]
    }

    private let session: URLSession
    private let lock = NSLock()
    private var currentTask: URLSessionDataTask?
    private var isCancelled = false

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 10
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    /// Ruft die Nachricht ab. `completion` wird genau einmal aufgerufen
    /// (auf einer Hintergrund-Queue), mit nil bei Fehler/Timeout/Abbruch.
    func fetch(topic: String,
               pollId: String,
               servers: [String],
               deadline: Date,
               completion: @escaping (Result?) -> Void) {
        fetchNext(topic: topic, pollId: pollId, servers: servers[...], deadline: deadline, completion: completion)
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let task = currentTask
        lock.unlock()
        task?.cancel()
    }

    private var cancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCancelled
    }

    private func fetchNext(topic: String,
                           pollId: String,
                           servers: ArraySlice<String>,
                           deadline: Date,
                           completion: @escaping (Result?) -> Void) {
        guard let serverURL = servers.first, !cancelled, Date() < deadline else {
            session.finishTasksAndInvalidate()
            completion(nil)
            return
        }
        let remaining = servers.dropFirst()

        guard let request = makeRequest(serverURL: serverURL, topic: topic, pollId: pollId) else {
            logger.error("poll_request: ungueltige Server-URL")
            fetchNext(topic: topic, pollId: pollId, servers: remaining, deadline: deadline, completion: completion)
            return
        }

        let task = session.dataTask(with: request) { data, response, error in
            if let error {
                logger.error("poll_request fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            } else if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                logger.error("poll_request: HTTP \(httpResponse.statusCode, privacy: .public)")
            } else if let data, let message = Self.parseMessage(data: data, pollId: pollId) {
                self.session.finishTasksAndInvalidate()
                completion(Result(serverURL: serverURL, message: message))
                return
            } else {
                logger.error("poll_request: keine passende Nachricht in der Antwort")
            }
            self.fetchNext(topic: topic, pollId: pollId, servers: remaining, deadline: deadline, completion: completion)
        }

        lock.lock()
        currentTask = task
        lock.unlock()
        task.resume()
    }

    private func makeRequest(serverURL: String, topic: String, pollId: String) -> URLRequest? {
        var base = serverURL
        while base.hasSuffix("/") {
            base.removeLast()
        }
        guard let baseURL = URL(string: base),
              baseURL.scheme == "https" || baseURL.scheme == "http" else {
            return nil
        }
        let topicURL = baseURL.appendingPathComponent(topic).appendingPathComponent("json")
        guard var components = URLComponents(url: topicURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "poll", value: "1"),
            URLQueryItem(name: "id", value: pollId)
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Gleiche Reihenfolge wie NtfyService.authHeader: Token vor Basic-Auth.
        // Keychain-Keys verwenden die unveraenderte serverURL (wie in der App).
        if let token = SharedKeychain.loadToken(serverURL: serverURL), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else if let credentials = SharedKeychain.loadCredentials(serverURL: serverURL),
                  !credentials.username.isEmpty,
                  let data = "\(credentials.username):\(credentials.password)".data(using: .utf8) {
            request.setValue("Basic \(data.base64EncodedString())", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    /// Antwort ist newline-delimited JSON. Bevorzugt die Nachricht mit der poll_id,
    /// sonst die erste "message".
    private static func parseMessage(data: Data, pollId: String) -> [String: Any]? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        var firstMessage: [String: Any]?
        for line in text.split(separator: "\n") {
            guard let lineData = String(line).data(using: .utf8),
                  let object = (try? JSONSerialization.jsonObject(with: lineData)) as? [String: Any],
                  object["event"] as? String == "message" else {
                continue
            }
            if object["id"] as? String == pollId {
                return object
            }
            if firstMessage == nil {
                firstMessage = object
            }
        }
        return firstMessage
    }
}
