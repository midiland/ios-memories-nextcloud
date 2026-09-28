import SwiftUI

/// Écran de connexion : saisie de l'URL du serveur puis Login Flow v2
/// (équivalent natif de `welcome.html` sur Android).
struct LoginView: View {
    @EnvironmentObject private var session: SessionStore
    @AppStorage("lastServerInput") private var serverInput = ""
    @FocusState private var fieldFocused: Bool

    private var isBusy: Bool { session.loginState != .idle }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            header
            serverField
            if let error = session.loginError {
                Text(error.localizedDescription)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            loginButton
            Spacer()
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: 480)
        .sheet(isPresented: loginSheetBinding) {
            if let url = session.loginPage {
                SafariView(url: url)
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: - Sous-vues

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Memories")
                .font(.largeTitle.bold())
            Text("Connectez-vous à votre serveur Nextcloud")
                .foregroundStyle(.secondary)
        }
    }

    private var serverField: some View {
        TextField("cloud.exemple.fr", text: $serverInput)
            .textContentType(.URL)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.go)
            .focused($fieldFocused)
            .onSubmit(submit)
            .padding(12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            .disabled(isBusy)
    }

    private var loginButton: some View {
        Button(action: submit) {
            HStack {
                if isBusy { ProgressView().tint(.white) }
                Text(buttonTitle)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isBusy || ServerURL(userInput: serverInput) == nil)
    }

    private var buttonTitle: String {
        switch session.loginState {
        case .idle: return "Se connecter"
        case .connecting: return "Connexion…"
        case .waitingForApproval: return "En attente de validation…"
        }
    }

    /// La feuille se ferme quand le polling aboutit ; fermée par l'utilisateur ⇒ annulation.
    private var loginSheetBinding: Binding<Bool> {
        Binding(
            get: { session.loginPage != nil },
            set: { presented in
                if !presented && session.loginPage != nil { session.cancelLogin() }
            }
        )
    }

    private func submit() {
        fieldFocused = false
        session.login(serverInput: serverInput)
    }
}
