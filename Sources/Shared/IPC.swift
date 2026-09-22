// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 WebKroo

import Foundation
import Security

enum ServiceIdentity {
    static let app = "com.norek.macprivacyactivity.local.app"
    static let collector = "com.norek.macprivacyactivity.local.collector"
    static let plist = collector + ".plist"
    static let protocolVersion = 1
    static func codeRequirement(at url: URL) -> String? {
        var code: SecStaticCode?; var info: CFDictionary?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dictionary = info as? [String: Any],
              let digest = dictionary[kSecCodeInfoUnique as String] as? Data,
              let identifier = dictionary[kSecCodeInfoIdentifier as String] as? String,
              identifier == app || identifier == collector else { return nil }
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "identifier \"\(identifier)\" and cdhash H\"\(hex)\""
    }
    static var clientRequirement: String? { codeRequirement(at: Bundle.main.bundleURL) }
    static var bundledHelper: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/MacPrivacyCollector") }
    static var helperRequirement: String? { codeRequirement(at: bundledHelper) }
    static let installedHelper = "/Library/PrivilegedHelperTools/com.norek.macprivacyactivity.local.collector"
    static let policyPath = "/Library/Application Support/Mac Privacy Activity Local/Client.plist"

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
