import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var shelfWindow: NSWindow?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.title = "Vibe"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Achievements", action: #selector(openAchievements), keyEquivalent: "a"))
        menu.addItem(NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu

        NotificationController.requestAuthorization()
    }

    @objc private func openAchievements() {
        if shelfWindow == nil {
            shelfWindow = NSWindow(contentViewController: NSHostingController(rootView: AchievementShelfView()))
            shelfWindow?.title = "Vibe Achievements"
            shelfWindow?.setContentSize(NSSize(width: 560, height: 420))
        }
        NSApp.activate(ignoringOtherApps: true)
        shelfWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            settingsWindow?.title = "Settings"
            settingsWindow?.setContentSize(NSSize(width: 460, height: 220))
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
