import AppKit
import ApplicationServices
import AVFoundation
import SwiftUI

struct BindingKey: Codable, Equatable {
    var code: Int64
    var flags: UInt64
    var label: String
    static let initial = BindingKey(code: 49, flags: CGEventFlags.maskAlternate.rawValue, label: "⌥Space")
    static let modifiers: CGEventFlags = [.maskAlternate, .maskCommand, .maskShift, .maskControl]
}

final class Preferences: ObservableObject {
    @Published var order: [Tool] { didSet { defaults.set(order.map(\.rawValue), forKey: "order") } }
    @Published var disabled: Set<Tool> { didSet { defaults.set(disabled.map(\.rawValue), forKey: "disabled") } }
    @Published var shortcut: BindingKey {
        didSet { defaults.set(try? JSONEncoder().encode(shortcut), forKey: "shortcut") }
    }
    @Published var mouse: Int { didSet { defaults.set(mouse, forKey: "mouse") } }
    @Published var look: WheelLook {
        didSet { defaults.set(look.rawValue, forKey: "wheelLook") }
    }
    @Published var screenshotMode: ScreenshotMode {
        didSet { defaults.set(screenshotMode.rawValue, forKey: "screenshotMode") }
    }
    @Published var capturing = false
    @Published private(set) var shortcutError: String?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = (defaults.stringArray(forKey: "order") ?? []).compactMap(Tool.init(rawValue:))
        var seen = Set<Tool>()
        order = (saved + Tool.allCases).filter { seen.insert($0).inserted }
        disabled = Set((defaults.stringArray(forKey: "disabled") ?? []).compactMap(Tool.init(rawValue:)))
        shortcut = defaults.data(forKey: "shortcut")
            .flatMap { try? JSONDecoder().decode(BindingKey.self, from: $0) }
            .flatMap { binding in
                let flags = CGEventFlags(rawValue: binding.flags)
                return (0...127).contains(binding.code) && binding.code != 53 &&
                    !binding.label.isEmpty && !flags.isEmpty && flags.isSubset(of: BindingKey.modifiers) ? binding : nil
            } ?? .initial
        let savedMouse = defaults.integer(forKey: "mouse")
        mouse = [0, 2, 3, 4].contains(savedMouse) ? savedMouse : 0
        look = WheelLook(rawValue: defaults.string(forKey: "wheelLook") ?? "") ?? .glass
        screenshotMode = ScreenshotMode(rawValue: defaults.string(forKey: "screenshotMode") ?? "") ?? .area
    }

    func beginShortcutCapture() {
        shortcutError = nil
        capturing.toggle()
    }

    func resetShortcut() {
        shortcut = .initial
        shortcutError = nil
        capturing = false
    }

    func capture(_ event: NSEvent) {
        capture(code: event.keyCode, flags: CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue)),
                characters: event.charactersIgnoringModifiers)
    }

    func capture(code: UInt16, flags: CGEventFlags, characters: String?) {
        capturing = false
        shortcutError = nil
        guard code != 53 else { return }
        let flags = flags.intersection(BindingKey.modifiers)
        guard !flags.isEmpty else {
            shortcutError = "Use a modifier such as Option or Control."
            Diagnostics.input.notice("Rejected shortcut without a modifier")
            return
        }
        let symbols: [(CGEventFlags, String)] = [(.maskControl, "⌃"), (.maskAlternate, "⌥"), (.maskShift, "⇧"), (.maskCommand, "⌘")]
        let names: [UInt16: String] = [36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 123: "←", 124: "→", 125: "↓", 126: "↑"]
        guard code <= 127, let key = names[code] ?? characters?.uppercased(),
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              key.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
        else {
            shortcutError = "That key can’t be used as a shortcut."
            Diagnostics.input.notice("Rejected unsupported shortcut key")
            return
        }
        shortcut = BindingKey(code: Int64(code), flags: flags.rawValue,
                              label: symbols.filter { flags.contains($0.0) }.map(\.1).joined() + key)
    }
}

final class SettingsSession: ObservableObject {
    @Published var tab: Int
    @Published var accessibility = false
    @Published var screen = false
    @Published var microphone = false
    @Published var input = false

    init(tab: Int) { self.tab = tab }
}

struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    @StateObject var session: SettingsSession

    init(preferences: Preferences, tab: Int) {
        self.preferences = preferences
        _session = StateObject(wrappedValue: SettingsSession(tab: tab))
    }

    var body: some View {
        TabView(selection: $session.tab) {
            Form {
                LabeledContent("Keyboard shortcut") {
                    Button(preferences.capturing ? "Press shortcut…" : preferences.shortcut.label) {
                        preferences.beginShortcutCapture()
                    }
                    Button("Reset", action: preferences.resetShortcut)
                }
                if let error = preferences.shortcutError {
                    Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red)
                }
                Picker("Mouse trigger", selection: $preferences.mouse) {
                    Text("Off").tag(0)
                    Text("Middle button").tag(2)
                    Text("Button 4").tag(3)
                    Text("Button 5").tag(4)
                }
                Picker("Wheel look", selection: $preferences.look) {
                    ForEach(WheelLook.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Screenshot mode", selection: $preferences.screenshotMode) {
                    ForEach(ScreenshotMode.allCases) { Text($0.rawValue).tag($0) }
                }
                Text("Use a modifier with the shortcut. Press Esc to cancel recording.")
                    .foregroundStyle(.secondary)
                Text("Tap to keep the ring open. Hold, point, and release to use a tool. Use 1–8 or the arrow keys, Return to confirm, and Esc to close. Press Tab or scroll to switch rings.")
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .tabItem { Label("Controls", systemImage: "keyboard") }.tag(0)

            List {
                Text("Use Choose Tool to add a utility to either ring. The on/off switch applies to the selected tool.")
                    .foregroundStyle(.secondary)
                ForEach(0..<2) { ring in
                    Section("Ring \(ring + 1)") {
                        ForEach(ring * 8..<(ring + 1) * 8, id: \.self) { slot in
                            let tool = preferences.order[slot]
                            HStack {
                                Text("\(slot % 8 + 1)").monospacedDigit().foregroundStyle(.secondary)
                                Toggle(isOn: Binding(get: { !preferences.disabled.contains(tool) },
                                                     set: { enabled in
                                    if enabled { preferences.disabled.remove(tool) }
                                    else { preferences.disabled.insert(tool) }
                                })) { Label(tool.title, systemImage: tool.icon) }
                                Spacer()
                                Menu("Choose Tool") {
                                    ForEach(Tool.allCases) { candidate in
                                        Button {
                                            guard let index = preferences.order.firstIndex(of: candidate) else { return }
                                            preferences.order.swapAt(slot, index)
                                        } label: { Label(candidate.title, systemImage: candidate.icon) }
                                            .disabled(candidate == tool)
                                    }
                                }.fixedSize()
                                Button { preferences.order.swapAt(slot, slot - 1) } label: {
                                    Image(systemName: "chevron.up")
                                }.buttonStyle(.borderless).disabled(slot == 0).accessibilityLabel("Move up")
                                Button { preferences.order.swapAt(slot, slot + 1) } label: {
                                    Image(systemName: "chevron.down")
                                }.buttonStyle(.borderless).disabled(slot == Tool.slotCount - 1).accessibilityLabel("Move down")
                            }
                        }
                    }
                }
            }
            .tabItem { Label("Tools", systemImage: "circle.grid.cross") }.tag(1)

            Form {
                permission("Accessibility", "Open the menu globally and control apps and windows.", session.accessibility) {
                    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                    _ = AXIsProcessTrustedWithOptions(options)
                    openPrivacy("Accessibility")
                }
                permission("Screen Recording", "Copy a screenshot of the current display.", session.screen) {
                    _ = CGRequestScreenCaptureAccess()
                    openPrivacy("ScreenCapture")
                }
                permission("Microphone", "Record voice memos when you select the microphone tool.", session.microphone) {
                    if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                        AVCaptureDevice.requestAccess(for: .audio) { _ in }
                    } else { openPrivacy("Microphone") }
                }
                if session.accessibility && !session.input {
                    permission("Input Monitoring", "Allow the global shortcut if macOS requires separate input access.", session.input) {
                        _ = CGRequestListenEventAccess()
                        openPrivacy("ListenEvent")
                    }
                }
                Text("After granting access in System Settings, reopen Untill if macOS asks you to quit and reopen.")
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .tabItem { Label("Permissions", systemImage: "lock.shield") }.tag(2)
        }
        .padding(16)
        .frame(width: 580, height: 476)
        .onAppear(perform: refresh)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in refresh() }
    }

    private func permission(_ title: String, _ detail: String, _ granted: Bool, action: @escaping () -> Void) -> some View {
        LabeledContent {
            if granted { Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            else { Button("Grant Access", action: action) }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).fontWeight(.semibold)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func refresh() {
        session.accessibility = AXIsProcessTrusted()
        session.screen = CGPreflightScreenCaptureAccess()
        session.microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        session.input = CGPreflightListenEventAccess()
    }

    private func openPrivacy(_ section: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(section)") {
            NSWorkspace.shared.open(url)
        }
    }
}
