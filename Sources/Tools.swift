import AppKit
import ApplicationServices
import AVFoundation
import CoreAudio
import ScreenCaptureKit

enum Tool: String, CaseIterable, Identifiable {
    case copy, paste, cut, plainPaste, undo, redo, selectAll, search
    case left, right, maximize, screenshot, record, playPause, next, volume

    case pins, music, clipboard, notes, timers, askAI, screenshotArea

    static let slotCount = 16

    var utility: Utility? {
        switch self {
        case .pins: .pins
        case .music: .music
        case .clipboard: .clipboard
        case .notes: .notes
        case .timers: .timers
        case .askAI: .askAI
        default: nil
        }
    }

    var id: String { rawValue }
    var title: String {
        switch self {
        case .copy: "Copy"
        case .paste: "Paste"
        case .cut: "Cut"
        case .plainPaste: "Plain paste"
        case .undo: "Undo"
        case .redo: "Redo"
        case .selectAll: "Select all"
        case .search: "Spotlight"
        case .left: "Tile left"
        case .right: "Tile right"
        case .maximize: "Fill screen"
        case .screenshot: "Screenshot"
        case .screenshotArea: "Screenshot Area"
        case .record: "Voice memo"
        case .playPause: "Play / pause"
        case .next: "Next track"
        case .volume: "Volume"
        case .pins: "Pinned Apps"
        case .music: "Music"
        case .clipboard: "Clipboard"
        case .notes: "Notes"
        case .timers: "Timers"
        case .askAI: "Ask AI"
        }
    }
    var icon: String {
        switch self {
        case .copy: "document.on.document"
        case .paste: "clipboard"
        case .cut: "scissors"
        case .plainPaste: "text.alignleft"
        case .undo: "arrow.uturn.backward"
        case .redo: "arrow.uturn.forward"
        case .selectAll: "selection.pin.in.out"
        case .search: "magnifyingglass"
        case .left: "rectangle.lefthalf.filled"
        case .right: "rectangle.righthalf.filled"
        case .maximize: "arrow.up.left.and.arrow.down.right"
        case .screenshot: "camera.viewfinder"
        case .screenshotArea: "viewfinder"
        case .record: "mic"
        case .playPause: "playpause"
        case .next: "forward.end"
        case .volume: "speaker.wave.2"
        case .pins: "pin"
        case .music: "music.note"
        case .clipboard: "list.clipboard"
        case .notes: "note.text"
        case .timers: "timer"
        case .askAI: "sparkles"
        }
    }
}

final class ToolActions: NSObject, AVAudioRecorderDelegate {
    static let synthetic: Int64 = 0x52414449414C
    private var recorder: AVAudioRecorder?
    var recording: Bool { recorder?.isRecording == true }

    func run(_ tool: Tool, target: NSRunningApplication?, screen: NSScreen?) {
        switch tool {
        case .copy: key(8, .maskCommand)
        case .paste: key(9, .maskCommand)
        case .cut: key(7, .maskCommand)
        case .plainPaste: plainPaste()
        case .undo: key(6, .maskCommand)
        case .redo: key(6, [.maskCommand, .maskShift])
        case .selectAll: key(0, .maskCommand)
        case .search: key(49, .maskCommand)
        case .left, .right, .maximize: tile(tool, target: target, screen: screen)
        case .screenshot, .screenshotArea: break
        case .record: record()
        case .playPause: media(16)
        case .next: media(17)
        case .volume, .pins, .music, .clipboard, .notes, .timers, .askAI: break
        }
    }

    private func key(_ code: CGKeyCode, _ flags: CGEventFlags) {
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
            event?.flags = flags
            event?.setIntegerValueField(.eventSourceUserData, value: Self.synthetic)
            event?.post(tap: .cghidEventTap)
        }
    }

    private func plainPaste() {
        let board = NSPasteboard.general
        guard let string = board.string(forType: .string) else {
            Diagnostics.tools.notice("Plain Paste requires text on the clipboard")
            NSSound.beep()
            return
        }
        let saved: [NSPasteboardItem] = board.pasteboardItems?.map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        } ?? []
        board.clearContents()
        guard board.setString(string, forType: .string) else {
            board.writeObjects(saved)
            Diagnostics.tools.error("Could not prepare clipboard for Plain Paste")
            NSSound.beep()
            return
        }
        let generation = board.changeCount
        key(9, .maskCommand)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard board.changeCount == generation else { return }
            board.clearContents()
            if !board.writeObjects(saved) {
                Diagnostics.tools.error("Could not restore clipboard after Plain Paste")
            }
        }
    }

    func media(_ code: Int) {
        for state in [0xA, 0xB] {
            NSEvent.otherEvent(with: .systemDefined, location: .zero,
                               modifierFlags: [], timestamp: 0, windowNumber: 0,
                               context: nil, subtype: 8, data1: (code << 16) | (state << 8),
                               data2: -1)?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    private func tile(_ tool: Tool, target: NSRunningApplication?, screen: NSScreen?) {
        guard let target, let screen, let primary = NSScreen.screens.first else {
            Diagnostics.tools.notice("Window tiling requires an active app and display")
            NSSound.beep()
            return
        }
        let app = AXUIElementCreateApplication(target.processIdentifier)
        var focused: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &focused)
        guard focusResult == .success, let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else {
            Diagnostics.tools.notice("Could not find the focused window (Accessibility result \(focusResult.rawValue))")
            NSSound.beep()
            return
        }
        let window = focused as! AXUIElement
        let frame = screen.visibleFrame
        var size = CGSize(width: tool == .maximize ? frame.width : floor(frame.width / 2), height: frame.height)
        var position = CGPoint(x: tool == .right ? frame.maxX - size.width : frame.minX,
                               y: primary.frame.maxY - frame.maxY)
        guard let point = AXValueCreate(.cgPoint, &position),
              let dimensions = AXValueCreate(.cgSize, &size) else { return }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, point)
        let result = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimensions)
        let moved = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, point)
        if result != .success || moved != .success {
            Diagnostics.tools.error("Window tiling failed (resize \(result.rawValue), move \(moved.rawValue))")
            NSSound.beep()
        }
    }

    enum ScreenshotError: Error {
        case permissionRequired, displayUnavailable, clipboardFailed
    }

    @MainActor
    func screenshot(_ screen: NSScreen?, area: CGRect?) async throws -> NSImage {
        guard CGPreflightScreenCaptureAccess() else { throw ScreenshotError.permissionRequired }
        guard let id = (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        else { throw ScreenshotError.displayUnavailable }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == id })
        else { throw ScreenshotError.displayUnavailable }
        let ownApp = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApp, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        let bounds = CGRect(origin: .zero, size: filter.contentRect.size)
        let source = area?.intersection(bounds) ?? bounds
        guard source.width >= 2, source.height >= 2, scale > 0 else { throw ScreenshotError.displayUnavailable }
        if area != nil { configuration.sourceRect = source }
        configuration.width = Int((source.width * scale).rounded())
        configuration.height = Int((source.height * scale).rounded())
        configuration.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)

        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let png = bitmap.representation(using: .png, properties: [:]),
              let tiff = bitmap.tiffRepresentation else { throw ScreenshotError.clipboardFailed }
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        item.setData(tiff, forType: .tiff)
        let clipboard = NSPasteboard.general
        clipboard.clearContents()
        guard clipboard.writeObjects([item]) else { throw ScreenshotError.clipboardFailed }
        return NSImage(cgImage: image, size: .zero)
    }

    private func record() {
        if let recorder {
            recorder.stop()
            self.recorder = nil
            NSWorkspace.shared.activateFileViewerSelecting([recorder.url])
            return
        }
        let permission = AVCaptureDevice.authorizationStatus(for: .audio)
        guard permission == .authorized else {
            Diagnostics.tools.notice("Voice Memo requires microphone permission")
            if permission == .notDetermined {
                AVCaptureDevice.requestAccess(for: .audio) { _ in }
            } else {
                let alert = NSAlert()
                alert.messageText = "Microphone access is required"
                alert.informativeText = "Allow Untill in System Settings → Privacy & Security → Microphone."
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
            }
            return
        }
        do {
            let directory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Music/Untill Voice Memos", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let timestamp = Date.now.formatted(.iso8601).replacingOccurrences(of: ":", with: "-")
            let file = directory.appendingPathComponent("Voice Memo \(timestamp).m4a")
            let audio = try AVAudioRecorder(url: file, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1
            ])
            audio.delegate = self
            if audio.record() {
                recorder = audio
            } else {
                Diagnostics.tools.error("Voice Memo could not start")
                NSSound.beep()
            }
        } catch {
            let failure = error as NSError
            Diagnostics.tools.error("Voice Memo failed (\(failure.domain, privacy: .public):\(failure.code))")
            NSSound.beep()
        }
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        self.recorder = nil
        Diagnostics.tools.error("Voice Memo encoding failed (code \((error as NSError?)?.code ?? 0))")
        NSSound.beep()
    }

    private func volumeProperty() -> (AudioObjectID, AudioObjectPropertyAddress)? {
        var device = AudioObjectID(0)
        var bytes = UInt32(MemoryLayout<AudioObjectID>.size)
        var output = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                mScope: kAudioObjectPropertyScopeGlobal,
                                                mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &output, 0, nil, &bytes, &device) == noErr,
              device != 0 else { return nil }
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                                 mScope: kAudioDevicePropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var writable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(device, &address, &writable) == noErr, writable.boolValue else { return nil }
        return (device, address)
    }

    func readVolume() -> Double? {
        guard let (device, property) = volumeProperty() else { return nil }
        var address = property
        var value: Float32 = 0
        var bytes = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &bytes, &value) == noErr else { return nil }
        return Double(value)
    }

    func setVolume(_ value: Double) {
        guard value.isFinite, let (device, property) = volumeProperty() else {
            Diagnostics.tools.notice("Volume change is unavailable")
            NSSound.beep()
            return
        }
        var address = property
        var scalar = Float32(min(1, max(0, value)))
        let result = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &scalar)
        if result != noErr {
            Diagnostics.tools.error("Could not change output volume (Core Audio result \(result))")
            NSSound.beep()
        }
    }
}
