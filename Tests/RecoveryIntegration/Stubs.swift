// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 WebKroo

import AppKit
import SwiftUI

// The integration executable deliberately does not link the real installer,
// notification manager, IPC identity, app entry point, or UI. Its anonymous XPC
// server runs as the current user and never launches /usr/bin/log.
enum ServiceIdentity {
    static let app = "com.norek.privacywatch.recovery-integration-tests"
    static let collector = app + ".anonymous-collector"
    static let protocolVersion = 1
    static var helperRequirement: String? { "identifier \"\(app)\"" }
}

@objc protocol CollectorProtocol {
    func start(version: Int, withReply reply: @escaping (String?) -> Void)
    func heartbeat(withReply reply: @escaping (Bool) -> Void)
    func stop(withReply reply: @escaping () -> Void)
}

@objc protocol EventReceiverProtocol {
    func receive(_ data: Data)
    func collectorFailed(_ message: String)
    func observedSnapshot(_ timestamp: String)
}

enum UnexpectedInstallation: Error { case prohibited }

@MainActor enum LocalInstallation {
    static let installed = true
    static var helperIsRunningHandler: () -> Bool = { false }
    static func helperIsRunning() async -> Bool { helperIsRunningHandler() }
    static func install() async throws { throw UnexpectedInstallation.prohibited }
    static func restoreOriginal() async throws { throw UnexpectedInstallation.prohibited }
}

final class NotificationManager {
    var openCSV: (() -> Void)?
    var report: ((String) -> Void)?
    func configure() {}
    func refreshAuthorizationStatus() {}
    func requestAuthorization() {}
    func send(_ event: SensorEvent) {}
}

struct ActivityView: View {
    let model: AppModel
    var body: some View { Text("Recovery integration test") }
}
