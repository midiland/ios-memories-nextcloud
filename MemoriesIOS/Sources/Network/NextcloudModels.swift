import Foundation

/// Response of `GET …/apps/memories/api/describe` (see `OtherController::describeApi`).
struct DescribeResponse: Decodable {
    let version: String
    /// Absolute root of the Memories app, e.g. `https://cloud/index.php/apps/memories/`.
    let baseUrl: String
    /// Login Flow v2 initialization endpoint (`/index.php/login/v2`).
    let loginFlowUrl: String
    /// Authenticated user; `nil` if the request is anonymous or the credentials are invalid.
    let uid: String?
}

/// Response of `POST /index.php/login/v2`.
struct LoginFlowInit: Decodable {
    struct Poll: Decodable {
        let token: String
        let endpoint: URL
    }

    let poll: Poll
    /// Login page to open in the browser.
    let login: URL
}

/// Login Flow v2 polling response once the login is approved.
struct LoginFlowResult: Decodable {
    let server: String
    let loginName: String
    let appPassword: String
}
