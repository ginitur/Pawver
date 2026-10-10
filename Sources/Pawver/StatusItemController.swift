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

    private func rebuild() {
        let s = app.settings
        menu.removeAllItems()

        let newShelf = item("新建 Shelf", #selector(newShelf), key: "s")
        newShelf.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(newShelf)
        let hkStatus = NSMenuItem(title: app.hotkeyStatusText, action: nil, keyEquivalent: "")
        hkStatus.isEnabled = false
        menu.addItem(hkStatus)
        menu.addItem(item("重新注册快捷键", #selector(reregisterHotkey)))
        menu.addItem(.separator())

        let engineMenu = NSMenu()
        engineMenu.addItem(item("全局事件监听（默认）", #selector(selectEngine(_:)), state: s.engine == .globalMonitor, rep: AppSettings.Engine.globalMonitor.rawValue))
        engineMenu.addItem(item("轮询（对比用，无需权限）", #selector(selectEngine(_:)), state: s.engine == .polling, rep: AppSettings.Engine.polling.rawValue))
        let engineItem = NSMenuItem(title: "拖拽检测引擎", action: nil, keyEquivalent: "")
        engineItem.submenu = engineMenu
        menu.addItem(engineItem)

        let sensMenu = NSMenu()
        for (title, value) in [("低", ShakeConfig.Sensitivity.low), ("中（默认）", .medium), ("高", .high)] {
            sensMenu.addItem(item(title, #selector(selectSensitivity(_:)), state: s.sensitivity == value, rep: value.rawValue))
        }
        let sensItem = NSMenuItem(title: "摇晃灵敏度", action: nil, keyEquivalent: "")
        sensItem.submenu = sensMenu
        menu.addItem(sensItem)

        menu.addItem(item("仅在拖拽板 changeCount 变化时触发（推荐）", #selector(toggleRequireChange), state: s.requireDragPasteboardChange))
        menu.addItem(item("拖出时允许“移动”（实验，默认关闭）", #selector(toggleAllowMove), state: s.allowMoveOnDragOut))
        menu.addItem(.separator())

        menu.addItem(item("详细诊断日志", #selector(toggleVerbose), state: s.verbose))
        menu.addItem(item("记录屏幕信息到日志", #selector(logScreens)))
        menu.addItem(item("权限状态…", #selector(showPermissions)))
        if let url = Diag.logFileURL {
            menu.addItem(item("在 Finder 中显示日志文件", #selector(revealLog), rep: url.path))
        }
        menu.addItem(.separator())

        if statusItem.isVisible {
            menu.addItem(item("隐藏菜单栏图标", #selector(hideIcon)))
        } else {
            menu.addItem(item("显示菜单栏图标", #selector(showIcon)))
        }
        menu.addItem(.separator())

        let quit = item("退出 Pawver", #selector(quit), key: "q")
        menu.addItem(quit)
    }

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

    @objc private func reregisterHotkey() { app.reregisterHotkey(reason: "menu") }

    @objc private func selectEngine(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let engine = AppSettings.Engine(rawValue: raw) else { return }
        app.setEngine(engine)
    }

    @objc private func selectSensitivity(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let value = ShakeConfig.Sensitivity(rawValue: raw) else { return }
        app.setSensitivity(value)
    }

    @objc private func toggleRequireChange() {
        app.settings.requireDragPasteboardChange.toggle()
        app.applySettings()
    }

    @objc private func toggleAllowMove() {
        app.settings.allowMoveOnDragOut.toggle()
        Diag.notice(.dragout, "allowMoveOnDragOut = \(app.settings.allowMoveOnDragOut)")
    }

    @objc private func toggleVerbose() {
        app.settings.verbose.toggle()
        app.applySettings()
    }

    @objc private func logScreens() { app.logScreens() }

    @objc private func showPermissions() {
        let summary = PermissionProbe.summary()
        Diag.info(.permissions, "user opened permission status: \(summary)")
        let alert = NSAlert()
        alert.messageText = "Pawver 权限状态"
        alert.informativeText = """
        辅助功能（Accessibility）：\(PermissionProbe.accessibilityTrusted ? "已授权" : "未授权")
        输入监控（Input Monitoring）：\(PermissionProbe.inputMonitoringGranted ? "已授权" : "未授权")

        Phase 0 的主路径（全局鼠标事件监听 + Carbon 快捷键）按 Apple 文档不需要这两项权限，Pawver 也不会主动请求。若摇晃在拖拽中没有反应，请先查看日志中是否出现 “global monitor received its first leftMouseDragged”，再尝试切换到“轮询”引擎对比。
        """
        NSApp.activate()
        alert.runModal()
    }

    @objc private func revealLog(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    @objc private func quit() {
        Diag.notice(.app, "quit requested from menu")
        NSApp.terminate(nil)
    }
}
