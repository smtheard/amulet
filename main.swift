// Amulet: a default "browser" that asks which Chrome profile should open each link.
// No network access, no config file, no dependencies, no special permissions.
// Build and install with ./build.sh.

import AppKit

struct Profile {
    let dir: String    // Chrome's folder name for the profile, e.g. "Default" or "Profile 1"
    let name: String   // what the picker shows
}

// The list of profiles is `profiles`, defined in Profiles.swift (see Profiles.example.swift).
// It is compiled in because macOS does not let other apps read Chrome's own profile list.

let chromeBundleID = "com.google.Chrome"

/// One clickable line in the picker.
final class Row: NSView {
    private let action: () -> Void

    var isSelected = false {
        didSet {
            layer?.backgroundColor = isSelected
                ? NSColor.controlAccentColor.withAlphaComponent(0.3).cgColor
                : nil
        }
    }

    init(number: Int, profile: Profile, action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6

        let title = NSMutableAttributedString(
            string: "\(number)   ",
            attributes: [.foregroundColor: NSColor.secondaryLabelColor,
                         .font: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .regular)])
        title.append(NSAttributedString(
            string: profile.name,
            attributes: [.foregroundColor: NSColor.labelColor,
                         .font: NSFont.systemFont(ofSize: 14, weight: .medium)]))

        let label = NSTextField(labelWithAttributedString: title)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // Clicks anywhere on the row, including on its text, belong to the row.
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { action() }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var pending: [URL] = []   // links waiting for a choice, oldest first
    private var rows: [Row] = []
    private var selected = 0
    private var panel: NSPanel?
    private var keyMonitor: Any?

    func application(_ application: NSApplication, open urls: [URL]) {
        // Only web links are accepted, so nothing else can reach Chrome's command line.
        pending += urls.filter { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }
        showPicker()
    }

    /// Shows the picker for the oldest waiting link, or closes it when none are left.
    private func showPicker() {
        panel?.orderOut(nil)
        panel = nil
        guard let url = pending.first else { return }

        let width: CGFloat = 380
        let more = pending.count > 1 ? "+\(pending.count - 1) more · " : ""
        let link = NSTextField(labelWithString: more + url.absoluteString)
        link.font = .systemFont(ofSize: 12)
        link.textColor = .secondaryLabelColor
        link.lineBreakMode = .byTruncatingMiddle

        rows = profiles.enumerated().map { index, profile in
            Row(number: index + 1, profile: profile) { [weak self] in self?.finish(openIn: index) }
        }
        rows[selected].isSelected = true

        let stack = NSStackView(views: [link] + rows)
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 2
        stack.setCustomSpacing(10, after: link)
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 8, bottom: 8, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: width).isActive = true
        link.widthAnchor.constraint(equalToConstant: width - 36).isActive = true
        rows.forEach { $0.widthAnchor.constraint(equalToConstant: width - 16).isActive = true }

        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
        ])

        let panel = NSPanel(contentRect: .zero, styleMask: [.titled, .fullSizeContentView],
                            backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = background
        panel.setContentSize(background.fittingSize)

        // Centre it, slightly high, on whichever screen the mouse is on.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let area = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: area.midX - panel.frame.width / 2,
                                         y: area.midY - panel.frame.height / 2 + area.height / 8))
        }

        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleKey(event) == true ? nil : event
            }
        }

        self.panel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    /// Returns true when the key was one of the picker's own.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard panel?.isVisible == true else { return false }
        switch event.keyCode {
        case 53:                       // Esc: drop this link
            finish(openIn: nil)
            if pending.isEmpty { NSApp.hide(nil) }   // hand focus back to the app you were in
        case 36, 76:                   // Return, Enter
            finish(openIn: selected)
        case 125:                      // Down
            select(selected + 1)
        case 126:                      // Up
            select(selected - 1)
        default:                       // 1–9 pick a profile directly
            guard let number = Int(event.charactersIgnoringModifiers ?? ""),
                  (1...profiles.count).contains(number) else { return false }
            finish(openIn: number - 1)
        }
        return true
    }

    private func select(_ index: Int) {
        rows[selected].isSelected = false
        selected = (index + rows.count) % rows.count
        rows[selected].isSelected = true
    }

    /// Opens the current link in the chosen profile (nil drops it), then moves to the next link.
    private func finish(openIn index: Int?) {
        guard !pending.isEmpty else { return }
        let url = pending.removeFirst()
        if let index { launch(url, in: profiles[index]) }
        selected = 0
        showPicker()
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
