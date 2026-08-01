# Changelog

Alle nennenswerten Änderungen an diesem Projekt werden in dieser Datei dokumentiert.

Das Format basiert auf [Keep a Changelog 1.1.0](https://keepachangelog.com/de/1.1.0/),
und dieses Projekt folgt [Semantic Versioning 2.0.0](https://semver.org/lang/de/).

## [Unreleased]

### Fixed

- SwiftData: DB-Reset löscht jetzt alle Store-Dateien, Unsubscribe-Lifecycle korrigiert,
  `markAllAsRead` markiert nur die gefilterten Nachrichten, Credential-Speicherung
  funktioniert auch mit dem Default-Server
- UI: Icon wird bei Farbwahl nicht mehr ungewollt zurückgesetzt, Bild-Recycling in
  `CachedAsyncImage` durch URL-Tracking behoben, Widget-Deep-Links mit Sonderzeichen
  werden prozent-kodiert, Hash-Overflow (`Int.min`) in Cache und Topic-Farbgenerierung behoben
- Wirkungslose Custom-Sound-Auswahl aus den Topic-Einstellungen entfernt

### Security

- Strukturiertes Logging über `os.Logger` mit Privacy-Redaction statt `print()`
- Keychain-Einträge auf `ThisDeviceOnly` umgestellt, inklusive Migration bestehender Einträge

## [2.0.0] - 2026-07-29

Erste über TestFlight ausgelieferte Version (Build 6).

### Added

- **Home-Screen-Widget** (`NtfyWidget`) mit Deep-Link-Unterstützung über das URL-Schema `ntfy://`
- **iPad-Layout**: `NavigationSplitView` mit Zwei-Spalten-Darstellung
- **Biometrische Sperre** (Face ID / Touch ID) mit Verzögerung nach Hintergrundwechsel
- **Nachrichten favorisieren** (Stern) und **Live-Suche** in der Nachrichtenansicht
- **Topic-Anpassung**: eigene Sounds, Standard-Priorität, Icons und Farben pro Topic,
  synchronisiert in die App Group
- **Erweiterte Publish-Optionen**: Anhang-URL, verzögerte Zustellung, E-Mail-Weiterleitung,
  Markdown-Umschalter
- **Interaktive Notification-Actions** auch im Push-Pfad (`MARK_READ`, `REPLY`, `OPEN_URL`, Copy)
- **Disk-Cache für Bild-Anhänge** inkl. Anzeige der Cache-Größe und gezieltem Leeren
  in den Einstellungen
- **Ablauf-Anzeige für Anhänge** anhand der Expiry-Information signierter URLs
- **Verbindungsstatus-Indikator** und automatischer SSE-Reconnect mit Backoff und
  Netzwerküberwachung (`NWPathMonitor`)
- Aufbewahrungsdauer für Nachrichten und Cleanup gelöschter Nachrichten
- Haptisches Feedback für Swipe-Actions und Stern-Umschalter

### Changed

- SwiftData-Schema mehrfach erweitert (V1 → V4) und anschließend auf ein einzelnes
  `NtfySchema` ohne Migrationsplan vereinfacht
- `storeMessages` und `refreshTopics` zentral in `NtfyService` zusammengeführt
- Denormalisierte Topic-Eigenschaften ersetzen die Query in `TopicRow`
- URL-Normalisierung zentralisiert, Default-Server auf `push.godsapp.de` gesetzt
- APNs auf Production umgestellt für die TestFlight-Auslieferung

### Fixed

- Crash bei identischen Model-Referenzen im Migrationsplan
- `ModelContainer`-`fatalError` durch eine Fehler-UI ersetzt, force-unwrapped URL abgesichert
- Grayscale-Crash in `Color.toHex()`
- Face ID greift nur nach echtem Hintergrundwechsel (> 5 s), nicht bei jedem Fokusverlust
- Reconnect-Debounce (2 s) gegen 429-Rate-Limiting des Servers
- Widget-Daten werden einmal nach vollständigem Refresh geschrieben statt einmal pro Topic
- Sound-Vorschau und Notification-Sound spielen wieder korrekt ab

### Removed

- Tote Delegate-Extension entfernt

### Security

- Bestätigungsdialog vor dem Ausführen von HTTP-Actions
- FCM-Token in die Keychain migriert
- Härtung von `openURL` durch Validierung des URL-Schemas

### Bekannte Einschränkung

- Das `NtfyWidget`-Target wurde direkt in `project.pbxproj` eingetragen, nicht über die
  Xcode-UI. Falls Xcode Probleme mit dem Widget-Target meldet, das Target in Xcode neu
  anlegen statt die pbxproj weiter von Hand zu editieren.

## [1.0.0] - 2026-01-09

Erste Version.

### Added

- Abonnieren von Topics auf ntfy.sh oder einem selbst gehosteten ntfy-Server
- Echtzeit-Benachrichtigungen über SSE sowie Push über Firebase Cloud Messaging
- Authentifizierung per Benutzername/Passwort oder Access Token, gespeichert in der Keychain
- Lokale Speicherung von Nachrichten über SwiftData
- Anzeige von App-Icons aus Nachrichten, Prioritäts-Badges, Dark Mode
- Notification Service Extension für Badge-Zählung und Aufbereitung eingehender Pushes

[Unreleased]: https://github.com/Revisor01/ntfy-plus-ios/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/Revisor01/ntfy-plus-ios/compare/v1.0...v2.0.0
[1.0.0]: https://github.com/Revisor01/ntfy-plus-ios/releases/tag/v1.0
