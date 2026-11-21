import AppKit

final class AreaPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class AreaSelectionView: NSView {
    private var start: CGPoint?
    private var selection = CGRect.zero
    private let complete: (CGRect?) -> Void

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(frame: NSRect, complete: @escaping (CGRect?) -> Void) {
        self.complete = complete
        super.init(frame: frame)
        autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func draw(_ dirtyRect: NSRect) {
        let shade = NSBezierPath(rect: bounds)
        shade.appendRect(selection)
        shade.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.33).setFill()
        shade.fill()
        if selection.isEmpty {
            let hint = "Drag to capture an area   ·   Esc to cancel" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: NSColor.white
            ]
            let size = hint.size(withAttributes: attributes)
            let box = NSRect(x: bounds.midX - size.width / 2 - 12, y: 54, width: size.width + 24, height: size.height + 16)
            NSColor.black.withAlphaComponent(0.75).setFill()
            NSBezierPath(roundedRect: box, xRadius: 9, yRadius: 9).fill()
            hint.draw(at: NSPoint(x: box.minX + 12, y: box.minY + 8), withAttributes: attributes)
        } else {
            NSColor.white.setStroke()
            NSBezierPath(rect: selection).stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        selection = .zero
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) { updateSelection(event) }

    override func mouseUp(with event: NSEvent) {
        updateSelection(event)
        start = nil
        guard selection.width >= 2, selection.height >= 2 else {
            selection = .zero
            needsDisplay = true
            return
        }
        complete(selection)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { complete(nil) }
        else { super.keyDown(with: event) }
    }

    override func cancelOperation(_ sender: Any?) { complete(nil) }
    override func rightMouseDown(with event: NSEvent) { complete(nil) }

    static func captureRect(from start: CGPoint, to end: CGPoint, in bounds: CGRect) -> CGRect? {
        let drag = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                          width: abs(start.x - end.x), height: abs(start.y - end.y))
        let clipped = drag.intersection(bounds)
        guard !clipped.isNull, clipped.width >= 2, clipped.height >= 2 else { return nil }
        return clipped.integral.intersection(bounds)
    }

    private func updateSelection(_ event: NSEvent) {
        guard let start else { return }
        let end = convert(event.locationInWindow, from: nil)
        selection = Self.captureRect(from: start, to: end, in: bounds) ?? .zero
        needsDisplay = true
    }
}
