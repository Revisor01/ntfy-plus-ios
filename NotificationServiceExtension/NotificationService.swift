import Foundation
import UserNotifications
import os.log

private let logger = Logger(subsystem: "de.godsapp.ntfy.NotificationServiceExtension", category: "NotificationService")

class NotificationService: UNNotificationServiceExtension {

    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    /// Schuetzt contentHandler-Aufruf und Content-Mutation gegen den Wettlauf zwischen
    /// Netzwerk-Callback (poll_request) und serviceExtensionTimeWillExpire.
    private let deliveryLock = NSLock()
    private var hasDelivered = false
    private var pollFetcher: PollRequestFetcher?

    /// Die NSE hat ca. 30 s; danach greift serviceExtensionTimeWillExpire.
    private let pollBudget: TimeInterval = 22

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        logger.info("🔔 NotificationServiceExtension didReceive called")

        self.contentHandler = contentHandler
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
            logger.error("🔔 Could not create mutable content")
            hasDelivered = true
            contentHandler(request.content)
            return
        }
        bestAttemptContent = content

        let payload = PushPayload(userInfo: request.content.userInfo)
        let topic = payload.topic

        // message_delete/message_clear u.ae.: keine neue Nachricht — kein Badge,
        // zugehoerige Mitteilung entfernen und moeglichst nichts anzeigen
        if payload.event != "message" && payload.event != "poll_request" {
            handleNonMessageEvent(payload)
            return
        }

        // Subtitle (Topic) entfernen
        content.subtitle = ""

        // Category für interaktive Actions (Als gelesen / Antworten / Link öffnen)
        // auch bei Push-Notifications sichtbar machen — sonst nur bei lokalen Notifications
        content.categoryIdentifier = "NTFY_MESSAGE"

        // Thread identifier für Topic-Gruppierung (GROUP-01)
        if !topic.isEmpty {
            content.threadIdentifier = topic
            if content.title.isEmpty {
                content.title = topic
            }
        }

        PriorityStyle.apply(priority: payload.priority, to: content)

        // Badge aus dem geteilten Zaehler (die App schreibt dort den massgeblichen Stand)
        let newBadge = SharedStore.incrementBadgeCount()
        content.badge = NSNumber(value: newBadge)

        let servers = topic.isEmpty ? [] : SharedStore.servers(for: topic)

        if payload.event == "poll_request" {
            // Englischen Server-Platzhalter ("New message") eindeutschen, falls der Abruf scheitert
            if content.body.isEmpty || content.body == "New message" {
                content.body = "Neue Nachricht"
            }

            // Nur die poll_id ist die ID der eigentlichen Nachricht (die eigene id gehoert zum poll_request)
            guard let pollId = payload.pollId, !topic.isEmpty, !servers.isEmpty else {
                logger.error("🔔 poll_request ohne Topic/poll_id/bekannten Server — Platzhalter bleibt")
                deliver()
                return
            }

            let fetcher = PollRequestFetcher()
            pollFetcher = fetcher
            fetcher.fetch(topic: topic,
                          pollId: pollId,
                          servers: servers,
                          deadline: Date().addingTimeInterval(pollBudget)) { [weak self] result in
                guard let self else { return }
                guard let result else {
                    logger.error("🔔 poll_request konnte nicht aufgeloest werden — Platzhalter bleibt")
                    self.deliver()
                    return
                }
                // Auch wenn die Zeit bereits abgelaufen ist: App bekommt die Nachricht trotzdem
                SharedStore.writePendingMessage(result.message, serverURL: result.serverURL)
                self.deliver { content in
                    NotificationService.applyResolvedMessage(result.message, serverURL: result.serverURL, topic: topic, to: content)
                }
                logger.info("🔔 poll_request aufgeloest, badge: \(newBadge, privacy: .public)")
            }
            return
        }

        // Normaler "message"-Push: Inhalt ist bereits im Payload
        let serverURL = servers.count == 1 ? servers.first : nil
        if let message = payload.messageDictionary() {
            SharedStore.writePendingMessage(message, serverURL: serverURL)
        }
        if let serverURL {
            content.userInfo["serverURL"] = serverURL
        }

        logger.info("🔔 Removed subtitle, badge: \(newBadge, privacy: .public), delivering notification")
        deliver()
    }

    override func serviceExtensionTimeWillExpire() {
        logger.error("🔔 serviceExtensionTimeWillExpire — liefere best attempt")
        pollFetcher?.cancel()
        deliver()
    }

    // MARK: - Nicht-Nachrichten-Events

    /// Fuer Events ohne neue Nachricht (z.B. message_delete/message_clear, falls als
    /// Alert zugestellt): Badge nicht erhoehen, die zugestellte Mitteilung der Sequenz
    /// entfernen und einen leeren Inhalt liefern. Ohne das Filtering-Entitlement kann
    /// die NSE die Anzeige nicht garantiert unterdruecken.
    private func handleNonMessageEvent(_ payload: PushPayload) {
        logger.info("🔔 Event \(payload.event, privacy: .public) — keine neue Nachricht, kein Badge")
        bestAttemptContent = UNMutableNotificationContent()

        guard let targetKey = payload.nonEmpty("sequence_id") ?? payload.id else {
            deliver()
            return
        }

        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { [weak self] notifications in
            let identifiers = notifications.compactMap { notification -> String? in
                let userInfo = notification.request.content.userInfo
                let id = userInfo["id"] as? String
                let sequenceId = userInfo["sequence_id"] as? String
                return (id == targetKey || sequenceId == targetKey) ? notification.request.identifier : nil
            }
            if !identifiers.isEmpty {
                center.removeDeliveredNotifications(withIdentifiers: identifiers)
            }
            self?.deliver()
        }
    }

    // MARK: - Delivery

    /// Ruft den contentHandler genau einmal auf; `update` mutiert den Content vorher
    /// unter demselben Lock (nur wenn noch nicht ausgeliefert).
    private func deliver(_ update: ((UNMutableNotificationContent) -> Void)? = nil) {
        deliveryLock.lock()
        guard !hasDelivered, let handler = contentHandler, let content = bestAttemptContent else {
            deliveryLock.unlock()
            return
        }
        hasDelivered = true
        update?(content)
        deliveryLock.unlock()
        handler(content)
    }

    /// Ersetzt den poll_request-Platzhalter durch die abgerufene Nachricht und setzt
    /// die userInfo-Felder, die AppDelegate (Tap, MARK_READ, REPLY, OPEN_URL) erwartet.
    private static func applyResolvedMessage(_ message: [String: Any],
                                             serverURL: String,
                                             topic: String,
                                             to content: UNMutableNotificationContent) {
        let title = (message["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? topic
        content.title = title

        if let body = message["message"] as? String, !body.isEmpty {
            content.body = body
        } else if let attachment = message["attachment"] as? [String: Any],
                  let name = attachment["name"] as? String, !name.isEmpty {
            content.body = name
        }

        let priority = (message["priority"] as? NSNumber)?.intValue
        PriorityStyle.apply(priority: priority, to: content)

        var userInfo = content.userInfo
        userInfo["event"] = "message"
        userInfo["topic"] = topic
        userInfo["serverURL"] = serverURL
        if let id = message["id"] as? String {
            userInfo["id"] = id
        }
        // Fuer das Entfernen per message_delete/message_clear (Ziel = sequence_id)
        if let sequenceId = message["sequence_id"] as? String, !sequenceId.isEmpty {
            userInfo["sequence_id"] = sequenceId
        }
        if let click = message["click"] as? String, !click.isEmpty {
            userInfo["click"] = click
        }
        if let messageTitle = message["title"] as? String {
            userInfo["title"] = messageTitle
        }
        if let body = message["message"] as? String {
            userInfo["message"] = body
        }
        if let priority {
            userInfo["priority"] = String(priority)
        }
        content.userInfo = userInfo
    }
}
