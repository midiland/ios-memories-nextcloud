import Foundation

/// Photos of the server timeline, per day (`GET …/api/days/{id1},{id2}`), with a short cache:
/// the frontend fetches a day several times (scrolling, refresh), and neighbouring days overlap.
actor ServerDayClient {
    private let credentials: Credentials
    private let session: URLSession
    private var cache: [Int: (date: Date, photos: [ServerPhoto])] = [:]
    private let maxAge: TimeInterval = 120

    init(credentials: Credentials, session: URLSession = .shared) {
        self.credentials = credentials
        self.session = session
    }

    /// Server photos of the given days. Throws if a day is not cached and the server is unreachable.
    func photos(days dayIds: [Int]) async throws -> [ServerPhoto] {
        let now = Date()
        let missing = dayIds.filter { day in cache[day].map { now.timeIntervalSince($0.date) > maxAge } ?? true }
        if !missing.isEmpty {
            let fetched = try await fetch(missing)
            let byDay = Dictionary(grouping: fetched, by: \.dayid)
            for day in missing {
                cache[day] = (now, byDay[day] ?? [])
            }
        }
        return dayIds.flatMap { cache[$0]?.photos ?? [] }
    }

    func invalidate() {
        cache = [:]
    }

    private func fetch(_ dayIds: [Int]) async throws -> [ServerPhoto] {
        let ids = dayIds.sorted().map(String.init).joined(separator: ",")
        let url = credentials.server.memoriesURL.appendingPathComponent("api/days/\(ids)")
        var request = URLRequest(url: url, authorizedFor: credentials)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw AppError.unexpectedStatus(status) }
        return try JSONDecoder().decode([ServerPhoto].self, from: data)
    }
}
