// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 WebKroo

import AppKit
import SwiftUI
import OSLog

final class Receiver: NSObject, EventReceiverProtocol {
    var events: ((Data) -> Void)?
    var failure: ((String) -> Void)?
    var snapshot: ((String) -> Void)?
    func receive(_ data: Data) { DispatchQueue.main.async { self.events?(data) } }
    func collectorFailed(_ message: String) { DispatchQueue.main.async { self.failure?(message) } }
    func observedSnapshot(_ timestamp: String) { DispatchQueue.main.async { self.snapshot?(timestamp) } }
}
@MainActor final class AppModel: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = AppModel()
    static var demoRequested: Bool { CommandLine.arguments.contains("--demo") || Bundle.main.object(forInfoDictionaryKey: "MPADemoPreview") as? Bool == true }
    @Published var running = false
    @Published var busy = false
    @Published var status = "Paused"
    @Published var issue: String?
    @Published var lastSnapshot = "Waiting for a verified sensor update"
    @Published var events: [SensorEvent] = []
    @Published var folder: URL
    @Published var enabled: Set<Sensor>
    @Published var menuHistory: MenuHistoryFilter { didSet { menuHistory.save(to: defaults) } }
    var menuEvents: [SensorEvent] { menuHistory.recentEvents(in: events) }
    @Published var notifyMic: Bool { didSet { defaults.set(notifyMic, forKey: "notifyMic") } }
    @Published var notifyCam: Bool { didSet { defaults.set(notifyCam, forKey: "notifyCam") } }
    @Published var backup: Bool { didSet { defaults.set(backup, forKey: "backup") } }
    @Published var startLoggingOnLaunch: Bool { didSet { defaults.set(startLoggingOnLaunch, forKey: "startLoggingOnLaunch") } }
    @Published var showMenuBarIcon: Bool { didSet { defaults.set(showMenuBarIcon, forKey: "showMenuBarIcon") } }
    @Published var showDockIcon: Bool { didSet { defaults.set(showDockIcon, forKey: "showDockIcon") } }
    @Published private(set) var activityWindowOpen = false
    @Published var selectedTab = 0
    @Published var notificationStatus = "Checking notification permission…"
    let preview = AppModel.demoRequested
    let defaults: UserDefaults
    let updates: UpdateController
    let notifications = NotificationManager()
    // Transport seam for the isolated XPC lifecycle test; production always
    // uses the authenticated, installed Mach service below.
    var connectionFactory: () -> NSXPCConnection = {
        NSXPCConnection(machServiceName: ServiceIdentity.collector, options: .privileged)
    }
    private var connection: NSXPCConnection?
    private var heartbeat: Timer?
    private var generation = UUID()
    private var lastPong = AwakeDeadline()
    @Published private var recovery = LoggingRecovery()
    private var reconnectTask: DispatchWorkItem?
    private var reconnectGeneration = UUID()
    private let lifecycleLog = Logger(subsystem: ServiceIdentity.app, category: "lifecycle")
    var loggingRequested: Bool { recovery.requested }
    private var folderAccess = false
    private var loggingActivity: NSObjectProtocol?
    private var activityWindow: NSWindow?
    private var stopping = false
    private var stopCompletions: [(Bool) -> Void] = []
    var store: LogStore { LogStore(folder: folder) }
    var signed: Bool { true }
    var helperStatus: String { LocalInstallation.installed ? "Local collector installed" : "Setup required" }
    var startTitle: String { LocalInstallation.installed ? "Resume Logging" : "Set Up & Start Logging" }
    private override init() {
        let demo = AppModel.demoRequested
        defaults = demo ? UserDefaults(suiteName: "com.norek.macprivacyactivity.local.preview")! : .standard
        updates = UpdateController(defaults: defaults, allowsChecks: !demo)
        folder = URL(fileURLWithPath: defaults.string(forKey: "folder") ?? NSHomeDirectory() + "/Documents/Logs/Mac Privacy Activity Local", isDirectory: true)
        enabled = Set((defaults.array(forKey: "sensors") as? [String] ?? Sensor.allCases.map(\.rawValue)).compactMap(Sensor.init))
        menuHistory = MenuHistoryFilter(defaults: defaults)
        notifyMic = defaults.object(forKey: "notifyMic") as? Bool ?? true
        notifyCam = defaults.object(forKey: "notifyCam") as? Bool ?? true
        backup = defaults.bool(forKey: "backup")
        showMenuBarIcon = defaults.object(forKey: "showMenuBarIcon") as? Bool ?? true
        showDockIcon = defaults.object(forKey: "showDockIcon") as? Bool ?? false
        startLoggingOnLaunch = defaults.object(forKey: "startLoggingOnLaunch") as? Bool ?? true
        super.init()
        if !demo, let bookmark = defaults.data(forKey: "folderBookmark") {
            var stale = false
            do {
                let resolved = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
                folder = resolved; folderAccess = resolved.startAccessingSecurityScopedResource()
                if stale {
                    defaults.set(try resolved.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil), forKey: "folderBookmark")
                }
            } catch {
                issue = "Access to the saved log folder needs to be renewed. In Settings, choose the same folder again. Your existing history is preserved."
            }
        }
        if !demo {
            notifications.openCSV = { [weak self] in self?.openCSV() }
            notifications.report = { [weak self] in self?.notificationStatus = $0 }
            notifications.configure()
            reloadHistory()
        } else {
            status = "Preview • sample events"
            notificationStatus = "Preview only — no notifications are sent."
            events = Self.sampleEvents
        }
    }
    func didLaunch(showWindow: Bool) {
        updates.start()
        if showWindow { showActivity() }
        guard !preview, startLoggingOnLaunch else { return }
        // Only a fresh process launch resumes automatically. Opening the window
        // again must not override an explicit Pause in the current session.
        guard LocalInstallation.installed else {
            status = "Setup required"
            issue = "Automatic logging is enabled. Click Set Up & Start Logging once to approve this version. Future launches will start logging automatically."
            return
        }
        start()
    }
    func showAllActivity() { selectedTab = 0; showActivity() }
    func showSettings() {
        selectedTab = 1; showActivity()
        if !preview { notifications.refreshAuthorizationStatus() }
    }
    func showActivity() {
        if activityWindow == nil {
            let controller = NSHostingController(rootView: ActivityView(model: self))
            let window = NSWindow(contentViewController: controller)
            window.title = "Privacy Watch"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 1080, height: 730))
            window.contentMinSize = NSSize(width: 900, height: 620)
            window.isReleasedWhenClosed = false
            window.delegate = self
            let frameName = preview ? "PrivacyWatch.PreviewWindow" : "PrivacyWatch.ActivityWindow"
            if !window.setFrameUsingName(frameName) { window.center() }
            window.setFrameAutosaveName(frameName)
            activityWindow = window
        }
        activityWindowOpen = true
        NSApp.setActivationPolicy(.regular)
        activityWindow?.deminiaturize(nil)
        activityWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === activityWindow else { return }
        activityWindowOpen = false
    }
    func toggle(_ sensor: Sensor, value: Bool) {
        if value { enabled.insert(sensor) } else { enabled.remove(sensor) }
        defaults.set(enabled.map(\.rawValue), forKey: "sensors")
    }
    func chooseFolder() {
        guard !busy, !loggingRequested else { return }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.prompt = "Use Log Folder"; panel.directoryURL = folder
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            // Resolve a durable bookmark before replacing the previous scope.
            // Keeping the resolved URL alive avoids relying on the panel's
            // temporary access, and bookmark failures must not be swallowed.
            let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            var stale = false
            let resolved = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
            let access = resolved.startAccessingSecurityScopedResource()
            do { try LogStore(folder: resolved).prepare(backup: backup) }
            catch { if access { resolved.stopAccessingSecurityScopedResource() }; throw error }
            if folderAccess { folder.stopAccessingSecurityScopedResource() }
            folder = resolved; folderAccess = access
            defaults.set(resolved.path, forKey: "folder")
            defaults.set(bookmark, forKey: "folderBookmark")
            issue = nil; reloadHistory()
        } catch { issue = error.localizedDescription }
    }
    func reloadHistory() {
        do { events = try store.recentEvents() } catch { issue = error.localizedDescription }
    }
    func openCSV() {
        do { try store.prepare(backup: backup); if !NSWorkspace.shared.open(store.csvURL) { issue = "No app is configured to open CSV files." } }
        catch { issue = error.localizedDescription }
    }
    func revealFolder() { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
    func approveHelper() { installCollector() }
    func installCollector() {
        guard !preview, !busy, !running else { return }
        recovery.userStarted(); cancelReconnect()
        busy = true; issue = nil; status = "Waiting for administrator approval…"
        Task {
            do {
                try await LocalInstallation.install()
                busy = false; status = "Ready"
                if recovery.shouldReconnect { startSession(automatic: true) }
            } catch {
                recovery.userStopped(); cancelReconnect()
                busy = false; status = "Setup not completed"; issue = error.localizedDescription
            }
        }
    }
    func restoreOriginal() {
        guard !preview, !busy, !loggingRequested else { return }
        busy = true
        Task {
            do { try await LocalInstallation.restoreOriginal(); status = "Original logger restored"; issue = "The original logger is running independently. Its existing notification watcher now displays AM/PM." }
            catch { issue = error.localizedDescription }
            busy = false
        }
    }
    func enableNotifications() { if !preview { notifications.requestAuthorization() } }
    func start() {
        guard !preview, !busy, !running else { return }
        recovery.userStarted()
        cancelReconnect()
        startSession(automatic: false)
    }
    private func startSession(automatic: Bool) {
        guard recovery.shouldReconnect, !busy, !running else { return }
        guard LocalInstallation.installed else {
            if automatic { fail("This version needs approval. In Settings, install or repair the local collector, then resume logging.") }
            else { installCollector() }
            return
        }
        guard let helperRequirement = ServiceIdentity.helperRequirement else { fail("Cannot verify the bundled local collector."); return }
        do { try store.prepare(backup: backup) } catch { fail(error.localizedDescription); return }
        issue = nil; busy = true; status = automatic ? "Reconnecting…" : "Starting…"
        let token = UUID(); generation = token
        // Keep callbacks from a retired session from affecting its replacement.
        let receiver = Receiver()
        receiver.events = { [weak self] data in
            guard let self, self.generation == token else { return }; self.ingest(data)
        }
        receiver.failure = { [weak self] message in
            guard let self, self.generation == token else { return }; self.recoverConnection(message)
        }
        receiver.snapshot = { [weak self] stamp in
            guard let self, self.generation == token else { return }; self.lastSnapshot = stamp
        }
        let c = connectionFactory()
        c.setCodeSigningRequirement(helperRequirement)
        c.remoteObjectInterface = NSXPCInterface(with: CollectorProtocol.self)
        c.exportedInterface = NSXPCInterface(with: EventReceiverProtocol.self); c.exportedObject = receiver
        c.invalidationHandler = { [weak self] in DispatchQueue.main.async {
            guard let self, self.generation == token else { return }
            self.recoverConnection("The log reader disconnected.")
        } }
        c.interruptionHandler = c.invalidationHandler
        connection = c; c.resume()
        keepLoggingResponsive()
        guard let proxy = c.remoteObjectProxyWithErrorHandler({ [weak self] error in
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }; self.recoverConnection(error.localizedDescription)
            }
        }) as? CollectorProtocol else { recoverConnection("Cannot connect to the log reader."); return }
        proxy.start(version: ServiceIdentity.protocolVersion) { [weak self] error in
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                if let error { self.recoverConnection(error); return }
                self.running = true; self.busy = false; self.status = "Logging"; self.lastPong.renew()
                self.recovery.connected()
                self.lifecycleLog.info("Logging session connected")
                self.lastSnapshot = "Waiting for a verified sensor update"
                let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
                    Task { @MainActor in self?.ping(token: token) }
                }
                self.heartbeat = timer
                RunLoop.main.add(timer, forMode: .common)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self, self.generation == token, self.busy else { return }
            self.recoverConnection("The log reader did not respond.")
        }
    }
    private func ping(token: UUID) {
        guard generation == token, recovery.shouldReconnect else { return }
        if lastPong.expired(after: 8) { recoverConnection("The log reader stopped responding."); return }
        (connection?.remoteObjectProxyWithErrorHandler({ [weak self] error in
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }; self.recoverConnection(error.localizedDescription)
            }
        }) as? CollectorProtocol)?.heartbeat { [weak self] alive in
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                if alive { self.lastPong.renew() } else { self.recoverConnection("The log reader stopped.") }
            }
        }
    }
    private func keepLoggingResponsive() {
        guard loggingActivity == nil else { return }
        loggingActivity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Record the privacy activity requested by the user")
    }
    private func cancelReconnect() {
        reconnectGeneration = UUID()
        reconnectTask?.cancel(); reconnectTask = nil
    }
    private func scheduleReconnect() {
        guard recovery.requested else { return }
        guard !recovery.sleeping else { status = "Sleeping"; return }
        guard !busy, !running, reconnectTask == nil, let delay = recovery.nextRetryDelay() else { return }
        status = "Reconnecting…"
        keepLoggingResponsive()
        let token = UUID(); reconnectGeneration = token
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.reconnectGeneration == token, self.recovery.shouldReconnect else { return }
            self.reconnectTask = nil
            self.startSession(automatic: true)
        }
        reconnectTask = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
    private func recoverConnection(_ message: String) {
        guard recovery.requested else { return }
        lifecycleLog.notice("Log reader interrupted; recovering automatically")
        issue = message + " Retrying automatically."
        stopSession { [weak self] success in
            guard let self else { return }
            if success { self.scheduleReconnect() }
            else { self.recovery.userStopped(); self.cancelReconnect() }
        }
    }
    func systemWillSleep() {
        guard !preview else { return }
        recovery.willSleep(); cancelReconnect()
        guard recovery.requested else { return }
        lifecycleLog.info("System sleeping; stopping the reader while preserving logging intent")
        // No synthetic STOP events are written. Wake begins a new observation
        // period, so its first snapshot is correctly labelled First seen.
        stopSession { [weak self] success in
            guard let self else { return }
            if success { self.scheduleReconnect() }
            else { self.recovery.userStopped(); self.cancelReconnect() }
        }
    }
    func systemDidWake() {
        updates.checkIfDue()
        guard !preview else { return }
        recovery.didWake(); cancelReconnect(); lastPong.renew()
        guard recovery.requested else { return }
        lifecycleLog.info("System awake; restoring requested logging")
        // A wake can arrive while sleep cleanup is still awaiting its reply.
        // That cleanup also reconciles intent, so the wake cannot be lost.
        guard !stopping, !(busy && connection == nil) else { return }
        if connection != nil || running {
            // Reopen the stream even if no will-sleep notification arrived.
            stopSession { [weak self] success in
                guard let self else { return }
                if success { self.scheduleReconnect() }
                else { self.recovery.userStopped(); self.cancelReconnect() }
            }
        } else { scheduleReconnect() }
    }
    private func ingest(_ data: Data) {
        guard running, data.count <= 1_048_576, let batch = try? JSONDecoder().decode([SensorEvent].self, from: data) else { return }
        for var event in batch where enabled.contains(event.sensor) {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: event.bundleID) {
                event.appName = (Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ?? url.deletingPathExtension().lastPathComponent
            } else { event.appName = event.bundleID }
            event.appName = event.appName.components(separatedBy: .newlines).joined(separator: " ")
            do { try store.append(event, backup: backup) }
            catch { fail(error.localizedDescription); return }
            events.insert(event, at: 0); if events.count > 2000 { events.removeLast(events.count - 2000) }
            if event.action == .start && ((event.sensor == .mic && notifyMic) || (event.sensor == .cam && notifyCam)) { notifications.send(event) }
        }
    }
    private func fail(_ message: String) {
        issue = message
        stop { _ in }
    }
    // On stop, the reader is reaped and the helper exits. The registered service
    // remains dormant, ready for Resume without another administrator prompt.
    func stop(completion: @escaping (Bool) -> Void) {
        // Explicit Pause and Quit cancel intent before any asynchronous cleanup.
        recovery.userStopped(); cancelReconnect()
        lifecycleLog.info("Logging explicitly stopped")
        stopSession(completion: completion)
    }
    private func stopSession(completion: @escaping (Bool) -> Void) {
        guard !preview else { completion(true); return }
        if stopping { stopCompletions.append(completion); return }
        guard !(busy && connection == nil) else {
            issue = "Finish or cancel the administrator setup dialog before quitting."
            completion(false); return
        }
        stopping = true; stopCompletions.append(completion)
        running = false; busy = true; status = "Stopping…"; generation = UUID()
        heartbeat?.invalidate(); heartbeat = nil
        if let loggingActivity { ProcessInfo.processInfo.endActivity(loggingActivity); self.loggingActivity = nil }
        let c = connection; connection = nil
        var completed = false
        let finish: () -> Void = { [weak self] in
            guard let self, !completed else { return }; completed = true
            c?.invalidate()
            Task { @MainActor in
                // Sleep can occur between the stop acknowledgement and the
                // helper's deferred exit. Confirm shutdown over awake time,
                // rather than trusting one wall-clock-delayed observation.
                let deadline = AwakeDeadline()
                var alive = await LocalInstallation.helperIsRunning()
                // A refused/unowned session can acknowledge stop without
                // exiting until the helper's 15-second idle timer fires.
                while alive && !deadline.expired(after: 18) {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    alive = await LocalInstallation.helperIsRunning()
                }
                self.busy = false; self.stopping = false
                if alive {
                    self.status = "Stop needs attention"
                    self.issue = "The local helper still appears to be running. Retry Quit & Stop Logging. The app will remain open until shutdown is confirmed."
                } else { self.status = "Paused" }
                let callbacks = self.stopCompletions; self.stopCompletions.removeAll()
                callbacks.forEach { $0(!alive) }
            }
        }
        guard let c else { finish(); return }
        if let proxy = c.remoteObjectProxyWithErrorHandler({ _ in DispatchQueue.main.async { finish() } }) as? CollectorProtocol {
            proxy.stop { DispatchQueue.main.async { finish() } }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { finish() }
        } else { finish() }
    }
    func quit() { NSApp.terminate(nil) }
    static var sampleEvents: [SensorEvent] {
        [SensorEvent(timestamp: "2026-09-18 20:14:32.473921-0400", sensor: .mic, action: .start, bundleID: "com.apple.VoiceMemos", appName: "Voice Memos"),
         SensorEvent(timestamp: "2026-09-18 20:12:08.216030-0400", sensor: .cam, action: .stop, bundleID: "com.apple.FaceTime", appName: "FaceTime"),
         SensorEvent(timestamp: "2026-09-18 20:11:52.044185-0400", sensor: .cam, action: .start, bundleID: "com.apple.FaceTime", appName: "FaceTime"),
         SensorEvent(timestamp: "2026-09-18 20:10:07.340289-0400", sensor: .scr, action: .start, bundleID: "pl.maketheweb.cleanshotx", appName: "CleanShot X"),
         SensorEvent(timestamp: "2026-09-18 20:08:16.947502-0400", sensor: .loc, action: .stop, bundleID: "com.apple.weather", appName: "Weather"),
         SensorEvent(timestamp: "2026-09-18 20:07:01.014921-0400", sensor: .loc, action: .start, bundleID: "com.apple.weather", appName: "Weather", observation: "first-observed"),
         SensorEvent(timestamp: "2026-09-18 20:05:09.441102-0400", sensor: .mic, action: .stop, bundleID: "com.apple.VoiceMemos", appName: "Voice Memos")]
    }
}
