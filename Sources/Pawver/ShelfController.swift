import AppKit
import PawverCore

/// Owns the single Phase 0 shelf: panel, drop handling, item list.
@MainActor
final class ShelfController: NSObject, ShelfDropHandling {
    static let panelSize = NSSize(width: 280, height: 320)

    let dragOut = DragOutController()
    private(set) var store = ShelfStore()

    private let panel: ShelfPanel
    private let dropView: ShelfDropView
    private let effectView = NSVisualEffectView()
    private let countLabel = NSTextField(labelWithString: "")
    private let dragAllHandle = DragAllHandleView(frame: .zero)
    private let scrollView = NSScrollView()
    private let listStack = NSStackView()
    private let emptyState = NSStackView()
    private var shownAtUptime: Double = 0
    private var lastLogged: [Int: (NSDragOperation, NSDragOperation)] = [:]

    override init() {
        let frame = NSRect(origin: .zero, size: Self.panelSize)
        panel = ShelfPanel(contentRect: frame)
        dropView = ShelfDropView(frame: frame)
        super.init()
        dragOut.shelf = self
        dropView.handler = self
        buildUI()
        refresh()
    }

    var isVisible: Bool { panel.isVisible }
    /// "…" button in the shelf header; shows the app menu (incl. Quit / show menu bar icon).
    var onMenuButton: ((NSView) -> Void)?

    // MARK: UI

    private func buildUI() {
        dropView.autoresizingMask = [.width, .height]
        panel.contentView = dropView

        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 14
        effectView.layer?.masksToBounds = true
        effectView.layer?.borderWidth = 1
        effectView.layer?.borderColor = NSColor.separatorColor.cgColor
        effectView.translatesAutoresizingMaskIntoConstraints = false
        dropView.addSubview(effectView)

        dropView.onTargetedChange = { [weak self] targeted in
            guard let layer = self?.effectView.layer else { return }
            layer.borderWidth = targeted ? 3 : 1
            layer.borderColor = (targeted ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
        }

        countLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        dragAllHandle.dragOut = dragOut
        dragAllHandle.itemsProvider = { [weak self] in self?.store.items ?? [] }

        let closeImage = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close shelf") ?? NSImage()
        let closeButton = FirstMouseButton(image: closeImage, target: self, action: #selector(closeClicked))
        closeButton.isBordered = false
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.toolTip = "关闭 Shelf（只释放引用，不影响原文件）"
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        let menuImage = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "Pawver menu") ?? NSImage()
        let menuButton = FirstMouseButton(image: menuImage, target: self, action: #selector(menuClicked(_:)))
        menuButton.isBordered = false
        menuButton.contentTintColor = .secondaryLabelColor
        menuButton.toolTip = "Pawver 菜单（含退出、显示菜单栏图标）"
        menuButton.translatesAutoresizingMaskIntoConstraints = false

        listStack.orientation = .vertical
        listStack.alignment = .leading
        listStack.spacing = 2
        listStack.translatesAutoresizingMaskIntoConstraints = false

        let docView = FlippedView()
        docView.translatesAutoresizingMaskIntoConstraints = false
        docView.addSubview(listStack)

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = docView
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let trayImage = NSImageView(image: NSImage(systemSymbolName: "tray.and.arrow.down", accessibilityDescription: nil) ?? NSImage())
        trayImage.symbolConfiguration = .init(pointSize: 28, weight: .regular)
        trayImage.contentTintColor = .secondaryLabelColor
        trayImage.unregisterDraggedTypes()
        let emptyLabel = NSTextField(labelWithString: "把文件拖到这里\nDrop files here")
        emptyLabel.alignment = .center
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.font = .systemFont(ofSize: 12)
        emptyState.orientation = .vertical
        emptyState.alignment = .centerX
        emptyState.spacing = 6
        emptyState.addArrangedSubview(trayImage)
        emptyState.addArrangedSubview(emptyLabel)
        emptyState.translatesAutoresizingMaskIntoConstraints = false

        for v in [countLabel, dragAllHandle, closeButton, menuButton, scrollView, emptyState] as [NSView] {
            effectView.addSubview(v)
        }

        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: dropView.leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: dropView.trailingAnchor),
            effectView.topAnchor.constraint(equalTo: dropView.topAnchor),
            effectView.bottomAnchor.constraint(equalTo: dropView.bottomAnchor),

            closeButton.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 10),
            closeButton.topAnchor.constraint(equalTo: effectView.topAnchor, constant: 9),
            countLabel.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: 8),
            countLabel.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            menuButton.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -10),
            menuButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            dragAllHandle.trailingAnchor.constraint(equalTo: menuButton.leadingAnchor, constant: -8),
            dragAllHandle.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),

            scrollView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 4),
            scrollView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -4),
            scrollView.topAnchor.constraint(equalTo: effectView.topAnchor, constant: 36),
            scrollView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -6),

            docView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            docView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            docView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            listStack.leadingAnchor.constraint(equalTo: docView.leadingAnchor),
            listStack.trailingAnchor.constraint(equalTo: docView.trailingAnchor),
            listStack.topAnchor.constraint(equalTo: docView.topAnchor),
            listStack.bottomAnchor.constraint(equalTo: docView.bottomAnchor),

            emptyState.centerXAnchor.constraint(equalTo: effectView.centerXAnchor),
            emptyState.centerYAnchor.constraint(equalTo: effectView.centerYAnchor, constant: 10),
        ])
    }

    private func refresh() {
        for v in listStack.arrangedSubviews {
            listStack.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        let names = store.displayNames()
        for item in store.items {
            let row = ItemRowView(item: item, displayName: names[item.id] ?? item.name)
            row.dragOut = dragOut
            listStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: listStack.widthAnchor).isActive = true
        }
        let n = store.count
        countLabel.stringValue = n == 0 ? "空 Shelf" : "\(n) 个项目"
        emptyState.isHidden = n > 0
        scrollView.isHidden = n == 0
        dragAllHandle.isEnabled = n > 0
    }

    // MARK: Show / hide

    func show(near cursor: CGPoint, reason: String) {
        let screens = NSScreen.screens
        let geometry = screens.map { ScreenGeometry(frame: $0.frame, visibleFrame: $0.visibleFrame, scale: $0.backingScaleFactor) }
        guard let frame = ShelfPositioning.shelfFrame(size: Self.panelSize, cursor: cursor, screens: geometry),
              let index = ShelfPositioning.screenIndex(for: cursor, in: geometry) else {
            Diag.error(.shelf, "cannot position shelf: no screens")
            return
        }
        let wasVisible = panel.isVisible
        panel.setFrame(frame, display: true)
        if wasVisible {
            panel.orderFrontRegardless()
        } else {
            panel.alphaValue = 0.35
            panel.orderFrontRegardless()
            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = 0.12
            panel.animator().alphaValue = 1
            NSAnimationContext.endGrouping()
        }
        shownAtUptime = ProcessInfo.processInfo.systemUptime
        let s = screens[index]
        Diag.notice(.shelf, "shelf shown (reason=\(reason), wasVisible=\(wasVisible)) cursor=\(fmt(cursor)) screen#\(index) '\(s.localizedName)' scale=\(s.backingScaleFactor) screenFrame=\(fmt(s.frame)) visibleFrame=\(fmt(s.visibleFrame)) panelFrame=\(fmt(frame)) cursorInsidePanel=\(ShelfPositioning.contains(frame, cursor)) appActive=\(NSApp.isActive) panelIsKey=\(panel.isKeyWindow) frontmostApp=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")")
    }

    @objc private func menuClicked(_ sender: NSView) {
        Diag.info(.shelf, "shelf menu button clicked")
        onMenuButton?(sender)
    }

    @objc private func closeClicked() {
        close(reason: "close button")
    }

    func close(reason: String) {
        let released = store.count
        store.removeAll()
        refresh()
        panel.orderOut(nil)
        Diag.notice(.shelf, "shelf closed (\(reason)); released \(released) reference(s); no file was touched")
    }

    func removeItems(_ ids: [UUID], reason: String) {
        for id in ids { store.remove(id: id) }
        refresh()
        Diag.info(.shelf, "removed \(ids.count) item(s) from shelf: \(reason)")
    }

    // MARK: ShelfDropHandling (NSDraggingDestination logic)

    func dropOperation(for info: NSDraggingInfo, phase: String) -> NSDragOperation {
        let seq = info.draggingSequenceNumber
        let sourceMask = info.draggingSourceOperationMask
        let fromOwnApp = info.draggingSource != nil
        let pb = info.draggingPasteboard
        let canRead = pb.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])

        var op: NSDragOperation = []
        if !fromOwnApp && canRead {
            if sourceMask.contains(.copy) {
                op = .copy
            } else if sourceMask.contains(.generic) {
                op = .generic
            }
        }

        let previous = lastLogged[seq]
        if phase == "entered" || previous == nil || previous!.0 != sourceMask || previous!.1 != op {
            lastLogged[seq] = (sourceMask, op)
            let since = ProcessInfo.processInfo.systemUptime - shownAtUptime
            Diag.info(.dropin, "dragging\(phase.capitalized) seq=\(seq) \(String(format: "%.0f", since * 1000))ms after shelf shown | sourceMask=\(sourceMask.names) modifiers=\(NSEvent.modifierFlags.names) → we return \(op.names) | fromOwnApp=\(fromOwnApp) canReadFileURLs=\(canRead) items=\(info.numberOfValidItemsForDrop) types=[\((pb.types ?? []).map(\.rawValue).joined(separator: ", "))]")
        }
        return op
    }

    func performDrop(_ info: NSDraggingInfo) -> Bool {
        let pb = info.draggingPasteboard
        let objects = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ?? []
        let urls = objects.compactMap { $0 as? URL }
        Diag.debug(.dropin, "raw dropped URLs: \(urls.map(\.absoluteString))")
        guard !urls.isEmpty else {
            Diag.error(.dropin, "performDragOperation seq=\(info.draggingSequenceNumber): no file URLs readable — drop rejected")
            return false
        }
        let result = store.add(urls)
        refresh()
        lastLogged[info.draggingSequenceNumber] = nil
        Diag.notice(.dropin, "performDragOperation seq=\(info.draggingSequenceNumber): stored \(result.added.count) reference(s), \(result.duplicates.count) duplicate(s), \(result.rejected.count) rejected; shelf now has \(store.count). Files were NOT copied or moved by Pawver. added=\(result.added.map(\.key))")
        return true
    }

    func dropTargetExited(_ info: NSDraggingInfo?) {
        if let info {
            Diag.debug(.dropin, "draggingExited seq=\(info.draggingSequenceNumber)")
            lastLogged[info.draggingSequenceNumber] = nil
        }
    }
}
