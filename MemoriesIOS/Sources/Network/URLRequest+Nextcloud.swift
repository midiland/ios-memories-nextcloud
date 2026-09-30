import Foundation

extension URLRequest {
    /// Request with the app's User-Agent. The credentials (Basic auth + `OCS-APIREQUEST`) are
    /// only added when `url` points to the account's server: they never go to a third-party host.
    init(url: URL, authorizedFor credentials: Credentials) {
        self.init(url: url)
        setValue(AppConstants.userAgentSuffix, forHTTPHeaderField: "User-Agent")
        if url.host == credentials.server.host {
            setValue(credentials.basicAuthHeader, forHTTPHeaderField: "Authorization")
            setValue("true", forHTTPHeaderField: "OCS-APIREQUEST")
        }
    }
}
