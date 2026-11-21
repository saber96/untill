import AppKit
import ApplicationServices

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
    checks += 1
}

for slot in 0..<8 {
    let angle = Double(slot) * Radial.step
    for offset in [-0.38, 0, 0.38] {
        check(Radial.sector(x: 100 * sin(angle + offset), y: 100 * cos(angle + offset)) == slot,
              "radial sector \(slot) at offset \(offset)")
    }
}
check(Radial.sector(x: 0, y: 0) == nil, "center is neutral")
check(Radial.sector(x: 29, y: 0) == nil, "point inside dead zone")
check(Radial.sector(x: 30, y: 0) == 2, "point on dead zone edge")
check(Radial.volume(from: 0.5, projection: 0, anchor: 200) == 0, "slider minimum")
check(Radial.volume(from: 0.5, projection: 400, anchor: 200) == 1, "slider maximum")
check(Radial.volume(from: 0.5, projection: 230, anchor: 200) == 0.75, "slider movement")

let display = CGRect(x: 0, y: 0, width: 1024, height: 768)
func area(_ start: CGPoint, _ end: CGPoint) -> CGRect? {
    AreaSelectionView.captureRect(from: start, to: end, in: display)
}
let start = CGPoint(x: 15, y: 70)
let end = CGPoint(x: 95, y: 120)
let expected = CGRect(x: 15, y: 70, width: 80, height: 50)
check(area(start, end) == expected, "area capture bounds")
check(area(end, start) == expected, "reverse drag")
check(area(start, start) == nil, "single click cannot take a screenshot")
check(area(CGPoint(x: 1.1, y: 1.1), CGPoint(x: 2.9, y: 2.9)) == nil, "fractional tiny drags stay invalid")
check(area(start, CGPoint(x: 15, y: 160)) == nil, "vertical line cannot take a screenshot")
check(area(CGPoint(x: -20, y: -10), CGPoint(x: 2000, y: 2000)) == display, "drag clipped on both sides")
check(area(CGPoint(x: -20, y: 20), CGPoint(x: -5, y: 40)) == nil, "off-display drag")

let suite = "com.untill.tests.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
defaults.set(["paste", "copy", "paste", "unknown"], forKey: "order")
defaults.set(["cut", "unknown"], forKey: "disabled")
defaults.set(8, forKey: "mouse")
defaults.set("unknown", forKey: "wheelLook")
defaults.set("unknown", forKey: "screenshotMode")
defaults.set(try JSONEncoder().encode(BindingKey(code: 49, flags: 0, label: "Space")), forKey: "shortcut")
let preferences = Preferences(defaults: defaults)
check(Array(preferences.order.prefix(2)) == [.paste, .copy], "valid saved ordering survives")
check(preferences.order.count == Tool.allCases.count, "tools deduplicated and catalog items added")
check(Set(preferences.order) == Set(Tool.allCases), "every tool is selectable")
check(preferences.disabled == [.cut], "invalid disabled-tool values ignored")
check(preferences.mouse == 0, "invalid mouse trigger fallback")
check(preferences.screenshotMode == .area, "area capture fallback")
check(preferences.look == .glass, "invalid appearance fallback")
check(preferences.shortcut == .initial, "invalid shortcut fallback")
preferences.capture(code: 0, flags: [], characters: "a")
check(preferences.shortcut == .initial && preferences.shortcutError != nil, "unmodified shortcut rejected visibly")
preferences.capture(code: 0, flags: .maskAlternate, characters: "\u{0001}")
check(preferences.shortcut == .initial && preferences.shortcutError != nil, "control character rejected visibly")
preferences.capture(code: 53, flags: [], characters: nil)
check(preferences.shortcut == .initial && preferences.shortcutError == nil, "Esc cancels shortcut capture")
preferences.capture(code: 49, flags: [.maskControl, .maskAlternate, .maskAlphaShift], characters: nil)
check(preferences.shortcut.label == "⌃⌥Space", "valid shortcut strips irrelevant flags")
preferences.look = .paper
preferences.screenshotMode = .display
preferences.mouse = 3
preferences.order.swapAt(0, preferences.order.firstIndex(of: .screenshotArea)!)
let reloaded = Preferences(defaults: defaults)
check(reloaded.shortcut == preferences.shortcut, "shortcut persisted")
check(reloaded.look == .paper && reloaded.screenshotMode == .display && reloaded.mouse == 3, "control preferences persisted")
check(reloaded.order.first == .screenshotArea, "tool swapped into visible slot and persisted")
preferences.resetShortcut()
check(preferences.shortcut == .initial, "reset restores Option–Space")

check(!UtilityModel.hasText(" \t\n"), "blank notes and prompts rejected")
check(UtilityModel.hasText(" \nhello "), "nonblank text accepted")
let model = UtilityModel()
let now = Date(timeIntervalSince1970: 1000)
check(!model.copy(" \t"), "blank copy is rejected before clipboard access")
for duration in [Int.min, 0, 181, Int.max] {
    model.minutes = duration
    model.startTimer(at: now)
}
check(model.timers.isEmpty, "invalid timer durations do not create timers")
model.minutes = 1
model.startTimer(at: now)
model.minutes = 180
model.startTimer(at: now)
check(model.timers.count == 2, "minimum and maximum timer durations accepted")
check(model.tick(clipboardVisible: false, at: now.addingTimeInterval(59)) == nil, "timer does not expire early")
check(model.tick(clipboardVisible: false, at: now.addingTimeInterval(60)) == "Your 1-minute timer finished.",
      "timer completes at deadline")
check(model.tick(clipboardVisible: false, at: now.addingTimeInterval(61)) == nil, "timer completes only once")
model.cancelTimer(model.timers[0].id)
check(model.timers.isEmpty, "cancel removes timer")

print("Passed \(checks) checks")
