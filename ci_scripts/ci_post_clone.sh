#!/bin/bash
# Xcode Cloud, nach dem Klonen: GoogleService-Info.plist liegt nicht im Repo.
# Sie kommt base64-kodiert aus der geheimen Umgebungsvariable
# GOOGLE_SERVICE_INFO_PLIST_B64 des Workflows; ohne sie kaeme kein Push an.
set -euo pipefail

ZIEL="${CI_PRIMARY_REPOSITORY_PATH:?Nur fuer Xcode Cloud gedacht.}/ntfy/GoogleService-Info.plist"
[ -n "${GOOGLE_SERVICE_INFO_PLIST_B64:-}" ] || { echo "FEHLER: GOOGLE_SERVICE_INFO_PLIST_B64 fehlt im Xcode-Cloud-Workflow."; exit 1; }
printf '%s' "$GOOGLE_SERVICE_INFO_PLIST_B64" | base64 -D > "$ZIEL"

BUNDLE=$(/usr/libexec/PlistBuddy -c "Print :BUNDLE_ID" "$ZIEL" 2>/dev/null || true)
[ "$BUNDLE" = "de.godsapp.ntfy" ] || { echo "FEHLER: GoogleService-Info.plist gilt fuer '$BUNDLE', erwartet de.godsapp.ntfy."; exit 1; }
echo "GoogleService-Info.plist fuer $BUNDLE geschrieben."
