import SwiftUI
import LocalAuthentication

// MARK: - Geraete-Authentifizierung (Biometrie mit Code-Fallback)

/// Hilfsfunktionen für `.deviceOwnerAuthentication` mit Fallback auf den Gerätecode.
enum DeviceAuth {
    /// Biometrie-Typ, erst nach `canEvaluatePolicy` gesetzt.
    static func biometryType() -> LABiometryType {
        let context = LAContext()
        var authError: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError)
        return context.biometryType
    }

    /// Name der Entsperr-Methode fuer UI-Texte ("Face ID", "Touch ID", "Optic ID", "Code").
    static func methodName(for type: LABiometryType) -> String {
        switch type {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        case .opticID:
            return "Optic ID"
        case .none:
            return "Code"
        @unknown default:
            return "Code"
        }
    }

    /// SF-Symbol passend zur Entsperr-Methode.
    static func symbolName(for type: LABiometryType) -> String {
        switch type {
        case .faceID:
            return "faceid"
        case .touchID:
            return "touchid"
        case .opticID:
            return "opticid"
        case .none:
            return "lock.open.fill"
        @unknown default:
            return "lock.open.fill"
        }
    }

    /// Titel fuer den Sperr-Toggle in den Einstellungen.
    static func lockToggleTitle() -> String {
        "App mit \(methodName(for: biometryType())) sperren"
    }

    /// Verstaendliche Meldung, warum `.deviceOwnerAuthentication` nicht moeglich ist.
    static func unavailableMessage(for error: NSError?) -> String {
        if let error, error.domain == LAError.errorDomain,
           let code = LAError.Code(rawValue: error.code) {
            switch code {
            case .passcodeNotSet:
                return "Auf diesem Gerät ist kein Code eingerichtet. Richte in den iOS-Einstellungen unter „Face ID & Code“ bzw. „Touch ID & Code“ einen Gerätecode ein, um die App-Sperre zu nutzen."
            case .biometryLockout:
                return "Biometrie ist vorübergehend gesperrt. Entsperre das Gerät einmal mit deinem Code und versuche es erneut."
            default:
                return error.localizedDescription
            }
        }
        return error?.localizedDescription ?? "Geräte-Authentifizierung ist nicht verfügbar."
    }
}

// MARK: - Lock Screen

struct LockScreenView: View {
    /// Nur bei aktiver Szene, im Zustand .inactive scheitert der Dialog.
    let isSceneActive: Bool
    let onUnlock: () -> Void

    @State private var errorMessage: String?
    @State private var isAuthenticating = false
    /// true, wenn das Geraet gar keinen Code hat — dann gibt es keinen Entsperr-Weg
    @State private var passcodeNotSet = false
    @State private var biometry: LABiometryType = .none
    /// Nur einmal pro Sperre, die Rückkehr aus dem Dialog soll keinen neuen öffnen.
    @State private var hasAutoAuthenticated = false

    init(isSceneActive: Bool = true, onUnlock: @escaping () -> Void) {
        self.isSceneActive = isSceneActive
        self.onUnlock = onUnlock
    }

    var body: some View {
        ZStack {
            // Verschwommener Hintergrund — verhindert Inhaltsvorschau
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: AppSpacing.lg) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Text("ntfy+ ist gesperrt")
                    .font(AppFonts.headline)
                    .foregroundStyle(.primary)

                if let errorMessage {
                    Text(errorMessage)
                        .font(AppFonts.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.xl)
                }

                if passcodeNotSet {
                    // Ohne Gerätecode kann iOS niemanden authentifizieren, daher Sperre abschaltbar statt Aussperrung.
                    Button {
                        AppSettings.biometricLockEnabled = false
                        onUnlock()
                    } label: {
                        Label("Sperre deaktivieren und fortfahren", systemImage: "lock.open")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, AppSpacing.xl)
                } else {
                    Button {
                        authenticate()
                    } label: {
                        Label(
                            "Mit \(DeviceAuth.methodName(for: biometry)) entsperren",
                            systemImage: DeviceAuth.symbolName(for: biometry)
                        )
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, AppSpacing.xl)
                    .disabled(isAuthenticating)
                }
            }
        }
        .onAppear {
            biometry = DeviceAuth.biometryType()
            autoAuthenticateIfActive()
        }
        .onChange(of: isSceneActive) {
            autoAuthenticateIfActive()
        }
    }

    private func autoAuthenticateIfActive() {
        guard isSceneActive, !hasAutoAuthenticated else { return }
        hasAutoAuthenticated = true
        authenticate()
    }

    private func authenticate() {
        guard !isAuthenticating else { return }

        let context = LAContext()
        var authError: NSError?

        // Biometrie mit Code-Fallback, geht auch ohne Biometrie.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
            errorMessage = DeviceAuth.unavailableMessage(for: authError)
            if let authError, authError.domain == LAError.errorDomain,
               authError.code == LAError.Code.passcodeNotSet.rawValue {
                passcodeNotSet = true
            }
            return
        }

        passcodeNotSet = false
        isAuthenticating = true

        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "ntfy+ entsperren"
        ) { success, error in
            DispatchQueue.main.async {
                isAuthenticating = false
                if success {
                    errorMessage = nil
                    onUnlock()
                } else if let error = error as? LAError, error.code != .userCancel {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
