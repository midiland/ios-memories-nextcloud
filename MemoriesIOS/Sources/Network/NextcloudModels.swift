import Foundation

/// Réponse de `GET …/apps/memories/api/describe` (voir `OtherController::describeApi`).
struct DescribeResponse: Decodable {
    let version: String
    /// Racine absolue de l'app Memories, ex. `https://cloud/index.php/apps/memories/`.
    let baseUrl: String
    /// Endpoint d'initialisation du Login Flow v2 (`/index.php/login/v2`).
    let loginFlowUrl: String
    /// Utilisateur authentifié, `nil` si la requête est anonyme ou les identifiants invalides.
    let uid: String?
}

/// Réponse de `POST /index.php/login/v2`.
struct LoginFlowInit: Decodable {
    struct Poll: Decodable {
        let token: String
        let endpoint: URL
    }

    let poll: Poll
    /// Page de connexion à ouvrir dans le navigateur.
    let login: URL
}

/// Réponse du polling Login Flow v2 une fois la connexion approuvée.
struct LoginFlowResult: Decodable {
    let server: String
    let loginName: String
    let appPassword: String
}

/// Comparaison de versions type `9.0.0-rc.1` (une pré-version est inférieure à la finale).
struct SemanticVersion: Comparable {
    let numbers: [Int]
    let preRelease: String?

    init(_ text: String) {
        let parts = text.split(separator: "-", maxSplits: 1).map(String.init)
        numbers = (parts.first ?? "").split(separator: ".").map { Int($0) ?? 0 }
        preRelease = parts.count > 1 ? parts[1] : nil
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let count = max(lhs.numbers.count, rhs.numbers.count)
        for i in 0..<count {
            let l = i < lhs.numbers.count ? lhs.numbers[i] : 0
            let r = i < rhs.numbers.count ? rhs.numbers[i] : 0
            if l != r { return l < r }
        }
        switch (lhs.preRelease, rhs.preRelease) {
        case (nil, nil), (nil, _): return false
        case (_, nil): return true
        case let (l?, r?): return l.compare(r, options: .numeric) == .orderedAscending
        }
    }
}
