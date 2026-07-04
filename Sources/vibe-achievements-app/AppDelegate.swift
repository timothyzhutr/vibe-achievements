import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var shelfWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private let appState = AppState()
    private var scanTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = LogoAsset.statusBarImage()
        statusItem?.button?.imagePosition = .imageOnly
        statusItem?.button?.toolTip = "Vibe Achievements"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Achievements", action: #selector(openAchievements), keyEquivalent: "a"))
        menu.addItem(NSMenuItem(title: "Scan Now", action: #selector(scanNow), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu

        NotificationController.requestAuthorization { [weak self] in
            Task { @MainActor in
                self?.appState.scanNow(sendNotifications: true)
            }
        }
        scanTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.appState.scanNow(sendNotifications: true)
            }
        }
    }

    @objc private func openAchievements() {
        if shelfWindow == nil {
            shelfWindow = NSWindow(contentViewController: NSHostingController(rootView: AchievementShelfView(state: appState)))
            shelfWindow?.title = "Vibe Achievements"
            shelfWindow?.setContentSize(NSSize(width: 560, height: 420))
            // We keep a strong reference and reuse the window; the default
            // release-when-closed would deallocate it under us on close.
            shelfWindow?.isReleasedWhenClosed = false
        }
        NSApp.activate(ignoringOtherApps: true)
        shelfWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func scanNow() {
        appState.scanNow(sendNotifications: true)
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(state: appState)))
            settingsWindow?.title = "Settings"
            settingsWindow?.setContentSize(NSSize(width: 460, height: 220))
            settingsWindow?.isReleasedWhenClosed = false
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
