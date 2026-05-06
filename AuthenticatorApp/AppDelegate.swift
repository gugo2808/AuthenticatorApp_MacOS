import AppKit
import SwiftUI

@main
struct AuthenticatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No main window — menu bar only
        Settings { EmptyView() }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    let store = AccountStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keep app alive without a dock icon
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: "Authenticator")
            button.action = #selector(togglePopover)
            button.target = self
        }

        let popover = NSPopover()
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView()
                .environmentObject(store)
        )
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 320, height: 400)
        self.popover = popover
    }

    @objc func togglePopover() {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
