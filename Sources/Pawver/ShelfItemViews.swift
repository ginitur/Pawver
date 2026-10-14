import AppKit
import PawverCore

/// Base view that starts a native drag-out session (via DragOutController)
/// once the pointer moves a few points after mouse-down.
class DragOutSourceView: NSView {
    weak var dragOut: DragOutController?
    var itemsProvider: () -> [ShelfItem] = { [] }
    private var mouseDownEvent: NSEvent?
    /// True once the current press turned into a drag (so mouseUp is not a click).
    private(set) var pressBecameDrag = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    /// Frame (in this view's coordinates) where the drag image starts.
    var dragImageFrame: NSRect { bounds }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        pressBecameDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = mouseDownEvent else { return }
        let a = down.locationInWindow
        let b = event.locationInWindow
        // Movement threshold: a click (including ⌘/⇧-click) never starts a drag.
        guard hypot(b.x - a.x, b.y - a.y) >= 3 else { return }
        mouseDownEvent = nil
        pressBecameDrag = true
        startDrag(event: event)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownEvent = nil
    }

    /// Default: drag `itemsProvider()` stacked from `dragImageFrame`.
    func startDrag(event: NSEvent) {
        let base = dragImageFrame
        dragOut?.beginDrag(items: itemsProvider(), from: self, event: event) { _, index in
            let offset = CGFloat(min(index, 8)) * 4
            return base.offsetBy(dx: offset, dy: -offset)
        }
    }
}

/// Row events the shelf controller turns into selection changes and drags.
@MainActor
protocol ItemRowDelegate: AnyObject {
    func rowMouseDown(_ row: ItemRowView, event: NSEvent)
    func rowClicked(_ row: ItemRowView, event: NSEvent)
    func rowBeginDrag(_ row: ItemRowView, event: NSEvent)
}

/// One row: Finder icon + display name + parent folder. Reference only.
final class ItemRowView: DragOutSourceView {
    static let height: CGFloat = 40
    let item: ShelfItem
    weak var rowDelegate: ItemRowDelegate?
    private let iconView = NSImageView()
    private let nameLabel: NSTextField
    private let parentLabel: NSTextField

    var isSelected = false {
        didSet {
            guard isSelected != oldValue else { return }
            nameLabel.textColor = isSelected ? .alternateSelectedControlTextColor : .labelColor
            parentLabel.textColor = isSelected ? NSColor.alternateSelectedControlTextColor.withAlphaComponent(0.8) : .secondaryLabelColor
            needsDisplay = true
        }
    }

    init(item: ShelfItem, displayName: String) {
        self.item = item
        nameLabel = NSTextField(labelWithString: displayName)
        parentLabel = NSTextField(labelWithString: (item.parentDirectoryPath as NSString).abbreviatingWithTildeInPath)
        super.init(frame: NSRect(x: 0, y: 0, width: 240, height: Self.height))
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        toolTip = item.url.path

        let icon = NSWorkspace.shared.icon(forFile: item.url.path)
        icon.size = NSSize(width: 32, height: 32)
        iconView.image = icon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.unregisterDraggedTypes()
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let name = nameLabel
        name.font = .systemFont(ofSize: 12, weight: .medium)
        name.lineBreakMode = .byTruncatingMiddle
        name.translatesAutoresizingMaskIntoConstraints = false

        let parent = parentLabel
        parent.font = .systemFont(ofSize: 10)
        parent.textColor = .secondaryLabelColor
        parent.lineBreakMode = .byTruncatingMiddle
        parent.translatesAutoresizingMaskIntoConstraints = false

        for v in [iconView, name, parent] { addSubview(v) }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.height),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32),
            name.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            name.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            name.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            parent.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            parent.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            parent.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 1),
        ])
        itemsProvider = { [item] in [item] }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var dragImageFrame: NSRect { iconView.frame }

    // Selection highlight: system accent (selectedContentBackgroundColor), resolved
    // for the current light/dark appearance; the shelf panel is never key, so the
    // emphasized colour is used deliberately.
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = 6
        if isSelected {
            var cg: CGColor?
            effectiveAppearance.performAsCurrentDrawingAppearance {
                cg = NSColor.selectedContentBackgroundColor.cgColor
            }
            layer.backgroundColor = cg
        } else {
            layer.backgroundColor = nil
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        rowDelegate?.rowMouseDown(self, event: event)
    }

    override func mouseUp(with event: NSEvent) {
        let wasDrag = pressBecameDrag
        super.mouseUp(with: event)
        if !wasDrag { rowDelegate?.rowClicked(self, event: event) }
    }

    override func startDrag(event: NSEvent) {
        rowDelegate?.rowBeginDrag(self, event: event)
    }
}

/// Document view of the shelf list; a click on empty space clears the selection.
final class ShelfListBackgroundView: NSView {
    var onEmptyClick: (() -> Void)?
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onEmptyClick?() }
}

/// "Drag all" handle in the header.
final class DragAllHandleView: DragOutSourceView {
    private let imageView = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        toolTip = "拖动全部项目 / Drag all items"
        imageView.image = NSImage(systemSymbolName: "square.stack.3d.up.fill", accessibilityDescription: "Drag all")
        imageView.contentTintColor = .controlAccentColor
        imageView.unregisterDraggedTypes()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 26),
            heightAnchor.constraint(equalToConstant: 22),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 18),
            imageView.heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var isEnabled = true {
        didSet { imageView.alphaValue = isEnabled ? 1 : 0.3 }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEnabled else { return }
        super.mouseDragged(with: event)
    }

    override var dragImageFrame: NSRect { NSRect(x: bounds.midX - 16, y: bounds.midY - 16, width: 32, height: 32) }
}
