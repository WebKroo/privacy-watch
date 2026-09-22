// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 WebKroo

import Foundation
import Combine

struct ReleaseVersion: Equatable, Comparable {
    let major: Int
    let minor: Int
    let patch: Int
    init?(_ text: String) {
        let value = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let numbers = parts.compactMap { part -> Int? in
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  part.count == 1 || part.first != "0" else { return nil }
            return Int(part)
        }
        guard numbers.count == 3 else { return nil }
        (major, minor, patch) = (numbers[0], numbers[1], numbers[2])
    }
    var description: String { "\(major).\(minor).\(patch)" }
    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

enum UpdateFrequency: String, CaseIterable, Identifiable {
    case daily, weekly, monthly
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    func nextDate(after date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: self == .monthly ? .month : .day,
                      value: self == .weekly ? 7 : 1, to: date) ?? date.addingTimeInterval(86_400)
    }
    func isDue(lastAttempt: Date?, now: Date, calendar: Calendar = .current) -> Bool {
        guard let lastAttempt, lastAttempt <= now else { return true }
        return now >= nextDate(after: lastAttempt, calendar: calendar)
    }
}

struct PublishedRelease: Equatable {
    let tag: String
    let version: ReleaseVersion
    init?(tag: String) {
        guard let version = ReleaseVersion(tag) else { return nil }
        self.tag = tag; self.version = version
    }
    // Construct the destination ourselves; never open a URL supplied by the API.
    var pageURL: URL { URL(string: "https://github.com/WebKroo/privacy-watch/releases/tag/\(tag)")! }
}

enum ReleaseCheckError: LocalizedError {
    case invalidResponse, tooLarge, rateLimited, unavailable
    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "GitHub returned release information this version cannot read. Try again later."
        case .tooLarge: return "GitHub's release response was too large. Try again later."
        case .rateLimited: return "GitHub is limiting update checks. Please try again later."
        case .unavailable: return "GitHub is temporarily unavailable. Please try again later."
        }
    }
}

final class GitHubReleaseClient: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let endpoint = URL(string: "https://api.github.com/repos/WebKroo/privacy-watch/releases/latest")!
    static let maximumBytes = 1_048_576
    static func decode(_ data: Data, status: Int) throws -> PublishedRelease? {
        if status == 404 { return nil }
        if status == 403 || status == 429 { throw ReleaseCheckError.rateLimited }
        guard status == 200 else { throw ReleaseCheckError.unavailable }
        guard data.count <= maximumBytes else { throw ReleaseCheckError.tooLarge }
        struct Response: Decodable { let tag_name: String; let draft: Bool; let prerelease: Bool }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { throw ReleaseCheckError.invalidResponse }
        guard !response.draft, !response.prerelease else { return nil }
        guard let release = PublishedRelease(tag: response.tag_name) else { throw ReleaseCheckError.invalidResponse }
        return release
    }
    func latest() async throws -> PublishedRelease? {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: Self.endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Privacy-Watch-Updater", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, response.url == Self.endpoint else { throw ReleaseCheckError.invalidResponse }
        guard response.expectedContentLength <= Self.maximumBytes else { throw ReleaseCheckError.tooLarge }
        // Bound memory use even when a server omits Content-Length.
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < Self.maximumBytes else { throw ReleaseCheckError.tooLarge }
            data.append(byte)
        }
        return try Self.decode(data, status: response.statusCode)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // A repository move should be reviewed in a new build, not silently
        // redirect this privacy utility to a different owner or service.
        completionHandler(nil)
    }
}

@MainActor final class UpdateController: ObservableObject {
    @Published var automaticChecks: Bool {
        didSet {
            defaults.set(automaticChecks, forKey: "updates.enabled")
            if !automaticChecks, automaticRequest { cancelRequest() }
            schedule()
        }
    }
    @Published var frequency: UpdateFrequency {
        didSet { defaults.set(frequency.rawValue, forKey: "updates.frequency"); schedule() }
    }
    @Published private(set) var isChecking = false
    @Published private(set) var availableRelease: PublishedRelease?
    @Published private(set) var lastChecked: Date?
    @Published private(set) var message = "Check GitHub for a newer release."
    @Published private(set) var checkFailed = false
    @Published private(set) var nextCheck: Date?
    let installedVersion: String
    let allowsChecks: Bool
    private let defaults: UserDefaults
    private let fetch: () async throws -> PublishedRelease?
    private let now: () -> Date
    private let calendar: Calendar
    private let timersEnabled: Bool
    private var lastAttempt: Date?
    private var timer: Timer?
    private var request: Task<Void, Never>?
    private var requestID = UUID()
    private var automaticRequest = false
    private var started = false

    init(defaults: UserDefaults, installedVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0",
         allowsChecks: Bool = true, timersEnabled: Bool = true, now: @escaping () -> Date = Date.init,
         calendar: Calendar = .current, fetch: @escaping () async throws -> PublishedRelease? = { try await GitHubReleaseClient().latest() }) {
        self.defaults = defaults; self.installedVersion = installedVersion; self.allowsChecks = allowsChecks
        self.timersEnabled = timersEnabled; self.now = now; self.calendar = calendar; self.fetch = fetch
        automaticChecks = defaults.bool(forKey: "updates.enabled")
        frequency = UpdateFrequency(rawValue: defaults.string(forKey: "updates.frequency") ?? "") ?? .weekly
        lastAttempt = defaults.object(forKey: "updates.lastAttempt") as? Date
        lastChecked = defaults.object(forKey: "updates.lastChecked") as? Date
        if let tag = defaults.string(forKey: "updates.availableTag"), let release = PublishedRelease(tag: tag),
           let installed = ReleaseVersion(installedVersion), release.version > installed {
            availableRelease = release
            message = "Version \(release.version.description) is available."
        } else { defaults.removeObject(forKey: "updates.availableTag") }
        if !allowsChecks { message = "Update checks are disabled in preview." }
    }
    func start() { started = true; checkIfDue() }
    func checkIfDue() {
        guard started, allowsChecks, automaticChecks else { schedule(); return }
        if frequency.isDue(lastAttempt: lastAttempt, now: now(), calendar: calendar) { check(manual: false) }
        else { schedule() }
    }
    func check(manual: Bool = true) {
        guard allowsChecks, request == nil, manual || automaticChecks else { return }
        guard let installed = ReleaseVersion(installedVersion) else {
            message = "The installed version could not be read."; checkFailed = true; return
        }
        timer?.invalidate(); timer = nil
        lastAttempt = now(); defaults.set(lastAttempt, forKey: "updates.lastAttempt")
        isChecking = true; checkFailed = false; message = "Checking GitHub…"
        automaticRequest = !manual
        let token = UUID(); requestID = token
        request = Task { [weak self, fetch] in
            do {
                let release = try await fetch()
                try Task.checkCancellation()
                guard let self, self.requestID == token else { return }
                self.lastChecked = self.now(); self.defaults.set(self.lastChecked, forKey: "updates.lastChecked")
                if let release, release.version > installed {
                    self.availableRelease = release
                    self.defaults.set(release.tag, forKey: "updates.availableTag")
                    self.message = "Version \(release.version.description) is available."
                } else {
                    self.availableRelease = nil; self.defaults.removeObject(forKey: "updates.availableTag")
                    self.message = release == nil ? "No published release is available yet." : "You're up to date."
                }
            } catch {
                guard let self, self.requestID == token else { return }
                self.checkFailed = true
                self.message = (error as? ReleaseCheckError)?.localizedDescription ?? "Couldn't reach GitHub. Check your connection and try again."
            }
            guard let self, self.requestID == token else { return }
            self.isChecking = false; self.request = nil; self.automaticRequest = false; self.schedule()
        }
    }
    private func cancelRequest() {
        requestID = UUID(); request?.cancel(); request = nil; isChecking = false; automaticRequest = false
        message = "Automatic check canceled. You can still check manually."; checkFailed = false
    }
    private func schedule() {
        timer?.invalidate(); timer = nil; nextCheck = nil
        guard started, allowsChecks, automaticChecks, request == nil else { return }
        let date = now()
        let due = frequency.isDue(lastAttempt: lastAttempt, now: date, calendar: calendar)
        nextCheck = due ? date : frequency.nextDate(after: lastAttempt!, calendar: calendar)
        guard timersEnabled else { return }
        // Re-evaluate at least hourly so wall-clock changes do not strand a timer.
        let delay = max(1, min(3_600, nextCheck!.timeIntervalSince(date)))
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkIfDue() }
        }
        timer.tolerance = min(60, delay * 0.1)
        self.timer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    func shutDown() {
        started = false; timer?.invalidate(); timer = nil; nextCheck = nil
        requestID = UUID(); request?.cancel(); request = nil; isChecking = false
    }
}
