// Amulet: a default "browser" that asks which Chrome profile should open each link.
// No network access, no config file, no dependencies, no special permissions.
// Build and install with ./build.sh.

import AppKit

struct Profile {
    let dir: String    // Chrome's folder name for the profile, e.g. "Default" or "Profile 1"
    let name: String   // what the picker shows
    let color: Int     // the colour of the profile's gem, as 0xRRGGBB

    init(dir: String, name: String, color: Int = 0x8E8E93) {
        self.dir = dir
        self.name = name
        self.color = color
    }
}

// The list of profiles is `profiles`, defined in Profiles.swift (see Profiles.example.swift).
// It is compiled in because macOS does not let other apps read Chrome's own profile list.

let chromeBundleID = "com.google.Chrome"

/// How long each piece of motion takes, in seconds.
enum Timing {
    static let appear = 0.14
    static let select = 0.12
    static let close = 0.13
}

enum Metrics {
    static let gem: CGFloat = 28
    static let cellWidth: CGFloat = 72
    static let corner: CGFloat = 12
    static let margin: CGFloat = 28   // clear space around the card, so its shadow has room
}

extension NSColor {
    convenience init(hex: Int) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

/// A transform that scales a layer about a point given in the layer's own coordinates.
func scaleTransform(_ scale: CGFloat, about point: CGPoint, in layer: CALayer, size: CGSize) -> CATransform3D {
    let dx = point.x - layer.anchorPoint.x * size.width
    let dy = point.y - layer.anchorPoint.y * size.height
    var transform = CATransform3DMakeTranslation(dx, dy, 0)
    transform = CATransform3DScale(transform, scale, scale, 1)
    return CATransform3DTranslate(transform, -dx, -dy, 0)
}

/// A flat disc in a profile's colour, carrying its initial. A thin ring marks the selected one.
final class GemView: NSView {
    private let disc = CALayer()
    private let ring = CAShapeLayer()
    private let letter = CATextLayer()

    init(profile: Profile) {
        let size = Metrics.gem
        let bounds = CGRect(x: 0, y: 0, width: size, height: size)
        let centre = CGPoint(x: size / 2, y: size / 2)
        let color = NSColor(hex: profile.color)
        super.init(frame: bounds)
        wantsLayer = true
        layer?.masksToBounds = false

        disc.bounds = bounds
        disc.position = centre
        disc.cornerRadius = size / 2
        disc.backgroundColor = color.cgColor

        ring.bounds = bounds
        ring.position = centre
        ring.path = CGPath(ellipseIn: bounds.insetBy(dx: -3.5, dy: -3.5), transform: nil)
        ring.fillColor = nil
        ring.strokeColor = color.cgColor
        ring.lineWidth = 1.5
        ring.opacity = 0

        let initial = NSAttributedString(
            string: profile.name.first.map { String($0).uppercased() } ?? "•",
            attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                         .foregroundColor: NSColor.white])
        let height = initial.size().height
        letter.string = initial
        letter.alignmentMode = .center
        letter.frame = CGRect(x: 0, y: (size - height) / 2, width: size, height: height)
        disc.addSublayer(letter)

        layer?.addSublayer(ring)
        layer?.addSublayer(disc)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var intrinsicContentSize: NSSize { NSSize(width: Metrics.gem, height: Metrics.gem) }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        letter.contentsScale = window?.backingScaleFactor ?? 2
    }

    func setSelected(_ selected: Bool, animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(Timing.select)
        ring.opacity = selected ? 1 : 0
        CATransaction.commit()
    }

    /// The ring widens and fades once, to confirm the choice.
    func confirm() {
        let widen = CABasicAnimation(keyPath: "transform.scale")
        widen.toValue = 1.45
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.toValue = 0
        let ping = CAAnimationGroup()
        ping.animations = [widen, fade]
        ping.duration = Timing.close
        ping.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ping.fillMode = .forwards
        ping.isRemovedOnCompletion = false
        ring.add(ping, forKey: "confirm")
    }
}

/// A gem with its name and number key beneath it.
final class GemCell: NSView {
    let gem: GemView
    private let name: NSTextField
    var onHover: () -> Void = {}
    var onClick: () -> Void = {}

    init(number: Int, profile: Profile) {
        gem = GemView(profile: profile)
        name = NSTextField(labelWithString: profile.name)
        super.init(frame: .zero)

        name.font = .systemFont(ofSize: 11)
        name.alignment = .center
        name.lineBreakMode = .byTruncatingTail
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let key = NSTextField(labelWithString: "\(number)")
        key.font = .monospacedDigitSystemFont(ofSize: 9.5, weight: .regular)
        key.textColor = .tertiaryLabelColor

        let stack = NSStackView(views: [gem, name, key])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 1
        stack.setCustomSpacing(8, after: gem)
        stack.edgeInsets = NSEdgeInsets(top: 5, left: 0, bottom: 0, right: 0)   // room for the ring
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Metrics.cellWidth),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            name.widthAnchor.constraint(lessThanOrEqualToConstant: Metrics.cellWidth - 6),
        ])
        setSelected(false, animated: false)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func setSelected(_ selected: Bool, animated: Bool) {
        gem.setSelected(selected, animated: animated)
        name.textColor = selected ? .labelColor : .secondaryLabelColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways],
                                       owner: self))
    }

    // Clicks anywhere in the cell, including on its text, belong to the cell.
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with event: NSEvent) { onHover() }
    override func mouseDown(with event: NSEvent) { onClick() }
}

/// The card the picker sits on: a flat surface with a hairline edge and one quiet shadow.
final class Card: NSView {
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 0.5
        layer?.cornerRadius = Metrics.corner
        layer?.cornerCurve = .continuous
    }
}

/// A borderless panel that can still take the keyboard.
final class PickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var pending: [URL] = []   // links waiting for a choice, oldest first
    private var cells: [GemCell] = []
    private var selected = 0
    private var panel: PickerPanel?
    private var isClosing = false
    private var keyMonitor: Any?

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    func application(_ application: NSApplication, open urls: [URL]) {
        // Only web links are accepted, so nothing else can reach Chrome's command line.
        pending += urls.filter { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }
        if !isClosing { showPicker() }
    }

    /// Shows the picker for the oldest waiting link.
    private func showPicker() {
        let replaced = panel?.isVisible == true ? panel?.frame : nil
        panel?.orderOut(nil)
        panel = nil
        guard let url = pending.first else { return }

        // The site first, then the rest of the address, quieter.
        let site = NSTextField(labelWithString: (url.host ?? url.absoluteString)
            .replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression))
        site.font = .systemFont(ofSize: 13, weight: .semibold)
        site.textColor = .labelColor

        var rest = url.path == "/" ? "" : url.path
        if let query = url.query { rest += "?" + query }
        if pending.count > 1 { rest += (rest.isEmpty ? "" : "  ") + "+\(pending.count - 1) more" }
        let detail = NSTextField(labelWithString: rest)
        detail.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        detail.textColor = .tertiaryLabelColor

        let header = rest.isEmpty ? [site] : [site, detail]
        cells = profiles.enumerated().map { index, profile in
            let cell = GemCell(number: index + 1, profile: profile)
            cell.onHover = { [weak self] in self?.select(index) }
            cell.onClick = { [weak self] in self?.finish(openIn: index) }
            return cell
        }
        cells[selected].setSelected(true, animated: false)

        let row = NSStackView(views: cells)
        row.orientation = .horizontal
        row.spacing = 0

        let rule = NSBox()
        rule.boxType = .separator

        let width = max(CGFloat(cells.count) * Metrics.cellWidth, 200)
        let stack = NSStackView(views: header + [rule, row])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 1
        stack.setCustomSpacing(9, after: header[header.count - 1])
        stack.setCustomSpacing(8, after: rule)
        stack.edgeInsets = NSEdgeInsets(top: 11, left: 12, bottom: 9, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: width + 24).isActive = true
        rule.widthAnchor.constraint(equalToConstant: width).isActive = true
        for label in header {
            label.alignment = .center
            label.lineBreakMode = .byTruncatingMiddle
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            label.widthAnchor.constraint(lessThanOrEqualToConstant: width).isActive = true
        }

        let card = Card()
        card.wantsLayer = true
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
        ])
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.2)
        shadow.shadowBlurRadius = 14
        shadow.shadowOffset = NSSize(width: 0, height: -5)
        card.shadow = shadow

        // The window is larger than the card by a clear margin, so the shadow is not cut off.
        let margin = Metrics.margin
        let cardSize = stack.fittingSize
        let size = NSSize(width: cardSize.width + margin * 2, height: cardSize.height + margin * 2)
        let content = NSView(frame: NSRect(origin: .zero, size: size))
        content.wantsLayer = true
        card.frame = NSRect(x: margin, y: margin, width: cardSize.width, height: cardSize.height)
        content.addSubview(card)

        let panel = PickerPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                                backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = content

        // A picker that is already open stays where it is; a new one opens at the pointer.
        var below = true
        if let replaced {
            panel.setFrameTopLeftPoint(NSPoint(x: replaced.minX, y: replaced.maxY))
        } else {
            below = place(panel)
        }

        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleKey(event) == true ? nil : event
            }
        }

        self.panel = panel
        NSApp.activate(ignoringOtherApps: true)
        if replaced == nil { panel.alphaValue = 0 }
        panel.makeKeyAndOrderFront(nil)
        if replaced == nil { animateIn(panel, from: below ? .maxY : .minY) }
    }

    /// Puts the card just under the pointer, or just above it when there is no room below.
    /// Returns whether it went below.
    private func place(_ panel: NSPanel) -> Bool {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let area = screen?.visibleFrame.insetBy(dx: 8, dy: 8) else { return true }
        let margin = Metrics.margin
        let card = NSSize(width: panel.frame.width - margin * 2, height: panel.frame.height - margin * 2)
        let x = min(max(mouse.x - card.width / 2, area.minX), area.maxX - card.width)
        var y = mouse.y - 14 - card.height
        let below = y >= area.minY
        if !below { y = min(mouse.y + 14, area.maxY - card.height) }
        panel.setFrameOrigin(NSPoint(x: x - margin, y: y - margin))
        return below
    }

    /// Fades the picker in, growing very slightly out of the edge nearest the pointer.
    private func animateIn(_ panel: NSPanel, from edge: NSRectEdge) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Timing.appear
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        guard !reduceMotion, let content = panel.contentView, let layer = content.layer else { return }

        let margin = Metrics.margin
        let pivot = CGPoint(x: content.bounds.midX, y: edge == .maxY ? content.bounds.maxY - margin : margin)
        let grow = CABasicAnimation(keyPath: "transform")
        grow.fromValue = NSValue(caTransform3D: scaleTransform(0.96, about: pivot, in: layer, size: content.bounds.size))
        grow.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        grow.duration = Timing.appear
        grow.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
        layer.add(grow, forKey: "grow")
    }

    /// Returns true when the key was one of the picker's own.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard panel?.isVisible == true else { return false }
        switch event.keyCode {
        case 53:                       // Esc: drop this link
            finish(openIn: nil)
        case 36, 76:                   // Return, Enter
            finish(openIn: selected)
        case 124:                      // Right
            select(selected + 1)
        case 123:                      // Left
            select(selected - 1)
        case 48:                       // Tab, Shift-Tab
            select(selected + (event.modifierFlags.contains(.shift) ? -1 : 1))
        default:                       // 1–9 pick a profile directly
            guard let number = Int(event.charactersIgnoringModifiers ?? ""),
                  (1...profiles.count).contains(number) else { return false }
            finish(openIn: number - 1)
        }
        return true
    }

    private func select(_ index: Int) {
        let index = (index + cells.count) % cells.count
        guard !isClosing, index != selected else { return }
        cells[selected].setSelected(false, animated: true)
        selected = index
        cells[selected].setSelected(true, animated: true)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    /// Opens the current link in the chosen profile (nil drops it), then closes the picker.
    private func finish(openIn index: Int?) {
        guard !isClosing, !pending.isEmpty else { return }
        let url = pending.removeFirst()
        if let index {
            // Show the choice on the gem even when it was made with a number key.
            cells[selected].setSelected(false, animated: false)
            cells[index].setSelected(true, animated: false)
            launch(url, in: profiles[index])
        }
        close(around: index)
    }

    /// Fades the picker out, with the chosen gem's ring widening once, then moves to the next link.
    private func close(around chosen: Int?) {
        guard let panel else { return }
        isClosing = true
        if let chosen, !reduceMotion { cells[chosen].gem.confirm() }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Timing.close
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                panel.orderOut(nil)
                self.panel = nil
                self.isClosing = false
                self.selected = 0
                // Dropping the last link hands focus back to the app you were in.
                if chosen == nil, self.pending.isEmpty { NSApp.hide(nil) }
                self.showPicker()
            }
        })
    }

    private func launch(_ url: URL, in profile: Profile) {
        // -n starts a second Chrome process, which hands the link to the Chrome that is
        // already running, in this profile, and then exits.
        let arguments = ["-n", "-b", chromeBundleID, "--args",
                         "--profile-directory=\(profile.dir)", url.absoluteString]
        NSApp.yieldActivation(toApplicationWithBundleIdentifier: chromeBundleID)
        do {
            _ = try Process.run(URL(fileURLWithPath: "/usr/bin/open"), arguments: arguments)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

// MARK: - Entry point

if CommandLine.arguments.contains("--make-default") {
    // macOS shows its own confirmation dialog before it changes the default browser.
    func claim(_ schemes: ArraySlice<String>) {
        guard let scheme = schemes.first else {
            print("Amulet is now the default browser")
            exit(0)
        }
        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL,
                                                 toOpenURLsWithScheme: scheme) { error in
            if let error {
                print("Default browser not changed (\(scheme)): \(error.localizedDescription)")
                exit(1)
            }
            claim(schemes.dropFirst())
        }
    }
    claim(["http", "https"])
    dispatchMain()
}

precondition(!profiles.isEmpty, "Profiles.swift lists no profiles")

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
