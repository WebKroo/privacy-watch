// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 WebKroo

import AppKit

struct LocalInstallation {
    static func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    static func verificationScript(quotedPath: String, requirement: String) -> String {
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        // codesign treats -R's value as a filename unless it begins with '='.
        // A CDHash identifies one architecture, so verify all signatures first,
        // then enforce the approved hash for the executing architecture.
        return """
        set -e
        /usr/bin/codesign --verify --strict \(quotedPath)
        /usr/bin/codesign --verify --strict --architecture \(architecture) \(quote("-R=" + requirement)) \(quotedPath)
        """
    }
    static var installed: Bool {
        guard let expected = ServiceIdentity.clientRequirement,
              let data = try? Data(contentsOf: URL(fileURLWithPath: ServiceIdentity.policyPath)),
              let policy = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String],
              policy["State"] == "active",
              policy["ClientRequirement"] == expected,
              ServiceIdentity.codeRequirement(at: URL(fileURLWithPath: ServiceIdentity.installedHelper)) == ServiceIdentity.helperRequirement else { return false }
        return true
    }
    static func run(_ executable: String, _ arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let task = Process(); let output = Pipe(); let error = Pipe()
            task.executableURL = URL(fileURLWithPath: executable); task.arguments = arguments
            task.standardOutput = output; task.standardError = error
            task.terminationHandler = { p in
                let out = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                let err = String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                if p.terminationStatus == 0 { continuation.resume(returning: out) }
                else { continuation.resume(throwing: StoreError.message(err.isEmpty ? "The system command failed (\(p.terminationStatus))." : err)) }
            }
            do { try task.run() } catch { continuation.resume(throwing: error) }
        }
    }
    static func authorize(_ script: String) async throws {
        _ = try await run("/usr/bin/osascript", ["-e", "on run argv", "-e", "do shell script (item 1 of argv) with administrator privileges", "-e", "end run", script])
    }
    static func install() async throws {
        guard let client = ServiceIdentity.clientRequirement, let helper = ServiceIdentity.helperRequirement else { throw StoreError.message("The local app signature is missing. Rebuild the app before installing its collector.") }
        // Exercise the same verification before requesting administrator access.
        _ = try await run("/bin/sh", ["-c", verificationScript(quotedPath: quote(ServiceIdentity.bundledHelper.path), requirement: helper)])
        let policy = try PropertyListSerialization.data(fromPropertyList: ["ClientRequirement": client, "State": "active"], format: .xml, options: 0).base64EncodedString()
        let launch: [String: Any] = ["Label": ServiceIdentity.collector, "ProgramArguments": [ServiceIdentity.installedHelper], "MachServices": [ServiceIdentity.collector: true], "RunAtLoad": false, "KeepAlive": false, "AbandonProcessGroup": false, "ExitTimeOut": 5]
        let plist = try PropertyListSerialization.data(fromPropertyList: launch, format: .xml, options: 0).base64EncodedString()
        // Copy into root-only staging and verify the exact helper before installing.
        let script = """
        set -eu
        support='/Library/Application Support/Mac Privacy Activity Local'
        helper=\(quote(ServiceIdentity.installedHelper))
        plist='/Library/LaunchDaemons/\(ServiceIdentity.plist)'
        if [ -L "$support" ] || [ -L /Library/PrivilegedHelperTools ]; then echo 'Unsafe installation path.' >&2; exit 1; fi
        /usr/bin/install -d -o root -g wheel -m 755 /Library/PrivilegedHelperTools "$support"
        stage=$(/usr/bin/mktemp -d /Library/PrivilegedHelperTools/.mpa-local.XXXXXX)
        trap '/bin/rm -rf "$stage"' EXIT
        /usr/bin/install -o root -g wheel -m 755 \(quote(ServiceIdentity.bundledHelper.path)) "$stage/collector"
        \(verificationScript(quotedPath: "\"$stage/collector\"", requirement: helper))
        /usr/bin/printf '%s' \(quote(policy)) | /usr/bin/base64 -D > "$stage/Client.plist"
        /usr/bin/printf '%s' \(quote(plist)) | /usr/bin/base64 -D > "$stage/Launch.plist"
        /bin/chmod 644 "$stage/Client.plist" "$stage/Launch.plist"
        if /bin/launchctl print system/\(ServiceIdentity.collector) >/dev/null 2>&1; then /bin/launchctl bootout system/\(ServiceIdentity.collector); fi
        /usr/bin/install -o root -g wheel -m 755 "$stage/collector" "$helper"
        /usr/bin/install -o root -g wheel -m 644 "$stage/Client.plist" "$support/Client.plist"
        /usr/bin/install -o root -g wheel -m 644 "$stage/Launch.plist" "$plist"
        /bin/launchctl enable system/\(ServiceIdentity.collector)
        /bin/launchctl bootstrap system "$plist"
        /bin/launchctl print system/\(ServiceIdentity.collector) >/dev/null
        if [ -f /Library/LaunchDaemons/local.privacy-sensors.logger.plist ]; then
          /bin/launchctl disable system/local.privacy-sensors.logger
          if /bin/launchctl print system/local.privacy-sensors.logger >/dev/null 2>&1; then /bin/launchctl bootout system/local.privacy-sensors.logger; fi
        fi
        """
        try await authorize(script)
        _ = try? await run("/bin/launchctl", ["disable", "gui/\(getuid())/local.privacy-sensors.notify"])
        _ = try? await run("/bin/launchctl", ["bootout", "gui/\(getuid())/local.privacy-sensors.notify"])
    }
    static func restoreOriginal() async throws {
        let script = """
        set -eu
        test -f /Library/LaunchDaemons/local.privacy-sensors.logger.plist
        if /bin/launchctl print system/\(ServiceIdentity.collector) >/dev/null 2>&1; then /bin/launchctl bootout system/\(ServiceIdentity.collector); fi
        /bin/launchctl disable system/\(ServiceIdentity.collector)
        if [ -f \(quote(ServiceIdentity.policyPath)) ]; then /usr/libexec/PlistBuddy -c 'Set :State inactive' \(quote(ServiceIdentity.policyPath)); fi
        /bin/launchctl enable system/local.privacy-sensors.logger
        if ! /bin/launchctl print system/local.privacy-sensors.logger >/dev/null 2>&1; then /bin/launchctl bootstrap system /Library/LaunchDaemons/local.privacy-sensors.logger.plist; fi
        """
        try await authorize(script)
        _ = try await run("/bin/launchctl", ["enable", "gui/\(getuid())/local.privacy-sensors.notify"])
        let watcher = NSHomeDirectory() + "/Library/LaunchAgents/local.privacy-sensors.notify.plist"
        _ = try? await run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", watcher])
    }
    static func helperIsRunning() async -> Bool {
        do {
            let text = try await run("/bin/launchctl", ["print", "system/" + ServiceIdentity.collector])
            return text.contains("state = running") || text.contains("pid = ")
        } catch {
            // Unknown errors cannot be treated as proof that shutdown succeeded.
            return !error.localizedDescription.contains("Could not find service")
        }
    }
}
