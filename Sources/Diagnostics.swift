import OSLog

enum Diagnostics {
    static let lifecycle = Logger(subsystem: "com.untill.radial", category: "lifecycle")
    static let input = Logger(subsystem: "com.untill.radial", category: "input")
    static let capture = Logger(subsystem: "com.untill.radial", category: "capture")
    static let tools = Logger(subsystem: "com.untill.radial", category: "tools")
}
