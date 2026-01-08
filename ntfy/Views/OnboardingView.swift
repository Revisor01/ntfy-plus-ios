import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var isOnboardingComplete: Bool

    @State private var currentPage = 0
    @State private var serverURL = "https://ntfy.sh"
    @State private var useAuth = false
    @State private var username = ""
    @State private var password = ""
    @State private var token = ""
    @State private var useToken = false
    @State private var isTestingConnection = false
    @State private var connectionError: String?
    @State private var connectionSuccess = false

    // Brand colors from the icon
    private let brandBlue = Color(hex: "#4A6FA5")
    private let brandLightBlue = Color(hex: "#7EB6C7")
    private let brandBackground = Color(hex: "#E4EDF7")

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [brandBackground, brandBackground.opacity(0.5), .white],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Content
                TabView(selection: $currentPage) {
                    welcomePage.tag(0)
                    serverSetupPage.tag(1)
                    authPage.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentPage)

                // Custom page indicator
                pageIndicator
                    .padding(.bottom, 20)
            }
        }
    }

    // MARK: - Page Indicator

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { index in
                Capsule()
                    .fill(index == currentPage ? brandBlue : brandBlue.opacity(0.3))
                    .frame(width: index == currentPage ? 24 : 8, height: 8)
                    .animation(.spring(response: 0.3), value: currentPage)
            }
        }
    }

    // MARK: - Welcome Page

    private var welcomePage: some View {
        VStack(spacing: 0) {
            Spacer()

            // App Icon
            ZStack {
                RoundedRectangle(cornerRadius: 28)
                    .fill(
                        LinearGradient(
                            colors: [brandBackground, brandLightBlue.opacity(0.5)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)

                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(brandBlue)
            }
            .shadow(color: brandBlue.opacity(0.3), radius: 20, x: 0, y: 10)

            VStack(spacing: 8) {
                Text("ntfy+")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(brandBlue)

                Text("Push-Benachrichtigungen\nfür alle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 24)

            Spacer()

            // Features
            VStack(spacing: 16) {
                featureCard(
                    icon: "server.rack",
                    title: "Self-Hosted",
                    description: "Nutze deinen eigenen Server"
                )
                featureCard(
                    icon: "bolt.fill",
                    title: "Echtzeit",
                    description: "Sofortige Benachrichtigungen"
                )
                featureCard(
                    icon: "paintpalette.fill",
                    title: "Anpassbar",
                    description: "Farben, Icons und mehr"
                )
            }
            .padding(.horizontal, 24)

            Spacer()

            // Button
            Button {
                withAnimation(.spring(response: 0.4)) {
                    currentPage = 1
                }
            } label: {
                Text("Los geht's")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(brandBlue.gradient)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }

    private func featureCard(icon: String, title: String, description: String) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(brandBlue.opacity(0.1))
                    .frame(width: 48, height: 48)

                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(brandBlue)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .background(.white.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Server Setup Page

    private var serverSetupPage: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .fill(brandBlue.opacity(0.1))
                    .frame(width: 100, height: 100)

                Image(systemName: "server.rack")
                    .font(.system(size: 44))
                    .foregroundStyle(brandBlue)
            }

            Text("Server einrichten")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .padding(.top, 24)

            Text("Wo sollen deine Benachrichtigungen herkommen?")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            Spacer()

            VStack(spacing: 16) {
                // Server URL Input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Server URL")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    TextField("https://ntfy.sh", text: $serverURL)
                        .textFieldStyle(.plain)
                        .padding(16)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(brandBlue.opacity(0.2), lineWidth: 1)
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }

                // Auth Toggle
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Authentifizierung")
                            .font(.headline)
                        Text("Nur wenn dein Server es erfordert")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: $useAuth)
                        .tint(brandBlue)
                }
                .padding(16)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 24)

            Spacer()

            // Buttons
            HStack(spacing: 12) {
                Button {
                    withAnimation(.spring(response: 0.4)) {
                        currentPage = 0
                    }
                } label: {
                    Text("Zurück")
                        .font(.headline)
                        .foregroundStyle(brandBlue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(brandBlue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                Button {
                    if useAuth {
                        withAnimation(.spring(response: 0.4)) {
                            currentPage = 2
                        }
                    } else {
                        finishOnboarding()
                    }
                } label: {
                    Text(useAuth ? "Weiter" : "Fertig")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(serverURL.isEmpty ? AnyShapeStyle(Color.gray) : AnyShapeStyle(brandBlue.gradient))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .disabled(serverURL.isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Auth Page

    private var authPage: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .fill(brandBlue.opacity(0.1))
                    .frame(width: 100, height: 100)

                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(brandBlue)
            }

            Text("Anmeldung")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .padding(.top, 24)

            Text("Gib deine Zugangsdaten ein")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            Spacer()

            VStack(spacing: 16) {
                // Method Picker
                Picker("Methode", selection: $useToken) {
                    Text("Benutzername").tag(false)
                    Text("Token").tag(true)
                }
                .pickerStyle(.segmented)

                if useToken {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Access Token")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        SecureField("tk_...", text: $token)
                            .textFieldStyle(.plain)
                            .padding(16)
                            .background(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(brandBlue.opacity(0.2), lineWidth: 1)
                            )
                            .textInputAutocapitalization(.never)
                    }
                } else {
                    VStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Benutzername")
                                .font(.headline)
                                .foregroundStyle(.secondary)

                            TextField("Benutzername", text: $username)
                                .textFieldStyle(.plain)
                                .padding(16)
                                .background(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(brandBlue.opacity(0.2), lineWidth: 1)
                                )
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Passwort")
                                .font(.headline)
                                .foregroundStyle(.secondary)

                            SecureField("Passwort", text: $password)
                                .textFieldStyle(.plain)
                                .padding(16)
                                .background(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(brandBlue.opacity(0.2), lineWidth: 1)
                                )
                        }
                    }
                }

                // Status messages
                if let error = connectionError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(error)
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                if connectionSuccess {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Verbindung erfolgreich!")
                    }
                    .font(.subheadline.bold())
                    .foregroundStyle(.green)
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(.green.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            // Buttons
            HStack(spacing: 12) {
                Button {
                    withAnimation(.spring(response: 0.4)) {
                        currentPage = 1
                    }
                } label: {
                    Text("Zurück")
                        .font(.headline)
                        .foregroundStyle(brandBlue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(brandBlue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                Button {
                    testAndFinish()
                } label: {
                    HStack(spacing: 8) {
                        if isTestingConnection {
                            ProgressView()
                                .tint(.white)
                        }
                        Text("Verbinden")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(isAuthValid ? AnyShapeStyle(brandBlue.gradient) : AnyShapeStyle(Color.gray.gradient))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .disabled(!isAuthValid || isTestingConnection)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }

    private var isAuthValid: Bool {
        if useToken {
            return !token.isEmpty
        } else {
            return !username.isEmpty && !password.isEmpty
        }
    }

    private func testAndFinish() {
        isTestingConnection = true
        connectionError = nil

        Task {
            do {
                var normalizedURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
                if !normalizedURL.hasPrefix("http://") && !normalizedURL.hasPrefix("https://") {
                    normalizedURL = "https://" + normalizedURL
                }
                normalizedURL = normalizedURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

                let testURL = URL(string: "\(normalizedURL)/test/json?poll=1")!
                var request = URLRequest(url: testURL)
                request.timeoutInterval = 10

                if useToken {
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                } else {
                    let credentials = "\(username):\(password)"
                    if let data = credentials.data(using: .utf8) {
                        request.setValue("Basic \(data.base64EncodedString())", forHTTPHeaderField: "Authorization")
                    }
                }

                let (_, response) = try await URLSession.shared.data(for: request)

                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                        await MainActor.run {
                            connectionError = "Authentifizierung fehlgeschlagen"
                            isTestingConnection = false
                        }
                        return
                    }
                }

                await MainActor.run {
                    connectionSuccess = true
                    isTestingConnection = false

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        finishOnboarding()
                    }
                }
            } catch {
                await MainActor.run {
                    connectionError = "Verbindung fehlgeschlagen"
                    isTestingConnection = false
                }
            }
        }
    }

    private func finishOnboarding() {
        var normalizedURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedURL.hasPrefix("http://") && !normalizedURL.hasPrefix("https://") {
            normalizedURL = "https://" + normalizedURL
        }
        normalizedURL = normalizedURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if useAuth {
            if useToken {
                try? KeychainManager.shared.saveToken(serverURL: normalizedURL, token: token)
            } else {
                try? KeychainManager.shared.saveCredentials(serverURL: normalizedURL, username: username, password: password)
            }
        }

        let server = Server(
            url: normalizedURL,
            name: URL(string: normalizedURL)?.host ?? normalizedURL,
            useAuth: useAuth,
            username: useAuth && !useToken ? username : nil,
            isDefault: true
        )
        modelContext.insert(server)
        try? modelContext.save()

        AppSettings.defaultServerURL = normalizedURL
        isOnboardingComplete = true
    }
}

#Preview {
    OnboardingView(isOnboardingComplete: .constant(false))
        .modelContainer(for: [Server.self], inMemory: true)
}
