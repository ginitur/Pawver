import AppKit
import PawverCore

/// Menu bar item. Quit is always the last, clearly labelled entry.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private unowned let app: AppDelegate
    private let menu = NSMenu()
    private var visibilityObservation: NSKeyValueObservation?

    /// UserDefaults key mirroring "the user hid the menu bar icon" (menu item or ⌘-drag).
    static let hiddenDefaultsKey = "statusItemHidden"
    static let autosaveName = "PawverStatusItem"

    init(app: AppDelegate) {
        self.app = app
        super.init()
        // ⌘-drag off the menu bar hides the item (isVisible = false) instead of being refused.
        statusItem.autosaveName = Self.autosaveName
        statusItem.behavior = .removalAllowed
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "pawprint", accessibilityDescription: "Pawver")
                ?? NSImage(systemSymbolName: "tray.full", accessibilityDescription: "Pawver")
            if let image {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "Pawver"
            }
            button.toolTip = "Pawver"
        }
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        rebuild()

        // Launching the app is an explicit "I want Pawver" signal, and a hidden icon
        // would leave no visible Quit, so a fresh launch always shows the icon again.
        let wasHidden = UserDefaults.standard.bool(forKey: Self.hiddenDefaultsKey) || !statusItem.isVisible
        setVisible(true, reason: wasHidden ? "launch (was hidden in previous session)" : "launch")

        visibilityObservation = statusItem.observe(\.isVisible, options: [.new]) { [weak self] item, _ in
            let visible = item.isVisible
            MainActor.assumeIsolated {
                self?.visibilityChanged(visible)
            }
        }
    }

    var isIconVisible: Bool { statusItem.isVisible }

    func setVisible(_ visible: Bool, reason: String) {
        Diag.notice(.app, "menu bar icon \(visible ? "shown" : "hidden") (\(reason))")
        statusItem.isVisible = visible
        UserDefaults.standard.set(!visible, forKey: Self.hiddenDefaultsKey)
    }

    /// Also fires when the user ⌘-drags the icon out of the menu bar.
    private func visibilityChanged(_ visible: Bool) {
        let stored = !UserDefaults.standard.bool(forKey: Self.hiddenDefaultsKey)
        guard stored != visible else { return }
        Diag.notice(.app, "menu bar icon isVisible → \(visible) (changed outside our menu, e.g. ⌘-drag); persisted")
        UserDefaults.standard.set(!visible, forKey: Self.hiddenDefaultsKey)
    }

    /// Shows the same menu from the shelf's "…" button, so Quit stays reachable while the icon is hidden.
    func popUpMenu(in view: NSView) {
        rebuild()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height + 4), in: view)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild()
    }

    private func item(_ title: String, _ action: Selector?, key: String = "", state: Bool? = nil, rep: Any? = nil) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
        mi.target = self
        if let state { mi.state = state ? .on : .off }
        mi.representedObject = rep
        return mi
    }

    /// Deliberately minimal; everything else lives in the Settings window.
    private func rebuild() {
        menu.removeAllItems()
        let newShelf = item("新建 Shelf", #selector(newShelf), key: "s")
        newShelf.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(newShelf)
        menu.addItem(.separator())
        menu.addItem(item("设置…", #selector(openSettings), key: ","))
        if statusItem.isVisible {
            menu.addItem(item("隐藏菜单栏图标", #selector(hideIcon)))
        } else {
            menu.addItem(item("显示菜单栏图标", #selector(showIcon)))
        }
        menu.addItem(.separator())
        menu.addItem(item("退出 Pawver", #selector(quit), key: "q"))
    }

    @objc private func openSettings() { app.openSettings() }

    @objc private func hideIcon() {
        setVisible(false, reason: "menu")
        let alert = NSAlert()
        alert.messageText = "菜单栏图标已隐藏"
        alert.informativeText = "Pawver 仍在运行。想找回图标：再次双击 Pawver.app（或在“应用程序/访达”里打开它），或按 ⌃⌥S 打开 Shelf 后点右上角的 “…” 按钮 → 显示菜单栏图标。退出也在这个菜单里。"
        NSApp.activate()
        alert.runModal()
    }

    @objc private func showIcon() { setVisible(true, reason: "menu (shelf …)") }

    @objc private func newShelf() { app.openShelf(reason: "menu bar") }

    @objc private func quit() {
        Diag.notice(.app, "quit requested from menu")
        NSApp.terminate(nil)
    }
}
