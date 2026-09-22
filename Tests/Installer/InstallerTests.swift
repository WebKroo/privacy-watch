// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 WebKroo

import Foundation

@main struct InstallerTests {
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else { fatalError("Pass the built helper path") }
        let source = URL(fileURLWithPath: CommandLine.arguments[1])
        guard let requirement = ServiceIdentity.codeRequirement(at: source) else { fatalError("Missing helper signature") }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MPA installer's test \(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let staged = folder.appendingPathComponent("collector")
        try FileManager.default.copyItem(at: source, to: staged)
        // Run the same shell fragment used before approval and in root staging,
        // including its argument quoting and universal-binary architecture choice.
        _ = try await LocalInstallation.run("/bin/sh", ["-c", LocalInstallation.verificationScript(quotedPath: LocalInstallation.quote(staged.path), requirement: requirement)])
        print("PASS actual installer verification of staged universal helper")
        let wrongHash = "identifier \"\(ServiceIdentity.collector)\" and cdhash H\"0000000000000000000000000000000000000000\""
        do {
            _ = try await LocalInstallation.run("/bin/sh", ["-c", LocalInstallation.verificationScript(quotedPath: LocalInstallation.quote(staged.path), requirement: wrongHash)])
        } catch {
            print("PASS installer rejects a different code hash")
            return
        }
        fatalError("Installer accepted an unapproved helper")
    }
}
