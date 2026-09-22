// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 WebKroo

import Foundation
import SystemConfiguration
import Security
import Darwin

// No writable paths, arbitrary commands, or user configuration cross this boundary.
// Every mutable field below is confined to queue.
final class Collector: NSObject, NSXPCListenerDelegate {
    let queue = DispatchQueue(label: "com.norek.macprivacyactivity.collector")
    let clientRequirement: String
    var owner: NSXPCConnection?
    var process: Process?
    var output: Pipe?
    var errors: Pipe?
    var buffer = Data()
    var differ = EventDiffer()
    var lastHeartbeat = AwakeDeadline()
    var lease: DispatchSourceTimer?
    var lastDiagnostic = ""
    var sourcePID: Int32?
    init(clientRequirement: String) { self.clientRequirement = clientRequirement }
    func isConsoleUser(_ connection: NSXPCConnection) -> Bool {
        var uid: uid_t = 0; var gid: gid_t = 0
        guard SCDynamicStoreCopyConsoleUser(nil, &uid, &gid) != nil else { return false }
        return uid != 0 && uid == connection.effectiveUserIdentifier
    }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection c: NSXPCConnection) -> Bool {
        guard isConsoleUser(c) else { return false }
        c.setCodeSigningRequirement(clientRequirement)
        c.exportedInterface = NSXPCInterface(with: CollectorProtocol.self)
        c.remoteObjectInterface = NSXPCInterface(with: EventReceiverProtocol.self)
        c.exportedObject = Session(collector: self, connection: c)
        c.invalidationHandler = { [weak self, weak c] in
            guard let self, let c else { return }
            self.queue.async { if self.owner === c { self.shutdown(); exit(0) } }
        }
        c.interruptionHandler = c.invalidationHandler
        c.resume()
        return true
    }
    func receiver() -> EventReceiverProtocol? { owner?.remoteObjectProxyWithErrorHandler { _ in } as? EventReceiverProtocol }
    func start(_ c: NSXPCConnection, version: Int, reply: @escaping (String?) -> Void) {
        queue.async { [self] in
            guard version == ServiceIdentity.protocolVersion, self.isConsoleUser(c) else { reply("Protocol mismatch or this is not the active console user."); return }
            guard self.owner == nil else { reply("The collector is already in use. Quit the other copy of Mac Privacy Activity first."); return }
            self.owner = c; self.lastHeartbeat.renew(); self.differ = EventDiffer(); self.buffer.removeAll(); self.sourcePID = nil
            let p = Process(); let out = Pipe(); let err = Pipe()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/log")
            p.arguments = ["stream", "--style", "ndjson", "--info", "--predicate", LogParser.predicate]
            p.environment = ["PATH": "/usr/bin:/bin", "LC_ALL": "en_US.UTF-8"]
            p.standardOutput = out; p.standardError = err; p.standardInput = FileHandle.nullDevice
            self.process = p; self.output = out; self.errors = err
            out.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                self?.queue.async { self?.consume(data) }
            }
            err.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                self?.queue.async { self?.lastDiagnostic = String(decoding: data.prefix(2048), as: UTF8.self) }
            }
            p.terminationHandler = { [weak self, weak p] _ in
                guard let self, let p else { return }
                self.queue.async {
                    guard self.process === p else { return }
                    self.receiver()?.collectorFailed("Apple log stream exited (\(p.terminationStatus)). \(self.lastDiagnostic)")
                    self.shutdown(); exit(0)
                }
            }
            do { try p.run() } catch { self.shutdown(); reply(error.localizedDescription); return }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + 1, repeating: 1)
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                guard let owner = self.owner, self.isConsoleUser(owner), !self.lastHeartbeat.expired(after: 12) else {
                    self.shutdown(); exit(0)
                }
            }
            self.lease = timer; timer.resume(); reply(nil)
        }
    }
    func consume(_ data: Data) {
        guard process != nil, !data.isEmpty else { return }
        buffer.append(data)
        guard buffer.count <= 1_048_576 else { receiver()?.collectorFailed("Apple log line exceeded the safety limit."); shutdown(); return }
        while let end = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<end]); buffer.removeSubrange(...end)
            // A root log stream can include other logged-in users. Restrict
            // attribution to this connection's console-user ControlCenter.
            guard let owner,
                  let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let processNumber = object["processID"] as? NSNumber,
                  object["processImagePath"] as? String == "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter" else { continue }
            let pid = processNumber.int32Value
            var info = proc_bsdinfo()
            let size = MemoryLayout<proc_bsdinfo>.size
            guard pid > 0, proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(size)) == size,
                  info.pbi_uid == owner.effectiveUserIdentifier else { continue }
            guard let snapshot = LogParser.jsonLine(line) else { continue }
            if sourcePID != pid { differ = EventDiffer(); sourcePID = pid }
            receiver()?.observedSnapshot(snapshot.timestamp)
            let events = differ.consume(snapshot)
            if !events.isEmpty, let payload = try? JSONEncoder().encode(events) { receiver()?.receive(payload) }
        }
    }
    // A stop reply is issued only after the reader has exited. launchd also owns
    // the process group (AbandonProcessGroup=false), covering a killed helper.
    func shutdown() {
        lease?.cancel(); lease = nil
        output?.fileHandleForReading.readabilityHandler = nil; errors?.fileHandleForReading.readabilityHandler = nil
        if let p = process, p.isRunning {
            p.terminate()
            let deadline = AwakeDeadline()
            while p.isRunning && !deadline.expired(after: 1) { usleep(10_000) }
            if p.isRunning { kill(p.processIdentifier, SIGKILL) }
            p.waitUntilExit()
        }
        process = nil; output = nil; errors = nil; buffer.removeAll(); owner = nil
    }
}
final class Session: NSObject, CollectorProtocol {
    weak var collector: Collector?
    weak var connection: NSXPCConnection?
    init(collector: Collector, connection: NSXPCConnection) { self.collector = collector; self.connection = connection }
    func start(version: Int, withReply reply: @escaping (String?) -> Void) {
        guard let collector, let connection else { reply("Connection closed."); return }
        collector.start(connection, version: version, reply: reply)
    }
    func heartbeat(withReply reply: @escaping (Bool) -> Void) {
        guard let collector, let connection else { reply(false); return }
        collector.queue.async {
            let valid = collector.owner === connection && collector.process?.isRunning == true && collector.isConsoleUser(connection)
            if valid { collector.lastHeartbeat.renew() }
            reply(valid)
        }
    }
    func stop(withReply reply: @escaping () -> Void) {
        guard let collector, let connection else { reply(); return }
        collector.queue.async {
            guard collector.owner === connection else { reply(); return }
            collector.shutdown(); reply()
            collector.queue.asyncAfter(deadline: .now() + 0.3) { exit(0) }
        }
    }
}
// A free local installation pins the approved application's exact code hash.
// Only the administrator-owned policy can authorize a different build.
func loadClientRequirement() -> String? {
    let fd = open(ServiceIdentity.policyPath, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    guard fd >= 0 else { return nil }; defer { close(fd) }
    var info = stat()
    guard fstat(fd, &info) == 0, info.st_uid == 0, info.st_nlink == 1,
          info.st_mode & S_IFMT == S_IFREG, info.st_mode & 0o022 == 0,
          info.st_size > 0, info.st_size < 16384 else { return nil }
    var bytes = [UInt8](repeating: 0, count: Int(info.st_size))
    guard read(fd, &bytes, bytes.count) == bytes.count,
          let dictionary = try? PropertyListSerialization.propertyList(from: Data(bytes), format: nil) as? [String: String],
          dictionary["State"] == "active",
          let requirement = dictionary["ClientRequirement"] else { return nil }
    var parsed: SecRequirement?
    guard SecRequirementCreateWithString(requirement as CFString, [], &parsed) == errSecSuccess else { return nil }
    return requirement
}
guard geteuid() == 0, let requirement = loadClientRequirement() else {
    fputs("Local collector requires its administrator-installed policy.\n", stderr); exit(78)
}
let collector = Collector(clientRequirement: requirement)
let listener = NSXPCListener(machServiceName: ServiceIdentity.collector)
listener.delegate = collector
signal(SIGTERM, SIG_IGN); signal(SIGINT, SIG_IGN)
let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: collector.queue)
term.setEventHandler { collector.shutdown(); exit(0) }; term.resume()
let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: collector.queue)
interrupt.setEventHandler { collector.shutdown(); exit(0) }; interrupt.resume()
listener.resume()
// No authenticated session means no reason to remain running after a wakeup.
let idle = DispatchSource.makeTimerSource(queue: collector.queue)
idle.schedule(deadline: .now() + 15, repeating: 15)
idle.setEventHandler { if collector.owner == nil { collector.shutdown(); exit(0) } }
idle.resume()
dispatchMain()
