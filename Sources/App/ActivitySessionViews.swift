// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 WebKroo

import SwiftUI

struct MenuSessionRow: View {
    let session: ActivitySession
    let compact: Bool
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: session.sensor.symbol).font(.system(size: 12, weight: .medium))
                .foregroundStyle(sensorColor(session.sensor))
                .frame(width: compact ? 15 : 27, height: compact ? 18 : 29)
                .background(sensorColor(session.sensor).opacity(compact ? 0 : 0.10), in: RoundedRectangle(cornerRadius: 6))
                .accessibilityHidden(true)
            if compact {
                Text(session.appName).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
                duration
                Text(NotificationTime.menuClock(session.latest.timestamp)).font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary).fixedSize()
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(session.appName).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 0)
                        duration
                    }
                    HStack(spacing: 6) {
                        Text("\(session.sensor.title) · \(session.stateLabel)").lineLimit(1)
                        Spacer(minLength: 0)
                        Text(NotificationTime.menuClock(session.latest.timestamp)).monospacedDigit().fixedSize()
                    }.font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }.padding(.vertical, compact ? 6 : 8).help(session.help)
            .accessibilityElement(children: .ignore).accessibilityLabel(session.help)
    }
    private var duration: some View {
        Text(session.durationLabel).font(.system(size: 11, weight: .medium)).monospacedDigit()
            .foregroundStyle(session.isActive ? Color.teal : Color.primary).fixedSize()
    }
}

struct SessionTable: View {
    let sessions: [ActivitySession]
    let compact: Bool
    var body: some View {
        Table(sessions) {
            TableColumn("Application") { session in
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.appName).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    if !compact { Text(session.bundleID).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1) }
                }.padding(.vertical, compact ? 0 : 3).help(session.help)
            }.width(min: 150, ideal: 210)
            TableColumn("Sensor") { session in
                Label { Text(session.sensor.title).lineLimit(1) } icon: { Image(systemName: session.sensor.symbol).foregroundStyle(sensorColor(session.sensor)) }
                    .help(session.help)
            }.width(min: 115, ideal: 140)
            TableColumn("Started / first seen") { session in
                SessionTimeCell(event: session.start, fallback: "Not recorded", compact: compact, firstSeen: session.firstSeen).help(session.help)
            }.width(min: compact ? 175 : 140, ideal: compact ? 185 : 165)
            TableColumn("Stopped") { session in
                SessionTimeCell(event: session.stop, fallback: session.isActive ? "Active" : "Not recorded", compact: compact).help(session.help)
            }.width(min: compact ? 170 : 115, ideal: compact ? 185 : 145)
            TableColumn("Duration") { session in
                Text(session.isActive ? "—" : session.durationLabel).font(.system(size: 12, weight: .medium)).monospacedDigit()
                    .foregroundStyle(session.isActive ? Color.secondary : Color.primary).help(session.help)
            }.width(min: 95, ideal: 110)
        }
    }
}

private struct SessionTimeCell: View {
    let event: SensorEvent?
    let fallback: String
    let compact: Bool
    var firstSeen = false
    var body: some View {
        if let event {
            VStack(alignment: .leading, spacing: 3) {
                Text((firstSeen ? "≤ " : "") + (compact ? NotificationTime.compactTimestamp(event.timestamp) : NotificationTime.menuClock(event.timestamp)))
                    .font(.system(size: compact ? 11 : 12)).monospacedDigit().lineLimit(1)
                if !compact { Text(NotificationTime.menuDate(event.timestamp)).font(.system(size: 10)).foregroundStyle(.secondary) }
            }.accessibilityElement(children: .ignore).accessibilityLabel("\(firstSeen ? "First seen" : "Time"): \(NotificationTime.display(event.timestamp))")
        } else {
            Text(fallback).font(.system(size: 12)).foregroundStyle(fallback == "Active" ? Color.teal : Color.secondary)
        }
    }
}
