// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 WebKroo

import Foundation

enum NotificationTime {
    static func display(_ timestamp: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.isLenient = false
        for pattern in ["yyyy-MM-dd HH:mm:ss.SSSSSSZ", "yyyy-MM-dd HH:mm:ss.SSSZ", "yyyy-MM-dd HH:mm:ssZ", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX"] {
            formatter.dateFormat = pattern
            if let date = formatter.date(from: timestamp) {
                formatter.dateFormat = "yyyy-MM-dd h:mm:ss a"
                return formatter.string(from: date)
            }
        }
        return timestamp
    }
}
