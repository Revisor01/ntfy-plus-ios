import SwiftUI
import LocalAuthentication

struct LockScreenView: View {
    let onUnlock: () -> Void

    @State private var errorMessage: String?

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

                Button {
                    authenticate()
                } label: {
                    Label("Mit Face ID entsperren", systemImage: "faceid")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, AppSpacing.xl)
            }
        }
        .onAppear {
            authenticate()
        }
    }

    private func authenticate() {
        let context = LAContext()
        var authError: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
            errorMessage = authError?.localizedDescription ?? "Biometrie nicht verfügbar"
            return
        }

        context.evaluatePolicy(
            .deviceOwnerAuthentication, // inkludiert automatisch Passcode-Fallback (BIO-03)
            localizedReason: "ntfy+ entsperren"
        ) { success, error in
            DispatchQueue.main.async {
                if success {
                    onUnlock()
                } else if let error = error as? LAError, error.code != .userCancel {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
