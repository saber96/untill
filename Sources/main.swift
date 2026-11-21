import AppKit
import SwiftUI
import ApplicationServices

final class App: NSObject, NSApplicationDelegate, NSWindowDelegate {
    enum Trigger: Equatable {
        case key(Int64), mouse(Int64)
    }

    let preferences = Preferences()
    let state = MenuState()
    let actions = ToolActions()
    let size: CGFloat = 416
    lazy var panel = OverlayPanel(state: state, size: size)
    var tap: CFMachPort?
    var tapSource: CFRunLoopSource?
    private var reportedTapFailure = false
    var status: NSStatusItem?
    var settings: NSWindow?
    var localMonitor: Any?
    var timer: Timer?
    var trigger: Trigger?
    var pressedAt: UInt64 = 0
    var center = NSPoint.zero
    var screen: NSScreen?
    var target: NSRunningApplication?
    var swallowedKeys = Set<Int64>()
    var swallowedMouse = Set<Int64>()
    var scrollDirection: Int64 = 0
    var lastScroll: UInt64 = 0
    var scrollDistance: Int64 = 0
    var slider: (initial: Double, anchor: Double, angle: Double)?
    var generation = 0
    var lastMotionPoint: NSPoint?
    var feedbackPanel: NSPanel?
    var capturingScreenshot = false
    var areaPanel: AreaPanel?
    var utilityWindow: NSWindow?
    var shownUtility: Utility?
    let utilities = UtilityModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Diagnostics.lifecycle.info("Untill launched")
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status?.button?.image = NSImage(systemSymbolName: "circle.dotted.circle", accessibilityDescription: "Untill")
            ?? NSImage(systemSymbolName: "circle.grid.cross", accessibilityDescription: "Untill")
        let menu = NSMenu()
        for (title, action, key) in [
            ("Settings…", #selector(showSettings), ","),
            ("Permissions…", #selector(showPermissions), ""),
            ("Quit Untill", #selector(quit), "q")
        ] {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.target = self
        }
        status?.menu = menu
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.preferences.capturing, self.settings?.isKeyWindow == true else { return event }
            self.preferences.capture(event)
            return nil
        }
        installTap()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.installTap()
            let clipboardVisible = self.shownUtility == .clipboard && self.utilityWindow?.isVisible == true
            if let message = self.utilities.tick(clipboardVisible: clipboardVisible) {
                NSSound.beep()
                self.showFeedback("Timer Finished", detail: message, on: nil)
            }
        }
        if !UserDefaults.standard.bool(forKey: "openedOnboarding") || !AXIsProcessTrusted() {
            showPermissions()
            UserDefaults.standard.set(true, forKey: "openedOnboarding")
        }
    }

    func installTap() {
        if let tap, CFMachPortIsValid(tap) { return }
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        tap = nil
        tapSource = nil
        guard AXIsProcessTrusted() else {
            reportedTapFailure = false
            return
        }
        let events: [CGEventType] = [.keyDown, .keyUp, .mouseMoved, .leftMouseDown, .leftMouseUp,
                                    .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
                                    .otherMouseDown, .otherMouseUp, .scrollWheel]
        let mask = events.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let app = Unmanaged<App>.fromOpaque(context).takeUnretainedValue()
            return app.handle(type, event) ? nil : Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            if !reportedTapFailure {
                Diagnostics.input.error("Could not install the global shortcut event tap")
                reportedTapFailure = true
            }
            return
        }
        reportedTapFailure = false
        tap = port
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        tapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
    }

    func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Diagnostics.input.notice("Restoring disabled global event tap (reason \(type.rawValue))")
            close(commit: false)
            trigger = nil
            swallowedKeys.removeAll()
            swallowedMouse.removeAll()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        if event.getIntegerValueField(.eventSourceUserData) == ToolActions.synthetic { return false }
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        let button = type == .leftMouseDown || type == .leftMouseUp ? 0 : event.getIntegerValueField(.mouseEventButtonNumber)

        if type == .keyUp, swallowedKeys.remove(key) != nil {
            if trigger == .key(key) { release(event.timestamp) }
            return true
        }
        if (type == .otherMouseUp || type == .leftMouseUp), swallowedMouse.remove(button) != nil {
            if trigger == .mouse(button) { release(event.timestamp) }
            return true
        }
        if preferences.capturing || areaPanel != nil { return false }
        if type == .keyDown {
            if swallowedKeys.contains(key) {
                if state.visible, trigger != .key(key), (123...126).contains(key) { _ = handleKey(key) }
                return true
            }
            let binding = preferences.shortcut
            if key == binding.code, event.flags.intersection(BindingKey.modifiers).rawValue == binding.flags,
               event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                swallowedKeys.insert(key)
                press(.key(key), event.timestamp)
                return true
            }
            if state.visible, handleKey(key) {
                swallowedKeys.insert(key)
                return true
            }
        }
        if type == .otherMouseDown, button == preferences.mouse {
            swallowedMouse.insert(button)
            press(.mouse(button), event.timestamp)
            return true
        }
        guard state.visible else { return false }
        switch type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            updatePointer()
            return false
        case .leftMouseDown:
            let point = NSEvent.mouseLocation
            if slider == nil && hypot(point.x - center.x, point.y - center.y) > Radial.clickRadius {
                close(commit: false)
                return false
            }
            updatePointer(force: true)
            swallowedMouse.insert(button)
            activateSelection()
            return true
        case .scrollWheel:
            scroll(event)
            return true
        default: return false
        }
    }

    func press(_ input: Trigger, _ time: UInt64) {
        guard trigger == nil else { return }
        trigger = input
        pressedAt = time
        if state.visible {
            close(commit: false)
            return
        }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
                ?? NSScreen.main else { return }
        let bounds = screen.frame
        let half = size / 2
        center = NSPoint(x: min(max(mouse.x, bounds.minX + half), bounds.maxX - half),
                         y: min(max(mouse.y, bounds.minY + half), bounds.maxY - half))
        self.screen = screen
        target = NSWorkspace.shared.frontmostApplication
        generation += 1
        lastMotionPoint = mouse
        scrollDirection = 0
        scrollDistance = 0
        lastScroll = 0
        state.ring = 0
        state.selected = nil
        state.disabled = preferences.disabled
        state.recording = actions.recording
        state.look = preferences.look
        setRingTools()
        panel.setFrameOrigin(NSPoint(x: center.x - half, y: center.y - half))
        panel.orderFrontRegardless()
        state.visible = true
    }

    func release(_ time: UInt64) {
        trigger = nil
        guard state.visible, time >= pressedAt else { return }
        if time - pressedAt >= 220_000_000 { close(commit: true) }
    }

    func close(commit: Bool) {
        guard state.visible else { return }
        let tool = state.selected.map { state.tools[$0] }
        let volume = state.volume
        let target = self.target
        let screen = self.screen
        state.visible = false
        state.selected = nil
        state.volume = nil
        slider = nil
        generation += 1
        let version = generation
        if commit, let tool {
            panel.orderOut(nil)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let actions = self.actions
                if tool == .screenshot || tool == .screenshotArea {
                    let mode: ScreenshotMode = tool == .screenshotArea ? .area : self.preferences.screenshotMode
                    Task { @MainActor in self.beginScreenshot(on: screen, mode: mode) }
                } else if let utility = tool.utility {
                    self.showUtility(utility)
                } else if tool == .volume { if let volume { actions.setVolume(volume) } }
                else { actions.run(tool, target: target, screen: screen) }
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.17) { [weak self] in
                guard let self, self.generation == version else { return }
                self.panel.orderOut(nil)
            }
        }
    }

    func setRingTools() {
        state.tools = Array(preferences.order.dropFirst(state.ring * 8).prefix(8))
    }

    func scroll(_ event: CGEvent) {
        let phase = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
        guard slider == nil, phase == 0 else { return }
        let delta = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        let lines = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let amount = delta == 0 ? lines * 12 : delta
        guard amount != 0 else { return }
        let direction = amount.signum()
        if event.timestamp < lastScroll || event.timestamp - lastScroll > 180_000_000 || direction != scrollDirection {
            scrollDistance = 0
        }
        lastScroll = event.timestamp
        scrollDirection = direction
        scrollDistance += abs(amount)
        guard scrollDistance >= 9 else { return }
        switchRing(to: direction < 0 ? 1 : 0)
    }

    func switchRing(to next: Int) {
        guard next != state.ring else { return }
        slider = nil
        state.volume = nil
        state.ring = next
        state.selected = nil
        setRingTools()
    }

    func select(_ slot: Int?) {
        state.selected = slot.flatMap { state.disabled.contains(state.tools[$0]) ? nil : $0 }
    }

    func updatePointer(force: Bool = false) {
        let mouse = NSEvent.mouseLocation
        guard force || mouse != lastMotionPoint else { return }
        lastMotionPoint = mouse
        let dx = mouse.x - center.x
        let dy = mouse.y - center.y
        if let slider {
            let projection = dx * sin(slider.angle) + dy * cos(slider.angle)
            state.volume = Radial.volume(from: slider.initial, projection: projection, anchor: slider.anchor)
            return
        }
        select(Radial.sector(x: dx, y: dy))
        if let slot = state.selected, state.tools[slot] == .volume, hypot(dx, dy) >= Radial.push {
            let angle = Double(slot) * Radial.step
            startSlider(angle: angle, anchor: dx * sin(angle) + dy * cos(angle))
        }
    }

    func startSlider(angle: Double, anchor: Double) {
        guard let current = actions.readVolume() else {
            Diagnostics.tools.notice("Volume slider is unavailable on the current output")
            NSSound.beep()
            return
        }
        slider = (current, anchor, angle)
        state.volume = current
    }

    func handleKey(_ key: Int64) -> Bool {
        if key == 48 { switchRing(to: 1 - state.ring); return true }
        if key == 53 { close(commit: false); return true }
        if let volume = state.volume, (123...126).contains(key) {
            state.volume = min(1, max(0, volume + ([124, 126].contains(key) ? 0.05 : -0.05)))
            return true
        }
        if key == 36 || key == 76 {
            activateSelection()
            return true
        }
        if let slot = Radial.numbers.firstIndex(of: key) {
            guard slider == nil else { return true }
            select(slot)
            if state.selected != nil { activateSelection() }
            return true
        }
        guard (123...126).contains(key) else { return false }
        let direction = [124, 125].contains(key) ? 1 : -1
        let initial: [Int64: Int] = [123: 6, 124: 2, 125: 4, 126: 0]
        let start = state.selected.map { ($0 + direction + 8) % 8 } ?? initial[key, default: 0]
        for offset in 0..<8 {
            select((start + offset * direction + 8) % 8)
            if state.selected != nil { break }
        }
        return true
    }

    func activateSelection() {
        if let slot = state.selected, state.tools[slot] == .volume, slider == nil {
            let angle = Double(slot) * Radial.step
            let mouse = NSEvent.mouseLocation
            startSlider(angle: angle, anchor: (mouse.x - center.x) * sin(angle) + (mouse.y - center.y) * cos(angle))
        } else { close(commit: true) }
    }

    @MainActor
    func beginScreenshot(on screen: NSScreen?, mode: ScreenshotMode) {
        guard !capturingScreenshot, areaPanel == nil else { return }
        guard mode == .area, CGPreflightScreenCaptureAccess(), let screen else {
            Task { await captureScreenshot(on: screen) }
            return
        }
        feedbackPanel?.orderOut(nil)
        feedbackPanel = nil
        let selector = AreaPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        selector.isOpaque = false
        selector.backgroundColor = .clear
        selector.hasShadow = false
        selector.level = .screenSaver
        selector.collectionBehavior = panel.collectionBehavior
        selector.delegate = self
        let selection = AreaSelectionView(frame: NSRect(origin: .zero, size: screen.frame.size)) { [weak self] area in
            guard let self else { return }
            self.dismissAreaSelection()
            if let area { Task { @MainActor in await self.captureScreenshot(on: screen, area: area) } }
        }
        selector.contentView = selection
        selector.setFrame(screen.frame, display: false)
        areaPanel = selector
        selector.makeKeyAndOrderFront(nil)
        selector.makeFirstResponder(selection)
    }

    private func dismissAreaSelection() {
        let selector = areaPanel
        areaPanel = nil
        selector?.orderOut(nil)
    }

    @MainActor
    func captureScreenshot(on screen: NSScreen?, area: CGRect? = nil) async {
        guard !capturingScreenshot else { return }
        capturingScreenshot = true
        defer { capturingScreenshot = false }
        feedbackPanel?.orderOut(nil)
        feedbackPanel = nil
        do {
            let image = try await actions.screenshot(screen, area: area)
            showFeedback("Screenshot", detail: "Copied to Clipboard", image: image, on: screen)
        } catch {
            let failure = error as NSError
            Diagnostics.capture.error("Screenshot failed (\(failure.domain, privacy: .public):\(failure.code))")
            let needsPermission = !CGPreflightScreenCaptureAccess()
            let alert = NSAlert()
            alert.messageText = needsPermission ? "Screen Recording is required" : "Screenshot failed"
            if needsPermission {
                alert.informativeText = "Allow Untill in Screen Recording, then try again. macOS may ask you to reopen the app."
                alert.addButton(withTitle: "Open Permissions")
                alert.addButton(withTitle: "Cancel")
            } else {
                switch error {
                case ToolActions.ScreenshotError.displayUnavailable:
                    alert.informativeText = "The selected display is unavailable. Open the ring on an active display and try again."
                case ToolActions.ScreenshotError.clipboardFailed:
                    alert.informativeText = "The screenshot could not be copied to the clipboard. Try again."
                default:
                    alert.informativeText = error.localizedDescription
                }
                alert.addButton(withTitle: "OK")
            }
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn && needsPermission { showPermissions() }
        }
    }

    func showFeedback(_ title: String, detail: String, image: NSImage? = nil, on screen: NSScreen?) {
        feedbackPanel?.orderOut(nil)
        guard let frame = (screen ?? NSScreen.main)?.visibleFrame else { return }
        let bounds = NSRect(x: frame.maxX - 288, y: frame.minY + 24, width: 264, height: 78)
        let preview = NSPanel(contentRect: bounds, styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        preview.isOpaque = false
        preview.backgroundColor = .clear
        preview.ignoresMouseEvents = true
        preview.hidesOnDeactivate = false
        preview.level = .popUpMenu
        preview.collectionBehavior = panel.collectionBehavior
        preview.contentView = NSHostingView(rootView:
            HStack(spacing: 12) {
                if let image {
                    Image(nsImage: image).resizable().scaledToFit()
                        .frame(width: 84, height: 54)
                        .background(.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Image(systemName: "timer").font(.system(size: 24))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(detail).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(width: 264, height: 78)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        )
        preview.orderFrontRegardless()
        feedbackPanel = preview
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self, weak preview] in
            guard let self, let preview, self.feedbackPanel === preview else { return }
            preview.orderOut(nil)
            self.feedbackPanel = nil
        }
    }

    func showUtility(_ utility: Utility) {
        let window = utilityWindow ?? NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 300),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        if shownUtility != utility || utilityWindow == nil {
            window.title = utility.rawValue
            window.contentView = NSHostingView(rootView: UtilityView(utility: utility, model: utilities, actions: actions))
        }
        if utilityWindow == nil { window.center() }
        if utility == .clipboard { utilities.captureClipboard() }
        utilityWindow = window
        shownUtility = utility
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc func showSettings() { show(tab: 0) }
    @objc func showPermissions() { show(tab: 2) }
    @objc func quit() { NSApp.terminate(nil) }

    func show(tab: Int) {
        preferences.capturing = false
        let window = settings ?? NSWindow(contentRect: .init(x: 0, y: 0, width: 580, height: 476),
                                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Untill Settings"
        window.delegate = self
        window.contentView = NSHostingView(rootView: SettingsView(preferences: preferences, tab: tab))
        if settings == nil { window.center() }
        settings = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === areaPanel { dismissAreaSelection() }
        if window === settings { preferences.capturing = false }
    }

    func applicationDidResignActive(_ notification: Notification) {
        preferences.capturing = false
    }
}

let application = NSApplication.shared
let delegate = App()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
