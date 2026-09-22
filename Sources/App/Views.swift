// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 WebKroo

import SwiftUI

struct ShieldMark: View {
    var size: CGFloat = 46
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26).fill(LinearGradient(colors: [Color(red: 0.06, green: 0.18, blue: 0.27), Color(red: 0.06, green: 0.48, blue: 0.47)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "checkmark.shield.fill").font(.system(size: size * 0.57, weight: .medium)).foregroundStyle(.white)
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}
struct StatusLabel: View {
    @ObservedObject var model: AppModel
    var color: Color { model.running ? .green : (model.issue != nil ? .orange : .secondary) }
    var body: some View {
        HStack(spacing: 6) {
            if model.busy { ProgressView().controlSize(.mini).accessibilityHidden(true) }
            else { Circle().fill(color).frame(width: 6, height: 6).accessibilityHidden(true) }
            Text(model.preview ? "Preview" : model.status).font(.system(size: 12, weight: .medium)).fixedSize(horizontal: false, vertical: true)
        }.accessibilityElement(children: .combine)
    }
}
struct StatusPill: View {
    @ObservedObject var model: AppModel
    var body: some View {
        StatusLabel(model: model).padding(.horizontal, 10).padding(.vertical, 6)
            .background(.quaternary, in: Capsule())
    }
}
struct LoggingButton: View {
    @ObservedObject var model: AppModel
    var fullWidth = false
    var body: some View {
        Button { model.loggingRequested ? model.stop { _ in } : model.start() } label: {
            Label(model.busy ? model.status : (model.loggingRequested ? "Pause Logging" : model.startTitle),
                  systemImage: model.loggingRequested ? "pause.fill" : "play.fill")
                .frame(maxWidth: fullWidth ? .infinity : nil).padding(.vertical, fullWidth ? 3 : 0)
        }.disabled(model.busy || model.preview)
    }
}
struct PanelView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ShieldMark(size: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Privacy Watch").font(.system(size: 14, weight: .semibold))
                    StatusLabel(model: model).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if model.issue != nil {
                Button { model.showActivity() } label: {
                    Label("Needs attention — view details", systemImage: "exclamationmark.triangle")
                        .font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                }.foregroundStyle(.orange).buttonStyle(.borderless)
            }
            LoggingButton(model: model, fullWidth: true)
                .buttonStyle(.borderedProminent).tint(Color(red: 0.06, green: 0.46, blue: 0.44))
            UpdateNotice(updates: model.updates, compact: true)
            Divider()
            HStack(spacing: 12) {
                Button("Activity & Settings…", systemImage: "list.bullet.rectangle") { model.showActivity() }
                    .help("Open activity history and settings")
                Spacer()
                Button("Quit") { model.quit() }.disabled(model.busy)
                    .help("Quit Privacy Watch and stop logging").accessibilityLabel("Quit Privacy Watch and stop logging")
            }.font(.system(size: 12)).controlSize(.small).buttonStyle(.borderless).padding(.vertical, 2)
        }.padding(16).frame(width: 320)
    }
}
final class ActivityViewState: ObservableObject {
    @Published var search = ""
    @Published var sensorFilter = "all"
    @Published var actionFilter = "all"
    @Published var dateFilter = "all"
    @Published var showAdvanced = false
    var isActive: Bool { !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sensorFilter != "all" || actionFilter != "all" || dateFilter != "all" }
    func clear() { search = ""; sensorFilter = "all"; actionFilter = "all"; dateFilter = "all" }
}
struct ActivityView: View {
    @ObservedObject var model: AppModel
    @StateObject private var filters = ActivityViewState()
    @FocusState private var searchFocused: Bool
    static var today: String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
    var filtered: [SensorEvent] {
        let today = Self.today
        let query = filters.search.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.events.filter { event in
            (filters.sensorFilter == "all" || event.sensor.rawValue == filters.sensorFilter) &&
            (filters.actionFilter == "all" || event.action.rawValue == filters.actionFilter) &&
            (filters.dateFilter == "all" || event.timestamp.hasPrefix(today)) &&
            (query.isEmpty || [event.appName, event.bundleID, event.timestamp, event.sensor.title, event.action.rawValue, event.action == .start ? "Started" : "Stopped"].joined(separator: " ").localizedCaseInsensitiveContains(query))
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ShieldMark(size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Privacy Watch").font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text("Microphone, camera, screen and location activity.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                StatusPill(model: model)
            }.padding(20)
            UpdateNotice(updates: model.updates).padding(.horizontal, 20)
            if let issue = model.issue {
                HStack { Image(systemName: "exclamationmark.triangle"); Text(issue).textSelection(.enabled); Spacer(); Button("Dismiss") { model.issue = nil } }
                    .font(.caption).padding(12).background(Color.orange.opacity(0.12)).padding(.horizontal, 24).padding(.bottom, 12)
            }
            if model.preview {
                Text("PREVIEW · Sample data only · No collector is running").font(.caption.weight(.semibold)).foregroundStyle(.teal).padding(.bottom, 12)
            }
            Picker("View", selection: $model.selectedTab) { Text("Activity").tag(0); Text("Settings").tag(1) }
                .pickerStyle(.segmented).labelsHidden().frame(width: 220).padding(.bottom, 16)
            if model.selectedTab == 0 { activity } else { settings }
            Divider()
            HStack {
                Button { model.revealFolder() } label: {
                    Label(model.folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"), systemImage: "folder")
                        .lineLimit(1).truncationMode(.middle)
                }.font(.caption).foregroundStyle(.secondary).buttonStyle(.borderless)
                    .help(model.folder.path).accessibilityLabel("Show log folder: \(model.folder.path)")
                Spacer()
                Button("Open CSV") { model.openCSV() }
                LoggingButton(model: model)
                Button("Quit Privacy Watch") { model.quit() }.disabled(model.busy)
            }.padding(.horizontal, 20).padding(.vertical, 12)
        }.frame(minWidth: 900, minHeight: 620).background(Color(nsColor: .windowBackgroundColor))
    }
    var activity: some View {
        let visibleEvents = filtered
        return VStack(spacing: 12) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                    TextField("Search activity", text: $filters.search).textFieldStyle(.plain)
                        .focused($searchFocused).accessibilityLabel("Search activity")
                        .help("Search applications, bundle IDs, sensors, events or timestamps")
                    if !filters.search.isEmpty {
                        Button { filters.search = ""; searchFocused = true } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.borderless).foregroundStyle(.secondary).accessibilityLabel("Clear search").help("Clear search")
                    }
                }.padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(searchFocused ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.12), lineWidth: 1))
                    .frame(minWidth: 230)
                Picker("Sensor", selection: $filters.sensorFilter) { Text("All sensors").tag("all"); ForEach(Sensor.allCases) { Text($0.title).tag($0.rawValue) } }.frame(width: 150)
                Picker("Event", selection: $filters.actionFilter) { Text("All events").tag("all"); Text("Started").tag("START"); Text("Stopped").tag("STOP") }.frame(width: 120)
                Picker("Date", selection: $filters.dateFilter) { Text("All dates").tag("all"); Text("Today").tag("today") }.frame(width: 120)
            }.labelsHidden().padding(.horizontal, 24)
            HStack(spacing: 12) {
                Text(filters.isActive ? "\(visibleEvents.count) of \(model.events.count) events" : "\(visibleEvents.count) \(visibleEvents.count == 1 ? "event" : "events")")
                    .font(.caption.weight(.medium)).monospacedDigit()
                if filters.isActive { Button("Clear Filters") { filters.clear() }.font(.caption).buttonStyle(.borderless) }
                Spacer()
                Text("Recent activity · Full history in CSV").font(.caption).foregroundStyle(.secondary)
                    .help("Shows up to 2,000 events from the last 4 MiB of the CSV")
                Button { if !model.preview { model.reloadHistory() } } label: { Image(systemName: "arrow.clockwise") }
                    .help("Reload history").accessibilityLabel("Reload history").disabled(model.preview)
            }.padding(.horizontal, 24)
            Table(visibleEvents) {
                TableColumn("Timestamp") { Text($0.timestamp).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }.width(min: 225, ideal: 265)
                TableColumn("Sensor") { event in
                    Label { Text(event.sensor.title) } icon: { Image(systemName: event.sensor.symbol).foregroundStyle(sensorColor(event.sensor)) }
                }.width(min: 115, ideal: 140)
                TableColumn("Event") { event in
                    Text(event.action == .start ? "Started" : "Stopped").font(.system(size: 10, weight: .semibold)).padding(.horizontal, 7).padding(.vertical, 4)
                        .background(event.action == .start ? Color.teal.opacity(0.13) : Color.gray.opacity(0.12), in: Capsule())
                }.width(80)
                TableColumn("Application") { event in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(event.appName).font(.system(size: 12, weight: .medium))
                        Text(event.bundleID).font(.system(size: 10)).foregroundStyle(.secondary)
                    }.padding(.vertical, 3)
                }.width(min: 170, ideal: 230)
                TableColumn("Observation") { event in
                    Text(event.observation == "first-observed" ? "First seen" : "Change")
                        .font(.caption).foregroundStyle(.secondary)
                        .help(event.observation == "first-observed" ? "Already present in the first update after logging began; the actual start time may be earlier." : "An attribution change reported by Control Center.")
                }.width(min: 90, ideal: 110)
            }.overlay {
                if visibleEvents.isEmpty {
                    if filters.isActive {
                        ContentUnavailableView {
                            Label("No matching activity", systemImage: "magnifyingglass")
                        } description: { Text("Try a different search or clear your filters.") }
                        actions: { Button("Clear Filters") { filters.clear() } }
                    } else {
                        ContentUnavailableView("No activity yet", systemImage: "checkmark.shield", description: Text(model.running ? "New activity appears when an app starts or stops using a selected sensor." : "Start logging to see new activity here."))
                    }
                }
            }
            HStack {
                Image(systemName: "clock"); Text("Last verified update: \(model.lastSnapshot)")
                Spacer()
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.bottom, 12)
        }
    }
    var settings: some View {
        Form {
            Section("Appearance") {
                Toggle("Show menu-bar icon", isOn: $model.showMenuBarIcon)
                Toggle("Keep Dock icon when window is closed", isOn: $model.showDockIcon)
                Text("Closing the window keeps logging in the background. Open Privacy Watch from Applications to return, even with both icons hidden. Quit stops logging.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Startup") {
                Toggle("Start logging automatically when the app opens", isOn: $model.startLoggingOnLaunch)
                Text("Add Privacy Watch to macOS Open at Login to start after sign-in. This setting applies on the next launch; Pause and Quit stop the current session.").font(.caption).foregroundStyle(.secondary)
            }
            UpdateSettings(updates: model.updates)
            Section("Record sensor activity") {
                ForEach(Sensor.allCases) { sensor in
                    Toggle(isOn: Binding(get: { model.enabled.contains(sensor) }, set: { model.toggle(sensor, value: $0) })) {
                        Label { Text(sensor.title) } icon: { Image(systemName: sensor.symbol).foregroundStyle(sensorColor(sensor)) }
                    }
                }
                Text("Only selected sensors are saved and can send notifications. Activity during a pause is not recorded.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Notifications") {
                Toggle("Microphone starts", isOn: $model.notifyMic).disabled(!model.enabled.contains(.mic))
                Toggle("Camera starts", isOn: $model.notifyCam).disabled(!model.enabled.contains(.cam))
                if !model.enabled.contains(.mic) || !model.enabled.contains(.cam) {
                    Text("Enable the corresponding sensor above to receive its notifications.").font(.caption).foregroundStyle(.secondary)
                }
                HStack { Text(model.notificationStatus).font(.caption).foregroundStyle(.secondary); Spacer(); Button("Allow Notifications…") { model.enableNotifications() } }
            }
            Section("Log files") {
                HStack {
                    Label(model.folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"), systemImage: "folder")
                        .font(.callout).textSelection(.enabled).lineLimit(2).truncationMode(.middle).help(model.folder.path)
                    Spacer()
                    Button("Choose Folder…") { model.chooseFolder() }.disabled(model.loggingRequested || model.busy)
                        .help(model.loggingRequested ? "Pause logging to choose a different folder" : "Choose where to save activity")
                }
                HStack {
                    Button("Open CSV", systemImage: "tablecells") { model.openCSV() }
                    Button("Show Folder", systemImage: "folder") { model.revealFolder() }
                }
                Toggle("Keep a plain-text backup (.log)", isOn: $model.backup)
                Text("Pause logging before changing folders. Existing logs stay where they are.").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                DisclosureGroup("Advanced", isExpanded: $filters.showAdvanced) {
                    LabeledContent("Log reader", value: model.helperStatus).padding(.top, 8)
                    Text("Administrator approval is needed only for setup and app updates. Pause and Quit stop the reader without a password.").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Install / Repair Local Collector…") { model.installCollector() }.disabled(model.busy || model.loggingRequested)
                        Button("Restore Original Logger…") { model.restoreOriginal() }.disabled(model.busy || model.loggingRequested)
                    }
                    Text("Pause logging before making changes. Restoring the original logger makes it run independently of Privacy Watch; existing files are preserved.").font(.caption).foregroundStyle(.secondary)
                }
            }

        }.formStyle(.grouped).onAppear {
            if !model.preview { model.notifications.refreshAuthorizationStatus() }
        }
    }
    func sensorColor(_ sensor: Sensor) -> Color {
        switch sensor { case .mic: return .orange; case .cam: return .green; case .scr: return .blue; case .loc: return .purple }
    }
}

struct UpdateSettings: View {
    @ObservedObject var updates: UpdateController
    var body: some View {
        Section("Updates") {
            Toggle("Check for updates automatically", isOn: $updates.automaticChecks)
                .disabled(!updates.allowsChecks)
            Picker("Check frequency", selection: $updates.frequency) {
                ForEach(UpdateFrequency.allCases) { Text($0.title).tag($0) }
            }.disabled(!updates.automaticChecks || !updates.allowsChecks)
            HStack {
                Text("Installed version \(updates.installedVersion)").foregroundStyle(.secondary)
                Spacer()
                if updates.isChecking { ProgressView().controlSize(.small).accessibilityLabel("Checking for updates") }
                Button(updates.isChecking ? "Checking…" : "Check for Updates") { updates.check() }
                    .disabled(updates.isChecking || !updates.allowsChecks)
            }
            HStack {
                Text(updates.message).foregroundStyle(updates.checkFailed ? Color.orange : Color.secondary)
                    .textSelection(.enabled)
                Spacer()
                if let release = updates.availableRelease {
                    Link("View Release & Download…", destination: release.pageURL)
                }
            }.font(.callout)
            if let date = updates.lastChecked {
                Text("Last checked: \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let date = updates.nextCheck {
                Text("Next check: \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Checks GitHub while Privacy Watch is running. Missed checks run after launch or wake. Activity logs stay on your Mac. Updates are downloaded and installed only when you choose.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct UpdateNotice: View {
    @ObservedObject var updates: UpdateController
    var compact = false
    var body: some View {
        if let release = updates.availableRelease {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle").foregroundStyle(.teal)
                if compact {
                    Link("Version \(release.version.description) available…", destination: release.pageURL)
                        .font(.caption)
                    Spacer()
                } else {
                    Text("Privacy Watch \(release.version.description) is available.").font(.callout)
                    Spacer()
                    Link("View Release & Download…", destination: release.pageURL).font(.callout)
                }
            }.padding(compact ? 0 : 12)
                .background(compact ? Color.clear : Color.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .padding(.bottom, compact ? 0 : 12)
        }
    }
}
