import AppKit

/// The block-level shape a paragraph can be turned into from the selection
/// toolbar. One list, so the menu, the current-state readback, and the command
/// that applies it can never drift apart.
enum BlockStyleChoice: Int, CaseIterable {
    case body
    case heading1
    case heading2
    case heading3
    case bulletList
    case numberedList
    case checklist
    case quote
    case codeBlock

    var title: String {
        switch self {
        case .body: return "Paragraph"
        case .heading1: return "Heading 1"
        case .heading2: return "Heading 2"
        case .heading3: return "Heading 3"
        case .bulletList: return "Bulleted List"
        case .numberedList: return "Numbered List"
        case .checklist: return "Checklist"
        case .quote: return "Quote"
        case .codeBlock: return "Code Block"
        }
    }
}

/// The bar that appears over selected text.
///
/// Formatting lives in three places — the sidebar, the menu bar, and the
/// keyboard — and all three ask the user to look away from what they just
/// selected. This puts the same commands where their attention already is.
/// It is a plain view over the text rather than a panel, so it scrolls with
/// the selection it belongs to and never steals first responder: the text view
/// keeps focus the whole time, which is what lets a command act on a live
/// selection at all.
final class SelectionToolbar: NSView {

    var onStyle: ((BlockStyleChoice) -> Void)?
    var onInline: ((InlineStyle) -> Void)?
    var onLink: (() -> Void)?
    var onAssistant: (() -> Void)?

    private let backdrop = NSVisualEffectView()
    private let stack = NSStackView()
    private let stylePopUp = NSPopUpButton()
    private var inlineButtons: [InlineStyle: ToolbarButton] = [:]

    private let barHeight: CGFloat = 34

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    /// The bar must never take focus. If it did, the selection it exists to
    /// act on would be gone by the time the command ran.
    override var acceptsFirstResponder: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        isHidden ? nil : super.hitTest(point)
    }

    private func build() {
        wantsLayer = true

        backdrop.material = .popover
        backdrop.blendingMode = .withinWindow
        backdrop.state = .active
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = 9
        backdrop.layer?.cornerCurve = .continuous
        backdrop.layer?.borderWidth = 0.7
        backdrop.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.6).cgColor
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backdrop)

        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.22
        layer?.shadowRadius = 10
        layer?.shadowOffset = CGSize(width: 0, height: -2)

        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        buildStylePopUp()
        stack.addArrangedSubview(separator())

        addInlineButton(.bold, symbol: "bold", help: "Bold (⌘B)")
        addInlineButton(.italic, symbol: "italic", help: "Italic (⌘I)")
        addInlineButton(.strikethrough, symbol: "strikethrough", help: "Strikethrough (⇧⌘X)")
        addInlineButton(.code, symbol: "chevron.left.forwardslash.chevron.right", help: "Inline code (⌘E)")
        addInlineButton(.highlight, symbol: "highlighter", help: "Highlight")

        let link = ToolbarButton(symbol: "link", help: "Add or remove a link (⌘K)") { [weak self] in
            self?.onLink?()
        }
        stack.addArrangedSubview(link)

        stack.addArrangedSubview(separator())

        let assistant = ToolbarButton(
            symbol: "sparkles",
            title: "Ask",
            help: "Ask Markowski about the selected text"
        ) { [weak self] in
            self?.onAssistant?()
        }
        stack.addArrangedSubview(assistant)

        NSLayoutConstraint.activate([
            backdrop.topAnchor.constraint(equalTo: topAnchor),
            backdrop.leadingAnchor.constraint(equalTo: leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
            backdrop.bottomAnchor.constraint(equalTo: bottomAnchor),

            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: barHeight)
        ])
    }

    private func buildStylePopUp() {
        stylePopUp.isBordered = false
        stylePopUp.refusesFirstResponder = true
        stylePopUp.controlSize = .small
        stylePopUp.font = .systemFont(ofSize: 12, weight: .medium)
        stylePopUp.toolTip = "Change what kind of block this is"
        stylePopUp.setAccessibilityLabel("Block style")

        let menu = NSMenu()
        for choice in BlockStyleChoice.allCases {
            let item = NSMenuItem(
                title: choice.title,
                action: #selector(styleChanged(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = choice.rawValue
            menu.addItem(item)
        }
        stylePopUp.menu = menu
        stack.addArrangedSubview(stylePopUp)
    }

    private func addInlineButton(_ style: InlineStyle, symbol: String, help: String) {
        let button = ToolbarButton(symbol: symbol, help: help) { [weak self] in
            self?.onInline?(style)
        }
        inlineButtons[style] = button
        stack.addArrangedSubview(button)
    }

    private func separator() -> NSView {
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            line.widthAnchor.constraint(equalToConstant: 1),
            line.heightAnchor.constraint(equalToConstant: 16)
        ])
        return line
    }

    @objc private func styleChanged(_ sender: NSMenuItem) {
        guard let choice = BlockStyleChoice(rawValue: sender.tag) else { return }
        onStyle?(choice)
    }

    /// Shows what the selection currently *is*, so the bar reads as a set of
    /// toggles rather than a set of one-way commands.
    func reflect(style: BlockStyleChoice?, activeInlineStyles: InlineStyle) {
        if let style {
            stylePopUp.selectItem(withTag: style.rawValue)
            stylePopUp.isEnabled = true
        } else {
            stylePopUp.isEnabled = false
        }
        for (style, button) in inlineButtons {
            button.isActive = activeInlineStyles.contains(style)
        }
    }
}

/// A button in the selection bar. Built as a plain view so a click can never
/// move first responder off the text — an `NSButton` that takes focus would
/// collapse the very selection the command is about to act on.
private final class ToolbarButton: NSView {
    var isActive = false {
        didSet { if isActive != oldValue { needsDisplay = true } }
    }

    private let symbol: String
    private let title: String?
    private let action: () -> Void
    private var isHovered = false
    private var isPressed = false
    private var trackingArea: NSTrackingArea?

    private lazy var iconView: NSImageView = {
        let view = NSImageView()
        view.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
        view.imageScaling = .scaleNone
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var titleLabel: NSTextField = {
        let field = NSTextField(labelWithString: title ?? "")
        field.font = .systemFont(ofSize: 11.5, weight: .medium)
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }()

    init(symbol: String, title: String? = nil, help: String, action: @escaping () -> Void) {
        self.symbol = symbol
        self.title = title
        self.action = action
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        toolTip = help
        setAccessibilityRole(.button)
        setAccessibilityLabel(help)
        translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        var constraints: [NSLayoutConstraint] = [
            heightAnchor.constraint(equalToConstant: 24),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: title == nil ? 7 : 8)
        ]

        if title != nil {
            addSubview(titleLabel)
            constraints += [
                titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 4),
                titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
                titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8)
            ]
        } else {
            constraints.append(iconView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7))
        }
        NSLayoutConstraint.activate(constraints)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        isPressed = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let wasPressed = isPressed
        isPressed = false
        needsDisplay = true
        guard wasPressed, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        action()
    }

    override func updateLayer() {
        let background: NSColor
        if isActive {
            background = .controlAccentColor.withAlphaComponent(isPressed ? 0.42 : 0.28)
        } else if isPressed {
            background = .labelColor.withAlphaComponent(0.18)
        } else if isHovered {
            background = .labelColor.withAlphaComponent(0.10)
        } else {
            background = .clear
        }
        layer?.backgroundColor = background.cgColor

        let tint: NSColor = isActive ? .controlAccentColor : .labelColor
        iconView.contentTintColor = tint
        titleLabel.textColor = tint
    }
}
