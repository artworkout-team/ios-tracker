import UIKit
import Network

public enum CheckState {
    case unchecked
    case canStart
    case cantStart
}

open class Openreplay: NSObject {
    @objc public static let shared = Openreplay()
    public let userDefaults = UserDefaults(suiteName: "io.asayer.AsayerSDK-defaults")
    public var projectKey: String?
    public var pkgVersion = "1.1.10"
    public var sessionStartTs: UInt64 = 0
    public var trackerState = CheckState.unchecked
    private var networkCheckTimer: Timer?
    public var bufferingMode = false
    public var serverURL: String {
        get { NetworkManager.shared.baseUrl }
        set { NetworkManager.shared.baseUrl = newValue }
    }
    public var options: OROptions = OROptions.defaults

    @objc open func start(projectKey: String, options: OROptions) {
        self.options = options
        self.projectKey = projectKey
        let monitor = NWPathMonitor()
        let q = DispatchQueue.global(qos: .background)
        
        monitor.start(queue: q)
        
        monitor.pathUpdateHandler = { path in
            #if targetEnvironment(simulator)
            self.trackerState = CheckState.canStart
            #else
            if path.usesInterfaceType(.wifi) {
                if PerformanceListener.shared.isActive {
                    PerformanceListener.shared.networkStateChange(1)
                }
                self.trackerState = CheckState.canStart
            } else if path.usesInterfaceType(.cellular) {
                if PerformanceListener.shared.isActive {
                    PerformanceListener.shared.networkStateChange(0)
                }
                if options.wifiOnly {
                    self.trackerState = CheckState.cantStart
                    DebugUtils.log("Connected to Cellular and options.wifiOnly is true. Openreplay will not start.")
                } else {
                    self.trackerState = CheckState.canStart
                }
            } else {
                self.trackerState = CheckState.cantStart
                DebugUtils.log("Not connected to either WiFi or Cellular. Openreplay will not start.")
            }
            #endif
        }
        
        networkCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true, block: { (_) in
            if self.trackerState == CheckState.canStart {
                self.startSession(projectKey: projectKey, options: options)
                self.networkCheckTimer?.invalidate()
            }
            if self.trackerState == CheckState.cantStart {
                self.networkCheckTimer?.invalidate()
            }
        })
    }
    
    @objc open func startSession(projectKey: String, options: OROptions) {
        self.projectKey = projectKey
        ORSessionRequest.create(doNotRecord: false) { sessionResponse in
            guard let sessionResponse = sessionResponse else { return DebugUtils.log("Openreplay: no response from /start request") }
            self.sessionStartTs = UInt64(Date().timeIntervalSince1970 * 1000)
            // let captureSettings = getCaptureSettings(fps: 3, quality: "high") // getCaptureSettings(fps: sessionResponse.fps, quality: sessionResponse.quality)
            let captureSettings = options.captureSettings
            ScreenshotManager.shared.setSettings(settings: captureSettings)
            
            MessageCollector.shared.start()
            
            if options.logs {
                LogsListener.shared.start()
            }
            
            if options.crashes {
                Crashs.shared.start()
            }
            
            if options.performances {
                PerformanceListener.shared.start()
            }
            
            if options.screen {
                ScreenshotManager.shared.start(startTs: self.sessionStartTs)
            }
            
            if options.analytics {
                Analytics.shared.start()
            }
        }
    }
    
    @objc open func coldStart(projectKey: String, options: OROptions) {
        self.options = options
        self.projectKey = projectKey
        self.bufferingMode = true
        ORSessionRequest.create(doNotRecord: true) { sessionResponse in
            guard let sessionResponse = sessionResponse else { return DebugUtils.log("Openreplay: no response from /start request") }
            self.sessionStartTs = UInt64(Date().timeIntervalSince1970 * 1000)
            ConditionsManager.shared.getConditions(projectId: sessionResponse.projectID, token: sessionResponse.token)
            // let captureSettings = getCaptureSettings(fps: sessionResponse.fps, quality: sessionResponse.quality)
            let captureSettings = options.captureSettings

            MessageCollector.shared.cycleBuffer()

            if options.logs {
                LogsListener.shared.start()
            }
            
            if options.crashes {
                Crashs.shared.start()
            }
            
            if options.performances {
                PerformanceListener.shared.start()
            }
            
            if options.screen {
                ScreenshotManager.shared.setSettings(settings: captureSettings)
                ScreenshotManager.shared.start(startTs: self.sessionStartTs)
                ScreenshotManager.shared.cycleBuffer()
            }
            
            if options.analytics {
                Analytics.shared.start()
            }
        }
    }
    
    @objc open func triggerRecording(condition: String?) {
        self.bufferingMode = false
        ORSessionRequest.create(doNotRecord: false) { sessionResponse in
            guard let sessionResponse = sessionResponse else { return DebugUtils.log("Openreplay: no response from /start request") }
            
            // sending buffered messages and images - should not be bigger than 30sec buffer,
            // so the performance impact is minimal (as long as fps was lower than 10)
            MessageCollector.shared.syncBuffers()
            ScreenshotManager.shared.syncBuffers()
            
            MessageCollector.shared.start()
        }
    }
    
    @objc open func stop() {
        MessageCollector.shared.stop()
        ScreenshotManager.shared.stop()
        Crashs.shared.stop()
        PerformanceListener.shared.stop()
        Analytics.shared.stop()
    }
    
    @objc open func addIgnoredView(_ view: UIView) {
        ScreenshotManager.shared.addSanitizedElement(view)
    }
    
    @objc open func removeIgnoredView(_ view: UIView) {
        ScreenshotManager.shared.removeSanitizedElement(view)
    }
    
    @objc open func setBlurMode(_ isActive: Bool) {
        ScreenshotManager.shared.setBlurMode(isActive)
    }
    
    @objc open func setBlurRadius(_ radius: Double) {
        ScreenshotManager.shared.setBlurRadius(radius)
    }
    
    @objc open func setDrawHierarchyHandler(_ handler: @escaping (Bool) -> Void) {
        ScreenshotManager.shared.setDrawHierarchyHandler(handler)
    }
    
    @objc open func setMetadata(key: String, value: String) {
        let message = ORMobileMetadata(key: key, value: value)
        MessageCollector.shared.sendMessage(message)
    }

    @objc open func event(name: String, object: NSObject?) {
        event(name: name, payload: object as? Encodable)
    }
    
    open func event(name: String, payload: [String: Any]?) {
        var json = ""
        if let payload = payload,
           let data = try? JSONSerialization.data(withJSONObject: payload),
           let jsonStr = String(data: data, encoding: .utf8) {
            json = jsonStr
        }
        let message = ORMobileEvent(name: name, payload: json)
        MessageCollector.shared.sendMessage(message)
    }

    open func event(name: String, payload: Encodable?) {
        var json = ""
        if let payload = payload,
           let data = payload.toJSONData(),
           let jsonStr = String(data: data, encoding: .utf8) {
            json = jsonStr
        }
        let message = ORMobileEvent(name: name, payload: json)
        MessageCollector.shared.sendMessage(message)
    }
    
    open func eventStr(name: String, payload: String?) {
        let message = ORMobileEvent(name: name, payload: payload ?? "")
        MessageCollector.shared.sendMessage(message)
    }

    @objc open func setUserID(_ userID: String) {
        let message = ORMobileUserID(iD: userID)
        MessageCollector.shared.sendMessage(message)
    }

    @objc open func userAnonymousID(_ userID: String) {
        let message = ORMobileUserAnonymousID(iD: userID)
        MessageCollector.shared.sendMessage(message)
    }
    
    @objc open func networkRequest(url: String, method: String, requestJSON: String, responseJSON: String, status: Int, duration: UInt64) {
        sendNetworkMessage(url: url, method: method, requestJSON: requestJSON, responseJSON: responseJSON, status: status, duration: duration)
    }
}



func getCaptureSettings(fps: Int, quality: String) -> (captureRate: Double, imgCompression: Double) {
    let limitedFPS = min(max(fps, 1), 99)
    let captureRate = 1.0 / Double(limitedFPS)
    
    var imgCompression: Double
    switch quality.lowercased() {
    case "low":
        imgCompression = 0.4
    case "standard":
        imgCompression = 0.5
    case "high":
        imgCompression = 0.6
    default:
        imgCompression = 0.5  // default to standard if quality string is not recognized
    }
    
    return (captureRate: captureRate, imgCompression: imgCompression)
}
