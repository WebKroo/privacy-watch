// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 WebKroo

import AppKit
import SwiftUI
import Combine
import Carbon

@MainActor final class StatusPanelController: NSObject {
    private let model: AppModel
    private var item: NSStatusItem?
    private let popover = NSPopover()
    private var subscriptions = Set<AnyCancellable>()

    init(model: AppModel) {
        self.model = model
        super.init()
        popover.behavior = .transient
        let controller = NSHostingController(rootView: PanelView(model: model))
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
        model.$showMenuBarIcon.sink { [weak self] visible in self?.setVisible(visible) }.store(in: &subscriptions)
        model.$running.combineLatest(model.$status).sink { [weak self] running, status in
            self?.updateIcon(running: running, status: status)
        }.store(in: &subscriptions)
        model.$activityWindowOpen.sink { [weak self] visible in
            if visible { self?.popover.performClose(nil) }
        }.store(in: &subscriptions)
    }
    private func setVisible(_ visible: Bool) {
        if visible {
            guard item == nil else { return }
            let newItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            newItem.button?.target = self
            newItem.button?.action = #selector(togglePanel(_:))
            item = newItem
            updateIcon(running: model.running, status: model.status)
        } else {
            popover.performClose(nil)
            if let item { NSStatusBar.system.removeStatusItem(item) }
            item = nil
        }
    }
    private func updateIcon(running: Bool, status: String) {
        let icon = NSImage(systemSymbolName: running ? "checkmark.shield.fill" : "shield.lefthalf.filled", accessibilityDescription: "Privacy Watch")
        icon?.isTemplate = true
        item?.button?.image = icon
        item?.button?.toolTip = "Privacy Watch: \(status)"
    }
    @objc private func togglePanel(_ sender: Any?) {
        guard let button = item?.button else { return }
        if popover.isShown { popover.performClose(sender) }
        else {
            if let view = popover.contentViewController?.view {
                view.layoutSubtreeIfNeeded()
                popover.contentSize = view.fittingSize
            }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
    private var terminating = false
    private var statusPanel: StatusPanelController?
    private var loggingItem: NSMenuItem?
    private var presentationSubscription: AnyCancellable?
    func applicationWillFinishLaunching(_ notification: Notification) { installMenus() }
    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel.shared
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(willSleep(_:)), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(didWake(_:)), name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(sessionBecameActive(_:)), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        statusPanel = StatusPanelController(model: model)
        presentationSubscription = model.$showDockIcon.combineLatest(model.$activityWindowOpen)
            .sink { showDockIcon, windowOpen in
                NSApp.setActivationPolicy(showDockIcon || windowOpen ? .regular : .accessory)
            }
        let event = NSAppleEventManager.shared().currentAppleEvent
        let loginLaunch = event?.eventID == kAEOpenApplication &&
            event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        model.didLaunch(showWindow: !loginLaunch && !CommandLine.arguments.contains("--background"))
    }
    @objc private func willSleep(_ notification: Notification) { AppModel.shared.systemWillSleep() }
    @objc private func didWake(_ notification: Notification) { AppModel.shared.systemDidWake() }
    @objc private func sessionBecameActive(_ notification: Notification) {
        // Also recover after returning from another user's console session.
        if !AppModel.shared.running { AppModel.shared.systemDidWake() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppModel.shared.showActivity(); return true
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if terminating { return .terminateLater }
        terminating = true
        Task { @MainActor in
            AppModel.shared.stop { success in
                self.terminating = false
                sender.reply(toApplicationShouldTerminate: success)
                if !success { AppModel.shared.showActivity() }
            }
        }
        return .terminateLater
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func installMenus() {
        let main = NSMenu()
        let application = NSMenu(title: "Privacy Watch")
        add("About Privacy Watch", to: application, action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), target: NSApp)
        application.addItem(.separator())
        add("Settings…", to: application, action: #selector(openSettings(_:)), key: ",")
        application.addItem(.separator())
        add("Hide Privacy Watch", to: application, action: #selector(NSApplication.hide(_:)), target: NSApp, key: "h")
        let hideOthers = add("Hide Others", to: application, action: #selector(NSApplication.hideOtherApplications(_:)), target: NSApp, key: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        add("Show All", to: application, action: #selector(NSApplication.unhideAllApplications(_:)), target: NSApp)
        application.addItem(.separator())
        add("Quit Privacy Watch", to: application, action: #selector(NSApplication.terminate(_:)), target: NSApp, key: "q")
        attach(application, to: main)

        let file = NSMenu(title: "File"); file.delegate = self
        add("Open Activity", to: file, action: #selector(openActivity(_:)), key: "1")
        add("Open CSV", to: file, action: #selector(openCSV(_:)), key: "o")
        add("Show Log Folder", to: file, action: #selector(showFolder(_:)))
        file.addItem(.separator())
        loggingItem = add("Pause Logging", to: file, action: #selector(toggleLogging(_:)))
        file.addItem(.separator())
        add("Close Window", to: file, action: #selector(NSWindow.performClose(_:)), target: nil, key: "w", responderChain: true)
        attach(file, to: main)

        let edit = NSMenu(title: "Edit")
        for (title, selector, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            add(title, to: edit, action: Selector(selector), target: nil, key: key, responderChain: true)
        }
        attach(edit, to: main)

        let window = NSMenu(title: "Window")
        add("Show Privacy Watch", to: window, action: #selector(openActivity(_:)))
        add("Minimize", to: window, action: #selector(NSWindow.performMiniaturize(_:)), target: nil, key: "m", responderChain: true)
        add("Bring All to Front", to: window, action: #selector(NSApplication.arrangeInFront(_:)), target: NSApp)
        attach(window, to: main)
        NSApp.windowsMenu = window
        NSApp.mainMenu = main
    }
    @discardableResult private func add(_ title: String, to menu: NSMenu, action: Selector, target: AnyObject? = nil, key: String = "", responderChain: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = responderChain ? nil : (target ?? self)
        menu.addItem(item); return item
    }
    private func attach(_ submenu: NSMenu, to menu: NSMenu) {
        let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        item.submenu = submenu; menu.addItem(item)
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        let model = AppModel.shared
        loggingItem?.title = model.busy ? model.status : (model.loggingRequested ? "Pause Logging" : model.startTitle)
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem !== loggingItem || (!AppModel.shared.busy && !AppModel.shared.preview)
    }
    @objc private func openSettings(_ sender: Any?) { AppModel.shared.showSettings() }
    @objc private func openActivity(_ sender: Any?) { AppModel.shared.selectedTab = 0; AppModel.shared.showActivity() }
    @objc private func openCSV(_ sender: Any?) { AppModel.shared.openCSV() }
    @objc private func showFolder(_ sender: Any?) { AppModel.shared.revealFolder() }
    @objc private func toggleLogging(_ sender: Any?) {
        let model = AppModel.shared
        if model.loggingRequested { model.stop { _ in } } else { model.start() }
    }
}

@main @MainActor struct PrivacyWatchApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Start without a Dock flash. Showing the window promotes the app to
        // regular activation, restoring the standard application menus.
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}
