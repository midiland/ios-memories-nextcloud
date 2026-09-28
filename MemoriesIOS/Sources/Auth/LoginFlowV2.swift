import Foundation

/// Connexion Nextcloud par Login Flow v2, en deux temps (comme `AccountManager` sur Android) :
/// 1. `prepare` : vérifie le serveur (`api/describe`) puis ouvre un flow → URL de login ;
/// 2. `waitForApproval` : polling toutes les 3 s (10 min max) jusqu'à l'obtention
///    de `loginName` + `appPassword`.
///
/// L'affichage de la page de login (SFSafariViewController) est géré par la vue.
struct LoginFlowV2 {
    /// Flow prêt : page à ouvrir + informations de polling.
    struct Pending {
        let loginPage: URL
        let poll: LoginFlowInit.Poll
        /// Racine Memories canonique renvoyée par le serveur.
        let server: ServerURL
    }

    private let client = NextcloudClient()

    /// Valide le serveur saisi et démarre un flow.
    func prepare(userInput: String) async throws -> Pending {
        guard let entered = ServerURL(userInput: userInput) else { throw AppError.invalidURL }

        let describe = try await client.describe(entered)
        // Le serveur connaît son URL canonique (overwrite.cli.url, protocole…) : on la préfère.
        let server = ServerURL(memoriesBaseURL: describe.baseUrl) ?? entered
        guard let loginFlowURL = URL(string: describe.loginFlowUrl) else {
            throw AppError.invalidResponse
        }

        let flow = try await client.startLoginFlow(loginFlowURL)
        return Pending(loginPage: flow.login, poll: flow.poll, server: server)
    }

    /// Attend que l'utilisateur valide la connexion dans le navigateur.
    /// S'arrête proprement si la tâche est annulée (`CancellationError`).
    func waitForApproval(_ pending: Pending) async throws -> Credentials {
        let deadline = Date().addingTimeInterval(AppConstants.loginPollTimeout)
        while Date() < deadline {
            try await Task.sleep(nanoseconds: AppConstants.loginPollInterval)
            // Les erreurs réseau ponctuelles sont ignorées : on retente au tour suivant.
            if let result = try? await client.pollLogin(pending.poll) {
                return Credentials(
                    server: pending.server,
                    loginName: result.loginName,
                    appPassword: result.appPassword
                )
            }
        }
        throw AppError.loginTimeout
    }
}
