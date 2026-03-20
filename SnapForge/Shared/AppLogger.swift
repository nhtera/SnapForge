import os

/// Centralized loggers for SnapForge subsystems.
/// Uses os.Logger for structured logging that can be filtered in Console.app
/// and is automatically stripped from production builds at debug level.
enum AppLogger {
    static let capture = Logger(subsystem: "com.snapforge.app", category: "Capture")
    static let recording = Logger(subsystem: "com.snapforge.app", category: "Recording")
    static let annotation = Logger(subsystem: "com.snapforge.app", category: "Annotation")
    static let export = Logger(subsystem: "com.snapforge.app", category: "Export")
    static let storage = Logger(subsystem: "com.snapforge.app", category: "Storage")
    static let hotkey = Logger(subsystem: "com.snapforge.app", category: "Hotkey")
    static let scroll = Logger(subsystem: "com.snapforge.app", category: "ScrollCapture")
    static let video = Logger(subsystem: "com.snapforge.app", category: "VideoEditor")
    static let general = Logger(subsystem: "com.snapforge.app", category: "General")
}
