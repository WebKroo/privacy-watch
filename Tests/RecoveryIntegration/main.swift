// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 WebKroo

import AppKit
import Foundation

final class FakeCollectorServer: NSObject, NSXPCListenerDelegate {
    let listener = NSXPCListener.anonymous()
    // Mutable test state is accessed only on the main queue.
    var sessions: [FakeSession] = []
    var startCount = 0
    var stopCount = 0
    var stopReplyDelay: TimeInterval = 0.08
    var stopExitDelay: TimeInterval = 0

    override init() {
        super.init()
        listener.delegate = self
        listener.resume()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        let session = FakeSession(server: self, connection: connection)
        connection.exportedInterface = NSXPCInterface(with: CollectorProtocol.self)
        connection.remoteObjectInterface = NSXPCInterface(with: EventReceiverProtocol.self)
        connection.exportedObject = session
        connection.invalidationHandler = { [weak session] in
            DispatchQueue.main.async { session?.active = false }
        }
        DispatchQueue.main.async { self.sessions.append(session) }
        connection.resume()
        return true
    }

    var activeSession: FakeSession? { sessions.last(where: { $0.active }) }
    var helperIsRunning: Bool { sessions.contains(where: { $0.active || $0.awaitingExit }) }

    func close() {
        for session in sessions { session.connection.invalidate() }
        listener.invalidate()
    }
}

final class FakeSession: NSObject, CollectorProtocol {
    weak var server: FakeCollectorServer?
    let connection: NSXPCConnection
    var active = false
    var awaitingExit = false

    init(server: FakeCollectorServer, connection: NSXPCConnection) {
        self.server = server
        self.connection = connection
    }

    func start(version: Int, withReply reply: @escaping (String?) -> Void) {
        DispatchQueue.main.async {
            guard version == ServiceIdentity.protocolVersion else { reply("Test protocol mismatch"); return }
            self.active = true
            self.server?.startCount += 1
            reply(nil)
        }
    }

    func heartbeat(withReply reply: @escaping (Bool) -> Void) {
        DispatchQueue.main.async { reply(self.active) }
    }

    func stop(withReply reply: @escaping () -> Void) {
        DispatchQueue.main.async {
            self.active = false
            self.server?.stopCount += 1
            if let exitDelay = self.server?.stopExitDelay, exitDelay > 0 {
                self.awaitingExit = true
                DispatchQueue.main.asyncAfter(deadline: .now() + exitDelay) { self.awaitingExit = false }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + (self.server?.stopReplyDelay ?? 0)) { reply() }
        }
    }

    func failStream() {
        active = false
        (connection.remoteObjectProxyWithErrorHandler { _ in } as? EventReceiverProtocol)?
            .collectorFailed("Simulated log-stream interruption")
    }
}

struct IntegrationFailure: Error, CustomStringConvertible {
    let description: String
}

@MainActor enum Integration {
    static var passed = 0

    static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw IntegrationFailure(description: message) }
    }

    static func waitUntil(_ description: String, timeout: TimeInterval = 8,
                          _ condition: @escaping @MainActor () -> Bool) async throws {
        let deadline = AwakeDeadline()
        while !condition() {
            if deadline.expired(after: timeout) { throw IntegrationFailure(description: "Timed out: \(description)") }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    static func delay(_ seconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    static func pass(_ label: String) {
        passed += 1
        print("PASS \(label)")
    }

    static func run() async -> Int32 {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PrivacyWatch-Recovery-Integration-\(UUID().uuidString)", isDirectory: true)
        let server = FakeCollectorServer()
        defer {
            server.close()
            try? FileManager.default.removeItem(at: folder)
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            // Registration is memory-only: no real app defaults, saved bookmarks,
            // login items, notification authorization, or log folders are changed.
            UserDefaults.standard.register(defaults: [
                "folder": folder.path, "backup": false,
                "notifyMic": false, "notifyCam": false,
                "startLoggingOnLaunch": false
            ])
            let model = AppModel.shared
            try check(model.folder.standardizedFileURL == folder.standardizedFileURL, "The harness must use only its temporary log folder")
            var clientConnections: [NSXPCConnection] = []
            model.connectionFactory = {
                let connection = NSXPCConnection(listenerEndpoint: server.listener.endpoint)
                clientConnections.append(connection)
                return connection
            }
            LocalInstallation.helperIsRunningHandler = { server.helperIsRunning }

            model.start()
            try await waitUntil("first anonymous XPC session connects") { model.running && server.startCount == 1 }
            try check(model.loggingRequested && server.helperIsRunning, "Explicit Start must establish intent and a live fake collector")
            guard let firstReceiver = clientConnections.last?.exportedObject as? Receiver else {
                throw IntegrationFailure(description: "The actual AppModel must export its per-session Receiver")
            }
            pass("actual AppModel connects through anonymous XPC with code-signature verification")

            // Wake is delivered while the asynchronous stop acknowledgment is
            // still pending. Its completion must reconcile the retained intent.
            server.stopExitDelay = 3.6
            model.systemWillSleep()
            try check(model.loggingRequested && !model.running, "Sleep must stop observation while preserving requested logging")
            model.systemDidWake()
            try await delay(0.65)
            try check(model.loggingRequested && !model.running && model.busy && server.startCount == 1,
                      "An acknowledged stop with a still-exiting helper must retain intent and await confirmation")
            try await waitUntil("wake arriving during stop cleanup reconnects") { model.running && server.startCount == 2 }
            try check(server.stopCount >= 1, "Sleep must actually ask the fake reader to stop")
            server.stopExitDelay = 0
            pass("helper exit delayed beyond three seconds is awaited without clearing logging intent")
            pass("wake during asynchronous sleep cleanup restores logging automatically")

            let currentReceiver = clientConnections.last!.exportedObject as! Receiver
            currentReceiver.observedSnapshot("current-session")
            try await delay(0.05)
            firstReceiver.observedSnapshot("stale-session")
            firstReceiver.collectorFailed("Stale session must not stop the replacement")
            let staleEvent = SensorEvent(timestamp: "2026-09-20 01:00:00.000000-0400", sensor: .mic, action: .start, bundleID: "example.stale", appName: "Stale")
            firstReceiver.receive(try JSONEncoder().encode([staleEvent]))
            try await delay(0.1)
            try check(model.running && model.loggingRequested && model.issue == nil, "Retired-session failure must not affect the replacement")
            try check(model.lastSnapshot == "current-session" && model.events.isEmpty, "Retired-session events and snapshots must be ignored")
            pass("late failure, event and snapshot callbacks from a retired session are ignored")

            let startsBeforePause = server.startCount
            model.systemWillSleep()
            model.stop { _ in }
            model.systemDidWake()
            try await waitUntil("explicit Pause finishes during sleep cleanup") { !model.busy }
            try await delay(1.2)
            try check(!model.loggingRequested && !model.running && server.startCount == startsBeforePause,
                      "Pause during sleep must veto wake's reconnect")
            pass("Pause during sleep cleanup remains paused after wake")

            model.start()
            try await waitUntil("manual resume connects") { model.running }
            let startsBeforeInterruption = server.startCount
            guard let interruptedSession = server.activeSession else { throw IntegrationFailure(description: "Missing active fake session") }
            interruptedSession.failStream()
            try await waitUntil("real XPC failure callback causes successful automatic reconnect") {
                model.running && server.startCount == startsBeforeInterruption + 1
            }
            try check(model.loggingRequested && model.issue == nil, "Successful recovery must retain intent and clear the transient issue")
            pass("a real asynchronous XPC stream-failure callback recovers without user action")

            guard let pendingSession = server.activeSession else { throw IntegrationFailure(description: "Missing session before pending-retry test") }
            pendingSession.failStream()
            try await waitUntil("retry is pending after cleanup") { !model.running && !model.busy && model.loggingRequested }
            let startsBeforeStop = server.startCount
            model.stop { _ in } // The same entry point used by Pause and Quit.
            try await waitUntil("explicit Stop confirms cleanup") { !model.busy }
            try await delay(1.3)
            try check(!model.loggingRequested && !model.running && server.startCount == startsBeforeStop,
                      "A queued retry must not undo explicit Stop")
            pass("Pause/Quit stop entry point cancels an already scheduled retry")

            model.start()
            try await waitUntil("final session connects before disconnect test") { model.running }
            let startsBeforeDisconnect = server.startCount
            server.activeSession?.connection.invalidate()
            try await waitUntil("actual XPC invalidation reconnects") {
                model.running && server.startCount == startsBeforeDisconnect + 1
            }
            pass("actual XPC connection invalidation recovers automatically")

            var stopResult: Bool?
            model.stop { stopResult = $0 }
            try await waitUntil("final clean stop") { stopResult != nil }
            try check(stopResult == true && !server.helperIsRunning && !model.loggingRequested, "Final shutdown must leave no fake reader or reconnect intent")
            pass("final shutdown confirms that the test reader has stopped")
            print("\(passed) AppModel integration tests, 0 failures")
            return 0
        } catch {
            print("FAIL AppModel integration: \(error)")
            print("State: \(AppModel.shared.status); requested=\(AppModel.shared.loggingRequested); busy=\(AppModel.shared.busy); sessions=\(server.sessions.count); starts=\(server.startCount); issue=\(AppModel.shared.issue ?? "none")")
            print("\(passed) AppModel integration tests passed before failure")
            return 1
        }
    }
}

@main struct RecoveryIntegrationMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        DispatchQueue.main.async {
            Task { @MainActor in exit(await Integration.run()) }
        }
        // Run the actual main run loop, including AppModel's heartbeat Timer.
        app.run()
    }
}
