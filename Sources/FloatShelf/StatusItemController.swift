import AppKit
import FloatShelfCore

/// Menu bar item. Quit is always the last, clearly labelled entry.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private unowned let app: AppDelegate
    private let menu = NSMenu()

    init(app: AppDelegate) {
        self.app = app
        super.init()
        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "tray.full", accessibilityDescription: "FloatShelf") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "FS"
            }
            button.toolTip = "FloatShelf"
        }
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        rebuild()
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

        let quit = item("退出 FloatShelf", #selector(quit), key: "q")
        menu.addItem(quit)
    }

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
        alert.messageText = "FloatShelf 权限状态"
        alert.informativeText = """
        辅助功能（Accessibility）：\(PermissionProbe.accessibilityTrusted ? "已授权" : "未授权")
        输入监控（Input Monitoring）：\(PermissionProbe.inputMonitoringGranted ? "已授权" : "未授权")

        Phase 0 的主路径（全局鼠标事件监听 + Carbon 快捷键）按 Apple 文档不需要这两项权限，FloatShelf 也不会主动请求。若摇晃在拖拽中没有反应，请先查看日志中是否出现 “global monitor received its first leftMouseDragged”，再尝试切换到“轮询”引擎对比。
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
