<p align="center">
  <img src="AppIcon.png" alt="ntfy+" width="128" height="128">
</p>

<h1 align="center">ntfy+</h1>

<p align="center">
  Native iOS-App für <a href="https://ntfy.sh">ntfy</a> Push-Benachrichtigungen.
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#installation">Installation</a> •
  <a href="#konfiguration">Konfiguration</a> •
  <a href="#mitwirken">Mitwirken</a>
</p>

---

## Features

- **Self-Hosted Support**: Nutze ntfy.sh oder deinen eigenen ntfy-Server
- **Echtzeit-Benachrichtigungen**: Sofortige Push-Nachrichten via SSE
- **App-Icons**: Zeigt Icons aus Nachrichten an (z.B. Sonarr, Radarr, Home Assistant)
- **Topic-Anpassung**: Eigene Farben, Buchstaben oder Icons pro Topic
- **Prioritäten**: Visuelle Badges für dringende Nachrichten
- **Authentifizierung**: Unterstützt Benutzername/Passwort und Access Tokens
- **Offline-Speicherung**: Nachrichten werden lokal gespeichert
- **Dark Mode**: Vollständige Unterstützung
- **Native iOS**: SwiftUI, SwiftData, iOS 26+

## Voraussetzungen

- iOS 26.0+
- ntfy-Server (self-hosted oder ntfy.sh)

## Installation

### TestFlight

*Demnächst verfügbar*

### Selbst kompilieren

1. Repository klonen:
   ```bash
   git clone https://github.com/SimonLuworksphere/ntfy-plus-ios.git
   ```
2. `ntfy-ios.xcodeproj` in Xcode öffnen
3. Team/Signing konfigurieren
4. Auf dem Gerät bauen und ausführen

## Konfiguration

1. **App starten** - Der Onboarding-Flow führt durch die Einrichtung
2. **Server eingeben** - ntfy.sh ist voreingestellt, eigene Server funktionieren auch
3. **Authentifizierung** - Optional, nur wenn der Server es erfordert
4. **Topics abonnieren** - Fertig!

## Screenshots

*Screenshots folgen*

## Technologie

- **SwiftUI** - Moderne, deklarative UI
- **SwiftData** - Persistenz für Topics und Nachrichten
- **Server-Sent Events** - Echtzeit-Verbindung zum ntfy-Server
- **Keychain** - Sichere Speicherung von Zugangsdaten

## Mitwirken

Beiträge sind willkommen! Pull Requests können gerne eingereicht werden.

## Lizenz

Dieses Projekt steht unter der Apache License 2.0 - siehe [LICENSE](LICENSE) für Details.

## Danksagung

- [ntfy](https://ntfy.sh) von Philipp C. Heckel - Der großartige Open-Source Push-Service
- Gebaut mit Hilfe von [Claude Code](https://claude.ai/claude-code)

## Hinweis

Dies ist eine inoffizielle Companion-App. ntfy+ ist nicht mit dem ntfy-Projekt verbunden oder von diesem unterstützt.

---

## Datenschutzerklärung

### Verantwortlicher

Simon Luthe
Süderstraße 18
25779 Hennstedt
Deutschland

E-Mail: mail@simonluthe.de
Telefon: +49 151 21563194
Web: [simonluthe.de](https://simonluthe.de)

### Datenverarbeitung

**ntfy+ speichert und verarbeitet folgende Daten ausschließlich lokal auf deinem Gerät:**

- Server-URLs deiner ntfy-Server
- Optionale Zugangsdaten (Benutzername/Passwort oder Access Token)
- Abonnierte Topics und deren Einstellungen
- Empfangene Nachrichten
- App-Einstellungen und Präferenzen

**Es werden keine Daten an externe Server übertragen**, außer an die von dir konfigurierten ntfy-Server.

### Keine Tracking- oder Analysedienste

ntfy+ verwendet:
- Keine Analytics oder Tracking-Tools
- Keine Werbung
- Keine Cloud-Dienste (außer deinem ntfy-Server)
- Keine Drittanbieter-SDKs, die Daten sammeln

### Netzwerkverbindungen

Die App stellt Verbindungen ausschließlich zu den von dir konfigurierten ntfy-Servern her:
- Abrufen von Nachrichten (HTTPS)
- Echtzeit-Verbindung für neue Nachrichten (SSE)
- Senden von Nachrichten (falls genutzt)

### Datenspeicherung

Alle Daten werden lokal gespeichert:
- **Zugangsdaten**: iOS Keychain (verschlüsselt)
- **Topics & Nachrichten**: SwiftData (lokal)
- **Einstellungen**: UserDefaults

Bei Deinstallation der App werden alle Daten vollständig entfernt.

### Deine Rechte (DSGVO)

Da alle Daten ausschließlich lokal auf deinem Gerät gespeichert werden und keine Übertragung an den Entwickler erfolgt, hast du die volle Kontrolle über deine Daten. Du kannst diese jederzeit durch Löschen der App vollständig entfernen.

Bei Fragen zum Datenschutz kannst du dich jederzeit an die oben genannte Kontaktadresse wenden.

### Änderungen

Diese Datenschutzerklärung kann bei Bedarf aktualisiert werden. Die aktuelle Version ist stets in diesem Repository verfügbar.

*Stand: Januar 2026*
