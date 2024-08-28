import Foundation

@objc public enum RecordingQuality: Int {
    case Low
    case Standard
    case High
}

open class OROptions: NSObject {
    let crashes: Bool
    let analytics: Bool
    let performances: Bool
    let logs: Bool
    let screen: Bool
    let wifiOnly: Bool
    let debugLogs: Bool
    let debugImages: Bool
    var captureSettings: (captureRate: Double, imgCompression: Double) = (captureRate: 0.33, imgCompression: 0.5)
    
    public static let defaults = OROptions(crashes: true, analytics: true, performances: true, logs: true, screen: true, wifiOnly: true, debugLogs: false, debugImages: false)
    public static let defaultDebug = OROptions(crashes: true, analytics: true, performances: true, logs: true, screen: true, wifiOnly: true, debugLogs: true, debugImages: false)

    @objc public init(crashes: Bool, analytics: Bool, performances: Bool, logs: Bool, screen: Bool, wifiOnly: Bool, debugLogs: Bool, debugImages: Bool) {
        self.crashes = crashes
        self.analytics = analytics
        self.performances = performances
        self.logs = logs
        self.screen = screen
        self.wifiOnly = wifiOnly
        self.debugLogs = debugLogs
        self.debugImages = debugImages
    }
}
