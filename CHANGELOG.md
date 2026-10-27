# Changelog

Alle nennenswerten Änderungen an diesem Projekt werden in dieser Datei dokumentiert.

Das Format basiert auf [Keep a Changelog 1.1.0](https://keepachangelog.com/de/1.1.0/),
und dieses Projekt folgt [Semantic Versioning 2.0.0](https://semver.org/lang/de/).

## [Unreleased]

### Geändert
- Neue Lizenz: GNU AGPL v3.0 statt GPL-3.0: Die Pflicht, Änderungen offenzulegen, gilt jetzt auch für den Betrieb als Webdienst.

### Behoben
- Die App meldet sich jetzt als deutschsprachig; Datumsauswahl und Systemknöpfe erscheinen auf Deutsch, der App Store nennt Deutsch als Sprache.

### Sonstiges

- Release-Builds entstehen in Xcode Cloud; der Release-Knopf auf GitHub startet sie und wartet darauf.
- Automatische Tests prüfen jetzt bei jeder Änderung, ob Nachrichten, Prioritäten, Tags und Eingaben richtig verarbeitet werden.
- README, Vorlagen und Hinweise gibt es nur noch auf Deutsch.

## [2.2.0] - 2026-10-25

iOS 27 als Mindestversion, neue Sende- und Push-Funktionen. Build 8.

### Hinzugefügt

- **Anhänge senden**: Fotos (PhotosPicker) und Dateien bis 15 MB direkt aus der App
  hochladen (`PUT /<topic>`, Nachricht/Titel/Priorität/Tags als Parameter)
- **Zustellzeitpunkt per Datumsauswahl** beim Senden (RFC 3339 + Zeitzone, max. 3 Tage)
- **Bild-Anhänge als Vorschau in Push-Mitteilungen** (bis 10 MB, auch bei geschützten Topics)
- Stummgeschaltete Topics werden auch per Push lautlos zugestellt
- Actions mit `clear=true` markieren die Nachricht als gelesen und entfernen die Mitteilung
- HTTP-Actions: Bestätigungsdialog mit Methode, Ziel, Header-Namen und Body-Vorschau;
  anschließend Erfolgs- oder Fehlermeldung
- Tap auf eine Mitteilung beim Kaltstart öffnet das Topic (nach dem Entsperren)
- CodeQL-Analyse läuft wieder (neuer Workflow-Pfad), Dependabot auch für Swift-Pakete

### Geändert

- **Mindestversion iOS 27.0** für App, Notification Service Extension und Widget
  (vorher iOS 26 bzw. 17); alle Targets in Swift 6; Build mit Xcode 27
- Markdown wird nur noch bei als Markdown gesendeten Nachrichten formatiert
  (`content_type`, wie upstream ntfy); bereits gespeicherte Nachrichten bleiben formatiert
- Geschützte Anhänge und Icons des eigenen Servers werden mit Anmeldung geladen;
  Größenlimits für Icons (2 MB) und Anhänge (15 MB); keine Zugangsdaten an fremde Hosts
- Widget zeigt die tatsächliche Zahl ungelesener Nachrichten statt höchstens 10
- Mitteilungs-Schalter in den Einstellungen zeigt den echten iOS-Berechtigungsstatus
- Kopieren übernimmt Titel, Nachricht und Zeitstempel
- iPad: App-Sperre und Sichtschutz gelten für alle Fenster; Entsperren gilt app-weit
- `Package.resolved` ist eingecheckt (reproduzierbare Builds)

### Behoben

- Abgelaufene Anhänge werden als „Anhang abgelaufen" angezeigt statt fehlzuschlagen
- Gekürzte Poll-Antworten des Servers (`X-Messages-Truncated`) werden protokolliert

### Hinweise für den Build

- Xcode 27 erforderlich (Deployment Target iOS 27.0)
- Weiterhin: Keychain Sharing (`de.godsapp.ntfy`) im NSE-Target prüfen

## [2.1.0] - 2026-10-25

Abgleich mit ntfy-Server v2.28–v2.34 und der offiziellen iOS-App 1.8.0, plus Behebung
der Befunde aus einem vollständigen Code-Audit. Build 7.

### Hinzugefügt

- **Geschützte Topics per Push**: Die Notification Service Extension löst `poll_request`-Pushes
  auf und lädt den echten Nachrichteninhalt nach (`GET /<topic>/json?poll=1&id=…`, mit
  Zugangsdaten aus der geteilten Keychain). Bisher erschien nur ein Platzhalter.
- Push-Nachrichten werden in der App Group zwischengespeichert und beim Öffnen der App
  in die Historie übernommen — auch dann, wenn der Server-Cache inzwischen abgelaufen ist
- Nachrichten-Updates, „gelesen" und Löschen über `sequence_id` (ntfy-Update-/Clear-/Delete-API),
  live per SSE und beim Nachladen
- Priorität aus Pushes wird ausgewertet: 1 = still, 5 = zeitkritisch
- Sichtschutz im App-Switcher, wenn die App-Sperre aktiv ist
- App-Sperre mit Gerätecode-Fallback; Hinweis und Ausweg, wenn kein Code gesetzt ist
- Bestätigungsdialog beim Löschen eines Servers
- Prüfung von Topic-Namen (`A–Z a–z 0–9 - _`, max. 64 Zeichen), Server-URLs und doppelten Abos
- Lokale Server im LAN per `http://` (`NSAllowsLocalNetworking`)
- Eigener CI-Build-Workflow für Pull Requests, Dependabot für GitHub Actions

### Geändert

- Senden über die ntfy-JSON-API statt HTTP-Header — Umlaute und Emoji in Titel und Tags
  kommen korrekt an; Fehlermeldungen des Servers werden angezeigt; Limits für Titel (1 KB)
  und Tags (512 B) werden vorab geprüft
- SSE: eigene Verbindung ohne 5-Minuten-Abbruch, Reconnect mit `since=<letzte ID>` (ntfy ≥ 2.31)
  und Duplikatfilter, Wiederholung mit Backoff bei 429/5xx statt dauerhaftem Abbruch,
  gemeinsamer Verbindungsstatus über alle Topics
- Antworten aus der Mitteilung gehen an den Server des Topics (vorher immer an den
  Standard-Server) und werden auch im Hintergrund zuverlässig gesendet
- „Als gelesen" aus der Mitteilung wirkt auch, wenn die App nicht geöffnet ist
- FCM-Abos mit Referenzzählung: gleichnamige Topics auf verschiedenen Servern stören sich nicht mehr
- Teilen über `ShareLink`; Datums-Formatter werden zwischengespeichert; Nachrichtenliste filtert
  einmal pro Render statt pro Zeile
- Bedienungshilfen: Beschriftungen für Symbol-Buttons, Farb- und Icon-Auswahl per VoiceOver bedienbar
- Firebase iOS SDK 12.7 → 13.1.1 (benötigt Xcode 26.2+), `actions/checkout` v4 → v7

### Behoben

- **Datenverlust**: Ein `message_clear`-Event löschte die gesamte lokale Historie des Topics
- `message_delete` vom Server wurde nie angewendet (falsche ID); Updates erzeugten Duplikate
- Absturz auf dem iPad beim Teilen einer Nachricht und beim Abbestellen des angezeigten Topics
- iPad: Detailansicht übernahm Titel/Suche des vorherigen Topics
- Server-URL bearbeiten löschte Zugangsdaten unter der falschen URL; Topics verloren die Anmeldung
- Neuer Server mit „Standard"-Schalter wurde sofort wieder Nicht-Standard
- „Alle Nachrichten löschen" ließ Ungelesen-Zähler und Vorschau stehen
- Onboarding: doppelter Server bei Doppeltipp, 5xx galt als erfolgreicher Test, Dark Mode unlesbar
- Ungelesen-Zähler, Badge und Widget liefen bei Löschen/Gelesen auseinander
- Polling-Fehler (400/429) wurden verschluckt
- App-Sperre verdeckte geöffnete Sheets und Dialoge nicht — Sperrbildschirm und Sichtschutz
  liegen jetzt in einem eigenen Fenster; Face ID startet erst bei aktiver App
- Hinter der App-Sperre wurden Nachrichten als gelesen markiert; gesperrte Inhalte sind für
  VoiceOver ausgeblendet
- Änderung von Server-URL oder Zugangsdaten baut Live-Verbindung und Push-Zuordnung sofort neu auf
- Topic entfernen meldet das Push-Abo zuverlässig ab
- App-Symbol zeigt beim Öffnen die Zahl ungelesener Nachrichten statt 0
- Gelesene oder gelöschte Nachrichten entfernen auch die zugehörige Mitteilung
- Gekürzte Push-Inhalte überschreiben keine vollständig empfangenen Nachrichten mehr
- `poll_request` zeigt nie eine falsche Nachricht an; Lösch-/Clear-Pushes erhöhen das Badge nicht
- Live-Verbindung wird beim Zurückkehren in die App sofort neu aufgebaut; keine Reconnect-Schleife
  bei Servern, die den Stream sofort schließen
- Widget aktualisiert sich nach „Als gelesen", Löschen und eingegangenen Pushes
- Keine doppelte Anfrage der Mitteilungs-Berechtigung mehr
- SwiftData: DB-Reset-Pfade, Unsubscribe-Lifecycle, `markAllAsRead`, Credential-Speicherung
  mit Default-Server
- UI: Icon-Reset bei Farbwahl, Bild-Recycling in `CachedAsyncImage`, Widget-Deep-Links mit
  Sonderzeichen, Hash-Overflow (`Int.min`)
- Wirkungslose Custom-Sound-Auswahl entfernt

### Entfernt

- Ungenutzte Background-Modes `fetch`/`processing`, `.provisional`-Autorisierung und toter
  Code für lokale Benachrichtigungen (inkl. `.defaultCritical` ohne Entitlement)

### Sicherheit

- Deep Links (`ntfy://topic/…`) hoben die Face-ID-Sperre auf — das Ziel wird jetzt erst nach
  dem Entsperren geöffnet
- Markdown-Links in Nachrichten und Tippen auf Mitteilungen öffnen nur noch `http`/`https`
  (vorher z. B. auch `shortcuts://`, `tel:`)
- `Authorization`-Header wird bei Redirects auf fremde Hosts entfernt
- Topic-Namen werden in URLs kodiert, sodass sie den Pfad nicht verändern können
- Keychain in geteilter Access-Group für App und Extension (`ThisDeviceOnly`), mit Migration
- Strukturiertes Logging über `os.Logger` mit Privacy-Redaction statt `print()`

### Hinweise für den Build

- Xcode 26.2 oder neuer (Firebase 13)
- NSE-Target → *Signing & Capabilities* → **Keychain Sharing** mit Group `de.godsapp.ntfy` prüfen
  (Entitlement ist eingetragen), ggf. Provisioning-Profile neu erzeugen
- Nach dem Update die App einmal öffnen, damit die Topic→Server-Zuordnung für Pushes befüllt wird

## [2.0.0] - 2026-07-29

Erste über TestFlight ausgelieferte Version (Build 6).

### Hinzugefügt

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

### Geändert

- SwiftData-Schema mehrfach erweitert (V1 → V4) und anschließend auf ein einzelnes
  `NtfySchema` ohne Migrationsplan vereinfacht
- `storeMessages` und `refreshTopics` zentral in `NtfyService` zusammengeführt
- Denormalisierte Topic-Eigenschaften ersetzen die Query in `TopicRow`
- URL-Normalisierung zentralisiert, Default-Server auf `push.godsapp.de` gesetzt
- APNs auf Production umgestellt für die TestFlight-Auslieferung

### Behoben

- Crash bei identischen Model-Referenzen im Migrationsplan
- `ModelContainer`-`fatalError` durch eine Fehler-UI ersetzt, force-unwrapped URL abgesichert
- Grayscale-Crash in `Color.toHex()`
- Face ID greift nur nach echtem Hintergrundwechsel (> 5 s), nicht bei jedem Fokusverlust
- Reconnect-Debounce (2 s) gegen 429-Rate-Limiting des Servers
- Widget-Daten werden einmal nach vollständigem Refresh geschrieben statt einmal pro Topic
- Sound-Vorschau und Notification-Sound spielen wieder korrekt ab

### Entfernt

- Tote Delegate-Extension entfernt

### Sicherheit

- Bestätigungsdialog vor dem Ausführen von HTTP-Actions
- FCM-Token in die Keychain migriert
- Härtung von `openURL` durch Validierung des URL-Schemas

### Bekannte Einschränkung

- Das `NtfyWidget`-Target wurde direkt in `project.pbxproj` eingetragen, nicht über die
  Xcode-UI. Falls Xcode Probleme mit dem Widget-Target meldet, das Target in Xcode neu
  anlegen statt die pbxproj weiter von Hand zu editieren.

## [1.0.0] - 2026-01-09

Erste Version.

### Hinzugefügt

- Abonnieren von Topics auf ntfy.sh oder einem selbst gehosteten ntfy-Server
- Echtzeit-Benachrichtigungen über SSE sowie Push über Firebase Cloud Messaging
- Authentifizierung per Benutzername/Passwort oder Access Token, gespeichert in der Keychain
- Lokale Speicherung von Nachrichten über SwiftData
- Anzeige von App-Icons aus Nachrichten, Prioritäts-Badges, Dark Mode
- Notification Service Extension für Badge-Zählung und Aufbereitung eingehender Pushes

[Unreleased]: https://github.com/Revisor01/ntfy-plus-ios/compare/2.2.0...HEAD
[2.2.0]: https://github.com/Revisor01/ntfy-plus-ios/compare/2.1.0...2.2.0
[2.1.0]: https://github.com/Revisor01/ntfy-plus-ios/compare/v2.0.0...2.1.0
[2.0.0]: https://github.com/Revisor01/ntfy-plus-ios/compare/v1.0...v2.0.0
[1.0.0]: https://github.com/Revisor01/ntfy-plus-ios/releases/tag/v1.0
