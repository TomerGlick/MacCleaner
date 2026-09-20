import Foundation
import os.log

/// A semantic version, compared numerically rather than as text.
///
/// String comparison gets this wrong in the case that matters: "1.10.0" sorts *before*
/// "1.9.0" alphabetically, so a user on 1.9.0 would never be told about 1.10.0.
struct AppVersion: Comparable, CustomStringConvertible {
    let components: [Int]

    /// Parses "1.4.0", "v1.4.0" or "1.4". Returns nil for anything without a leading number.
    init?(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Release tags are sometimes prefixed; this project uses bare versions, but a "v"
        // costs nothing to tolerate and would otherwise silently disable update checks.
        let withoutPrefix = trimmed.hasPrefix("v") || trimmed.hasPrefix("V")
            ? String(trimmed.dropFirst())
            : trimmed

        // Parsing stops at the first segment that is not purely numeric, so
        // "1.4.0-beta.1" reads as 1.4.0 rather than 1.4.0.1 — which would otherwise
        // compare as *newer* than the 1.4.0 release it precedes.
        var parsed: [Int] = []
        for segment in withoutPrefix.split(separator: ".") {
            let digits = segment.prefix(while: \.isNumber)
            guard !digits.isEmpty, let value = Int(digits) else { break }
            parsed.append(value)
            // A suffix on this segment ends the version; everything after it is a
            // prerelease or build identifier.
            if digits.count != segment.count { break }
        }

        guard !parsed.isEmpty else { return nil }
        components = parsed
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        // Missing trailing components are zero, so 1.4 == 1.4.0 rather than being lesser.
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    var description: String { components.map(String.init).joined(separator: ".") }
}

/// The newest release as published on GitHub.
struct ReleaseInfo: Equatable {
    let version: String
    let url: URL
}

/// Fetches the latest release. Abstracted so the check can be tested without a network.
protocol ReleaseFetching {
    func latestRelease() async throws -> ReleaseInfo
}

/// Reads the newest release straight from the GitHub Releases API.
struct GitHubReleaseFetcher: ReleaseFetching {
    let owner: String
    let repository: String
    let session: URLSession

    init(owner: String = "TomerGlick", repository: String = "MacCleaner", session: URLSession = .shared) {
        self.owner = owner
        self.repository = repository
        self.session = session
    }

    private struct Response: Decodable {
        let tag_name: String
        let html_url: String
    }

    func latestRelease() async throws -> ReleaseInfo {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repository)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UpdateCheckError.badResponse
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let releaseURL = URL(string: decoded.html_url) else {
            throw UpdateCheckError.badResponse
        }

        return ReleaseInfo(version: decoded.tag_name, url: releaseURL)
    }
}

enum UpdateCheckError: Error {
    case badResponse
}

/// Checks whether a newer release exists, and remembers the answer.
///
/// Deliberately only *tells* you: it never downloads or installs. The app is distributed
/// as a DMG from GitHub, so the honest end of this flow is a link to the release page.
@MainActor
final class UpdateCheckService: ObservableObject {
    /// The newer release, when one exists. Nil means up to date or not yet checked.
    @Published private(set) var availableUpdate: ReleaseInfo?
    @Published private(set) var isChecking = false

    private let fetcher: ReleaseFetching
    private let currentVersion: String
    private let preferences: PreferencesService
    private let logger = Logger(subsystem: "com.macstoragecleanup.app", category: "updates")

    static let shared = UpdateCheckService()

    init(
        fetcher: ReleaseFetching = GitHubReleaseFetcher(),
        currentVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0",
        preferences: PreferencesService = .shared
    ) {
        self.fetcher = fetcher
        self.currentVersion = currentVersion
        self.preferences = preferences
    }

    /// Check at most once a day unless forced, so opening the app repeatedly does not
    /// hammer the API — GitHub rate-limits unauthenticated requests per address.
    func checkIfDue(force: Bool = false) async {
        guard force || preferences.checkForUpdatesAutomatically else { return }

        if !force, let last = preferences.lastUpdateCheck,
           Date().timeIntervalSince(last) < 24 * 60 * 60 {
            // Still surface a previously-found update rather than going quiet.
            restoreKnownUpdate()
            return
        }

        await check()
    }

    func check() async {
        isChecking = true
        defer { isChecking = false }

        do {
            let release = try await fetcher.latestRelease()
            preferences.lastUpdateCheck = Date()

            guard let latest = AppVersion(release.version), let current = AppVersion(currentVersion) else {
                logger.debug("Unparseable version, latest=\(release.version, privacy: .public) current=\(self.currentVersion, privacy: .public)")
                availableUpdate = nil
                return
            }

            if latest > current {
                logger.debug("Update available: \(latest.description, privacy: .public)")
                preferences.latestKnownVersion = release.version
                availableUpdate = release
            } else {
                preferences.latestKnownVersion = nil
                availableUpdate = nil
            }
        } catch {
            // A failed check is not worth bothering the user about; it retries tomorrow.
            logger.debug("Update check failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Re-surface an update found on an earlier launch, without a network round trip.
    private func restoreKnownUpdate() {
        guard let known = preferences.latestKnownVersion,
              let latest = AppVersion(known),
              let current = AppVersion(currentVersion),
              latest > current,
              let url = URL(string: "https://github.com/TomerGlick/MacCleaner/releases/latest") else {
            availableUpdate = nil
            return
        }

        availableUpdate = ReleaseInfo(version: known, url: url)
    }
}
