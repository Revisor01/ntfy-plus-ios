<p align="center">
  <img src="AppIcon.png" alt="ntfy+" width="128" height="128">
</p>

<h1 align="center">ntfy+</h1>

<p align="center">
  The iPhone app for <a href="https://ntfy.sh">ntfy</a> — receive notifications from your own<br>
  or a public ntfy server, and send your own.
</p>

<p align="center">
  <a href="README.md">Deutsch</a> · <b>English</b>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-iOS%2027+-blue?logo=apple" alt="Platform">
  <img src="https://img.shields.io/badge/Swift-6.0-orange?logo=swift" alt="Swift">
  <img src="https://img.shields.io/badge/Xcode-27+-blue?logo=xcode" alt="Xcode">
  <img src="https://img.shields.io/github/license/Revisor01/ntfy-plus-ios" alt="License">
  <img src="https://img.shields.io/github/v/release/Revisor01/ntfy-plus-ios" alt="Version">
</p>

## What it is about

ntfy is a simple service for push notifications: a script, a server or a smart
home sends a message over HTTP to a topic, and every device subscribed to that
topic receives it.

ntfy+ is a dedicated iPhone app for it, with your own server or ntfy.sh. Topics
can be styled, you can send messages yourself, and protected topics work with
username and password or an access token.

## Features

- **Your own server or ntfy.sh** — several servers side by side
- **Real time** — new messages via server-sent events, push even when the app is closed
- **Protected topics** — username/password or access token, for push as well
- **Sending** — messages with title, priority, tags, attachments (photos and files up
  to 15 MB) and a scheduled delivery time
- **Attachments and icons** — image preview in the notification, icons from the message
  (for example from Sonarr, Radarr or Home Assistant)
- **Actions** — buttons from the message, HTTP actions with a confirmation before sending
- **Styled topics** — your own colours, letters or icons, mute
- **Priorities** — urgent messages are highlighted
- **Widget** — unread messages on the home screen
- **App lock** — lock and privacy screen, on iPad for all windows
- **Offline** — messages stay stored locally
- Light and dark mode, iPhone and iPad

## Installation

The app is not in the App Store yet. The current version **2.2 (build 8)** is
available via TestFlight; access on request via the contact address below.

You need iOS 27 or later and an ntfy server — ntfy.sh is preset, your own works
just the same.

**Getting started:** open the app; the setup walks you through the server,
optional login and the first topic.

## Versions

What changed when is in [CHANGELOG.md](CHANGELOG.md) (in German, following
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/)). The
[releases](https://github.com/Revisor01/ntfy-plus-ios/releases) summarise each
version.

## Building it yourself

```bash
git clone https://github.com/Revisor01/ntfy-plus-ios.git
cd ntfy-plus-ios
open ntfy-ios.xcodeproj
```

Xcode 27 or later, target iOS 27. Xcode fetches the Swift packages on first
open (versions in `Package.resolved`). Enter your own team in the signing
settings. Push while the app is closed needs your own Firebase project with a
`GoogleService-Info.plist`; without it, messages only arrive while the app is
running.

## Structure

```
ntfy-plus-ios
├── ntfy/                         — the app: views, models (SwiftData), services
│                                   (ntfy API, SSE, push, keychain)
├── NotificationServiceExtension/ — loads content of protected topics and image
│                                   attachments before the notification appears
└── NtfyWidget/                   — home screen widget
```

**What matters when building:**
- **Credentials belong in the keychain**, never in the settings.
- **No credentials to foreign hosts** — login only happens with your own server.
- **Behave like upstream ntfy** where the protocol defines it (Markdown, actions,
  attachments).

## Contributing

Bug reports and suggestions are welcome as an
[issue](https://github.com/Revisor01/ntfy-plus-ios/issues); the form asks for the
app and server version. Please report security issues privately as described in
[SECURITY.md](SECURITY.md). Pull requests run through a build and a secret scan;
see [CONTRIBUTING.md](CONTRIBUTING.md).

## Privacy

ntfy+ collects nothing for the developer: no analytics, no ads. Server
addresses, credentials (in the keychain), topics, messages and settings stay on
the device and disappear with the app.

The app talks to the ntfy servers you enter yourself. For push notifications
while the app is closed, it registers with Apple (APNs) and Google Firebase
Cloud Messaging and subscribes to the topic names there; the ntfy server
delivers push messages that way.

## License

ntfy+ is licensed under the
[GNU Affero General Public License v3.0](LICENSE). If you modify ntfy+ and make
it available to others, including as a web service, you publish your source
code under the same license.
Contributions: [CONTRIBUTING.md](CONTRIBUTING.md). The [LICENSE](LICENSE) file
is authoritative.

The author distributes the App Store versions himself as the rights holder.

## Note

ntfy+ is an independent app. It is not an official product of the ntfy project
and is neither supported nor reviewed by it.

Thanks to [ntfy](https://ntfy.sh) by Philipp C. Heckel — the great open-source
service without which this app would not exist.

## Contact

Pastor Simon Luthe · [mail@simonluthe.de](mailto:mail@simonluthe.de) ·
[simonluthe.de](https://simonluthe.de)
