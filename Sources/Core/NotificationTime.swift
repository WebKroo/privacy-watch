// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 WebKroo

import Foundation

enum NotificationTime {
    // Searches can inspect 2,000 timestamps on each edit. Reuse formatters on
    // their calling thread, and replace them when the user's time zone changes.
    private final class FormatterCache {
        let zone = NSTimeZone.default
        var patterns: [String: DateFormatter] = [:]
        let dates = NSCache<NSString, NSDate>()
        init() { dates.countLimit = 4096 }
    }
    private static func cache() -> FormatterCache {
        let key = "PrivacyWatch.NotificationTime.formatters"
        let dictionary = Thread.current.threadDictionary
        let cached = dictionary[key] as? FormatterCache
        let cache: FormatterCache
        if let cached, cached.zone == NSTimeZone.default { cache = cached }
        else { cache = FormatterCache(); dictionary[key] = cache }
        return cache
    }
    private static func formatter(_ pattern: String) -> DateFormatter {
        let cache = cache()
        if let formatter = cache.patterns[pattern] { return formatter }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = cache.zone
        formatter.isLenient = false
        formatter.dateFormat = pattern
        cache.patterns[pattern] = formatter
        return formatter
    }
    static func date(_ timestamp: String) -> Date? {
        let dates = cache().dates
        if let cached = dates.object(forKey: timestamp as NSString) { return cached as Date }
        for pattern in ["yyyy-MM-dd HH:mm:ss.SSSSSSZ", "yyyy-MM-dd HH:mm:ss.SSSZ", "yyyy-MM-dd HH:mm:ssZ", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX"] {
            if let date = formatter(pattern).date(from: timestamp) {
                dates.setObject(date as NSDate, forKey: timestamp as NSString)
                return date
            }
        }
        return nil
    }
    static func display(_ timestamp: String) -> String {
        guard let date = date(timestamp) else { return timestamp }
        return formatter("yyyy-MM-dd h:mm:ss a").string(from: date)
    }
    static func menuClock(_ timestamp: String) -> String {
        guard let date = date(timestamp) else { return timestamp }
        return formatter("h:mm:ss a").string(from: date)
    }
    static func menuDate(_ timestamp: String) -> String {
        guard let date = date(timestamp) else { return "" }
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate(Calendar.current.component(.year, from: date) == Calendar.current.component(.year, from: Date()) ? "MMMd" : "yMMMd")
        return formatter.string(from: date)
    }
    static func compactTimestamp(_ timestamp: String) -> String {
        guard let date = date(timestamp) else { return timestamp }
        let pattern = Calendar.current.component(.year, from: date) == Calendar.current.component(.year, from: Date()) ? "MMM d, h:mm:ss a" : "MMM d yyyy, h:mm:ss a"
        return formatter(pattern).string(from: date)
    }
}
