import AppKit
import SwiftUI

enum Radial {
    static let step = Double.pi / 4
    static let diameter = 376.0
    static let clickRadius = diameter / 2
    static let radius = 133.0
    static let dead = 30.0
    static let push = 174.0
    static let numbers: [Int64] = [18, 19, 20, 21, 23, 22, 26, 28]

    static func sector(x: Double, y: Double) -> Int? {
        guard hypot(x, y) >= dead else { return nil }
        return (Int(floor((atan2(x, y) + step / 2) / step)) + 8) % 8
    }

    static func volume(from initial: Double, projection: Double, anchor: Double) -> Double {
        min(1, max(0, initial + (projection - anchor) / 120))
    }
}

final class MenuState: ObservableObject {
    @Published var ring = 0
    @Published var selected: Int?
    @Published var visible = false
    @Published var volume: Double?
    @Published var tools: [Tool] = []
    @Published var disabled: Set<Tool> = []
    @Published var recording = false
    @Published var look: WheelLook = .glass
}

struct Wheel: View {
    @ObservedObject var state: MenuState
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var systemScheme

    private var scheme: ColorScheme {
        switch state.look {
        case .glass: systemScheme
        case .graphite: .dark
        case .paper: .light
        }
    }

    private var surface: AnyShapeStyle {
        switch state.look {
        case .glass: AnyShapeStyle(.regularMaterial)
        case .graphite: AnyShapeStyle(Color(red: 0.13, green: 0.15, blue: 0.18))
        case .paper: AnyShapeStyle(Color(red: 0.97, green: 0.94, blue: 0.87))
        }
    }

    var body: some View {
        ZStack {
            Circle().fill(surface)
            Circle().strokeBorder(.primary.opacity(0.16), lineWidth: 1)
            Circle().strokeBorder(.primary.opacity(0.11), lineWidth: 1)
                .frame(width: 338, height: 338)
            ForEach(Array(state.tools.enumerated()), id: \.offset) { slot, tool in
                tile(slot, tool)
                    .offset(x: sin(Double(slot) * Radial.step) * Radial.radius,
                            y: -cos(Double(slot) * Radial.step) * Radial.radius)
            }
            center
        }
        .frame(width: Radial.diameter, height: Radial.diameter)
        .environment(\.colorScheme, scheme)
        .shadow(color: .black.opacity(0.28), radius: 13, y: 5)
        .scaleEffect(state.visible || reduceMotion ? 1 : 0.91)
        .opacity(state.visible ? 1 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: state.visible)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: state.selected)
        .frame(width: size, height: size)
    }

    func tile(_ slot: Int, _ tool: Tool) -> some View {
        let active = state.selected == slot
        let disabled = state.disabled.contains(tool)
        return VStack(spacing: 4) {
            Image(systemName: tool == .record && state.recording ? "stop.circle.fill" : tool.icon)
                .font(.system(size: 19, weight: .medium))
            Text(tool == .record && state.recording ? "Stop memo" : tool.title)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
            Text("\(slot + 1)")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .opacity(0.68)
        }
        .frame(width: 86, height: 64)
        .foregroundStyle(active ? Color.white : Color.primary)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(active ? Color.blue : Color.primary.opacity(0.09))
        }
        .opacity(disabled ? 0.30 : 1)
    }

    var center: some View {
        VStack(spacing: 6) {
            if let volume = state.volume {
                Image(systemName: "speaker.wave.2")
                Text(volume, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 19, weight: .semibold, design: .monospaced))
                ProgressView(value: volume).frame(width: 64)
            } else {
                Text(state.ring == 0 ? "Ring 1" : "Ring 2")
                    .font(.system(size: 16, weight: .semibold))
                HStack(spacing: 5) {
                    ForEach(0..<2) { index in
                        Capsule().fill(index == state.ring ? Color.accentColor : Color.secondary.opacity(0.35))
                            .frame(width: index == state.ring ? 13 : 5, height: 5)
                    }
                }
                Text("Tab or scroll")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 112, height: 112)
        .background(.thinMaterial, in: Circle())
        .overlay(Circle().strokeBorder(.primary.opacity(0.13), lineWidth: 1))
    }
}

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(state: MenuState, size: CGFloat) {
        super.init(contentRect: .init(x: 0, y: 0, width: size, height: size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        if #available(macOS 13.0, *) { collectionBehavior.insert(.canJoinAllApplications) }
        contentView = NSHostingView(rootView: Wheel(state: state, size: size))
    }
}
