import AppKit
import SwiftUI
import PawverCore

/// Bridges AppSettings/AppDelegate to SwiftUI. Every change goes through the same
/// AppDelegate paths the old menu used, so persistence and side effects are unchanged.
@MainActor
final class SettingsModel: ObservableObject {
    private unowned let app: AppDelegate

    @Published var engine: AppSettings.Engine { didSet { if engine != app.settings.engine { app.setEngine(engine) } } }
    @Published var sensitivity: ShakeConfig.Sensitivity { didSet { if sensitivity != app.settings.sensitivity { app.setSensitivity(sensitivity) } } }
    @Published var requireChange: Bool { didSet { app.settings.requireDragPasteboardChange = requireChange; app.applySettings() } }
    @Published var allowMove: Bool {
        didSet {
            app.settings.allowMoveOnDragOut = allowMove
            Diag.notice(.dragout, "allowMoveOnDragOut = \(allowMove) (settings window)")
        }
    }
    @Published var verbose: Bool { didSet { app.settings.verbose = verbose; app.applySettings() } }
    @Published var iconVisible: Bool { didSet { if iconVisible != app.isMenuBarIconVisible { app.setMenuBarIconVisible(iconVisible, reason: "settings window") } } }
    @Published private(set) var hotkeyStatus = ""
    @Published private(set) var accessibility = false
    @Published private(set) var inputMonitoring = false

    init(app: AppDelegate) {
        self.app = app
        let s = app.settings
        engine = s.engine
        sensitivity = s.sensitivity
        requireChange = s.requireDragPasteboardChange
        allowMove = s.allowMoveOnDragOut
        verbose = s.verbose
        iconVisible = app.isMenuBarIconVisible
        refreshStatus()
    }

    /// Re-read state that can change outside the window (⌘-drag of the icon, hotkey fires, TCC).
    func refreshStatus() {
        hotkeyStatus = app.hotkeyStatusText
        accessibility = PermissionProbe.accessibilityTrusted
        inputMonitoring = PermissionProbe.inputMonitoringGranted
        if iconVisible != app.isMenuBarIconVisible { iconVisible = app.isMenuBarIconVisible }
    }

    var logFileURL: URL? { Diag.logFileURL }
    func reregisterHotkey() { app.reregisterHotkey(reason: "settings window"); refreshStatus() }
    func logScreens() { app.logScreens() }
    func revealLog() {
        guard let url = Diag.logFileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("通用") {
                Toggle("显示菜单栏图标", isOn: $model.iconVisible)
                Text("隐藏后：再次双击 Pawver.app，或在 Shelf 右上角“…”菜单中恢复。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("摇晃检测") {
                Picker("灵敏度", selection: $model.sensitivity) {
                    Text("低").tag(ShakeConfig.Sensitivity.low)
                    Text("中（默认）").tag(ShakeConfig.Sensitivity.medium)
                    Text("高").tag(ShakeConfig.Sensitivity.high)
                }
                .pickerStyle(.segmented)
                Picker("检测引擎", selection: $model.engine) {
                    Text("全局事件监听（默认）").tag(AppSettings.Engine.globalMonitor)
                    Text("轮询（对比用）").tag(AppSettings.Engine.polling)
                }
                Toggle("仅在确认是文件拖拽时触发（推荐）", isOn: $model.requireChange)
            }
            Section("快捷键") {
                LabeledContent("新建 Shelf", value: "⌃⌥S")
                HStack {
                    Text(model.hotkeyStatus).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("重新注册") { model.reregisterHotkey() }
                }
            }
            Section("高级与诊断") {
                Toggle("拖出时允许“移动”（实验，默认关闭）", isOn: $model.allowMove)
                Toggle("详细诊断日志", isOn: $model.verbose)
                LabeledContent("辅助功能", value: model.accessibility ? "已授权" : "未授权")
                LabeledContent("输入监控", value: model.inputMonitoring ? "已授权" : "未授权")
                Text("当前功能不需要这两项权限，Pawver 也不会主动请求。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("记录屏幕信息到日志") { model.logScreens() }
                    if model.logFileURL != nil {
                        Button("在 Finder 中显示日志") { model.revealLog() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            model.refreshStatus()
        }
    }
}

/// A plain titled NSWindow hosting the SwiftUI form. Opening it activates the app
/// (it needs keyboard focus); the shelf panel stays non-activating and is unaffected.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let model: SettingsModel

    init(app: AppDelegate) {
        model = SettingsModel(app: app)
        let host = NSHostingController(rootView: SettingsView(model: model))
        let window = NSWindow(contentViewController: host)
        window.title = "Pawver 设置"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("PawverSettingsWindow")
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show() {
        model.refreshStatus()
        if window?.isVisible != true { window?.center() }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        Diag.info(.app, "settings window opened")
    }

    func windowWillClose(_ notification: Notification) {
        Diag.info(.app, "settings window closed")
    }
}
