import UIKit
import DeviceKit

class ORSessionRequest: NSObject {
    private static var params = [String: AnyHashable]()

    static func create(doNotRecord: Bool,  completion: @escaping (ORSessionResponse?) -> Void) {
        guard let projectKey = Openreplay.shared.projectKey else { return DebugUtils.log("Openreplay: no project key added") }
//         #warning("Can interfere with client usage")
        UIDevice.current.isBatteryMonitoringEnabled = true
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()

        let performances: [String: UInt64] = [
            "physicalMemory": UInt64(ProcessInfo.processInfo.physicalMemory),
            "processorCount": UInt64(ProcessInfo.processInfo.processorCount),
            "activeProcessorCount": UInt64(ProcessInfo.processInfo.activeProcessorCount),
            "systemUptime": UInt64(ProcessInfo.processInfo.systemUptime),
            "isLowPowerModeEnabled": UInt64(ProcessInfo.processInfo.isLowPowerModeEnabled ? 1 : 0),
            "thermalState": UInt64(ProcessInfo.processInfo.thermalState.rawValue),
            "batteryLevel": UInt64(max(0.0, UIDevice.current.batteryLevel)*100),
            "batteryState": UInt64(UIDevice.current.batteryState.rawValue),
            "orientation": UInt64(UIDevice.current.orientation.rawValue),
        ]
        
        let device = Device.current
        var deviceModel = ""
        var deviceSafeName = ""
        
        if device.isSimulator {
            deviceSafeName = "iPhone 14 Pro"
            deviceModel = "iPhone14,8"
        } else {
            deviceSafeName = device.safeDescription
            deviceModel = Device.identifier
        }

        DebugUtils.log(">>>> device \(device) type \(device.safeDescription) mem \(UInt64(ProcessInfo.processInfo.physicalMemory / 1024))")
        params = [
            "doNotRecord": doNotRecord,
            "projectKey": projectKey,
            "trackerVersion": Openreplay.shared.pkgVersion,
            "revID": Bundle(for: Openreplay.shared.classForCoder).object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "N/A",
            "userUUID": ORUserDefaults.shared.userUUID,
            "userOSVersion": UIDevice.current.systemVersion,
            "userDevice": "Unknown",
            "userDeviceType": "tablet",
            "timestamp": UInt64(Date().timeIntervalSince1970 * 1000),
            "performances": performances,
            "deviceMemory": UInt64(ProcessInfo.processInfo.physicalMemory / 1024),
            "timezone": getTimezone(),
            "width": UInt64(UIScreen.main.bounds.width),
            "height": UInt64(UIScreen.main.bounds.height),
            "platform": "Android"
        ]
        callAPI(completion: completion)
    }

    private static func callAPI(completion: @escaping (ORSessionResponse?) -> Void) {
        guard !params.isEmpty else { return }
        NetworkManager.shared.createSession(params: params) { (sessionResponse) in
            guard let sessionResponse = sessionResponse else {
                DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                    callAPI(completion: completion)
                }
                return
            }
            DebugUtils.log(">>>> Starting session : \(sessionResponse.sessionID)")
            return completion(sessionResponse)
        }
    }
}

struct ORSessionResponse: Decodable {
    let userUUID: String
    let token: String
    let imagesHashList: [String]?
    let sessionID: String
    let fps: Int
    let quality: String
    let projectID: String
}

extension ORSessionResponse {
    enum CodingKeys: CodingKey {
        case userUUID
        case token
        case imagesHashList
        case sessionID
        case fps
        case quality
        case projectID
    }
    
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.userUUID = try container.decode(String.self, forKey: .userUUID)
        self.token = try container.decode(String.self, forKey: .token)
        self.imagesHashList = try container.decodeIfPresent([String].self, forKey: .imagesHashList)
        self.sessionID = try container.decode(String.self, forKey: .sessionID)
        self.fps = try container.decode(Int.self, forKey: .fps)
        self.quality = try container.decode(String.self, forKey: .quality)
        self.projectID = try container.decodeIfPresent(String.self, forKey: .projectID) ?? "FIcMkYwRybXQtQG5Zu8L"
    }
}

func getTimezone() -> String {
    let offset = TimeZone.current.secondsFromGMT()
    let sign = offset >= 0 ? "+" : "-"
    let hours = abs(offset) / 3600
    let minutes = (abs(offset) % 3600) / 60
    return String(format: "UTC%@%02d:%02d", sign, hours, minutes)
}
