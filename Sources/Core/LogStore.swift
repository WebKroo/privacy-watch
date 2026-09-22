// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 WebKroo

import Foundation
import Darwin

enum StoreError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}
final class LogStore {
    let folder: URL
    var csvURL: URL { folder.appendingPathComponent("Mac Privacy Activity.csv") }
    var textURL: URL { folder.appendingPathComponent("Mac Privacy Activity.log") }
    init(folder: URL) { self.folder = folder }
    private func safeOpen(_ url: URL, create: Bool) throws -> Int32 {
        let flags = (create ? O_RDWR | O_CREAT | O_APPEND : O_RDONLY) | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK
        let fd = open(url.path, flags, 0o600)
        guard fd >= 0 else {
            let error = errno
            if error == EPERM || error == EACCES {
                throw StoreError.message("macOS denied access to the log file. In Settings → Log files, choose the same folder again, then Resume Logging. Your existing history is preserved.")
            }
            throw StoreError.message("Cannot open \(url.lastPathComponent): \(String(cString: strerror(error))). Choose a writable folder with no legacy CSV shortcut.")
        }
        var st = stat()
        guard fstat(fd, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, st.st_uid == getuid(), st.st_nlink == 1 else {
            close(fd); throw StoreError.message("Log must be a regular file owned by you, with no hard links or symbolic links. Choose a new folder; the legacy log is preserved.")
        }
        if create { _ = fchmod(fd, 0o600) }
        return fd
    }
    private func writeAll(_ data: Data, fd: Int32) throws {
        try data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let count = Darwin.write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw StoreError.message("Log write failed: \(String(cString: strerror(errno))). Logging has paused.") }
                offset += count
            }
        }
        guard fsync(fd) == 0 else { throw StoreError.message("Unable to flush the log to disk. Logging has paused.") }
    }
    private func validateHeader(_ fd: Int32) throws {
        var st = stat(); guard fstat(fd, &st) == 0 else { throw StoreError.message("Cannot inspect the CSV.") }
        if st.st_size == 0 { try writeAll(Data(CSV.header.utf8), fd: fd); return }
        var bytes = [UInt8](repeating: 0, count: CSV.header.utf8.count)
        let count = pread(fd, &bytes, bytes.count, 0)
        guard count == bytes.count && Data(bytes) == Data(CSV.header.utf8) else {
            throw StoreError.message("This folder contains a CSV from another version. Choose a new folder or archive the old CSV first. No history has been overwritten.")
        }
    }
    func prepare(backup: Bool) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let csv = try safeOpen(csvURL, create: true); defer { close(csv) }
        try validateHeader(csv)
        if backup { let fd = try safeOpen(textURL, create: true); close(fd) }
    }
    func append(_ event: SensorEvent, backup: Bool) throws {
        let fd = try safeOpen(csvURL, create: true); defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw StoreError.message("Another process is writing this CSV.") }
        defer { flock(fd, LOCK_UN) }
        try validateHeader(fd)
        try writeAll(Data(CSV.row(event).utf8), fd: fd)
        if backup {
            let text = try safeOpen(textURL, create: true); defer { close(text) }
            // Escape control characters so an event always occupies exactly one backup line.
            let escaped = try JSONEncoder().encode(event)
            try writeAll(escaped + Data([10]), fd: text)
        }
    }
    func recentEvents(limit: Int = 2000) throws -> [SensorEvent] {
        guard FileManager.default.fileExists(atPath: csvURL.path) else { return [] }
        let fd = try safeOpen(csvURL, create: false); defer { close(fd) }
        var st = stat(); guard fstat(fd, &st) == 0 else { return [] }
        // Read a bounded tail. CSV records created here cannot contain literal newlines
        // in bundle IDs; app names are flattened by the user-session writer.
        let length = min(Int(st.st_size), 4 * 1024 * 1024)
        let offset = st.st_size - off_t(length)
        var bytes = [UInt8](repeating: 0, count: length)
        let count = pread(fd, &bytes, length, offset)
        guard count >= 0 else { throw StoreError.message("Cannot read CSV history.") }
        var text = String(decoding: bytes.prefix(count), as: UTF8.self)
        if offset > 0, let end = text.firstIndex(of: "\n") { text = String(text[text.index(after: end)...]) }
        return Array(CSV.rows(text).compactMap(CSV.event).suffix(limit).reversed())
    }
}
