import SwiftUI

final class AppState: ObservableObject {
    @Published var isStationConfigured: Bool
    @Published var deviceId: String
    @Published var stationId: String
    @Published var operatorName: String

    init() {
        let defaults = UserDefaults.standard

        if let stored = defaults.string(forKey: "deviceId") {
            self.deviceId = stored
        } else {
            let newId = UUID().uuidString
            defaults.set(newId, forKey: "deviceId")
            self.deviceId = newId
        }

        self.stationId = defaults.string(forKey: "stationId") ?? "packaging"
        self.operatorName = defaults.string(forKey: "operatorName") ?? ""
        self.isStationConfigured = defaults.bool(forKey: "isStationConfigured")
    }

    func saveStation(stationId: String, operatorName: String) {
        let defaults = UserDefaults.standard
        self.stationId = stationId
        self.operatorName = operatorName
        self.isStationConfigured = true
        defaults.set(stationId, forKey: "stationId")
        defaults.set(operatorName, forKey: "operatorName")
        defaults.set(true, forKey: "isStationConfigured")
    }
}
