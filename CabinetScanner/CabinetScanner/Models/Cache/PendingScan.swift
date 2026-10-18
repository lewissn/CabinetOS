import Foundation
import SwiftData

/// A locally-recorded BJS panel scan awaiting sync to the server. The scanner
/// hot path writes one of these per scan; the ScanQueueService drains them in
/// batches via `POST /scan-batch`.
@Model
final class PendingScan {
    /// Stable client-generated id sent to the server as `localId` so the
    /// per-scan response can be matched back. Persisted as a String to keep
    /// SwiftData migrations simple.
    @Attribute(.unique) var localId: String

    var boxId: String
    var manifestId: String
    var consignmentId: String
    var projectName: String
    var cabinetName: String
    var partNumber: String
    var panelUid: String

    var scannedAt: Date
    var deviceId: String
    var stationId: String
    var operatorName: String?

    /// Raw status — SwiftData enum support is fine but raw strings keep the
    /// store backwards-compatible across schema versions.
    var statusRaw: String

    var errorCode: String?
    var errorMessage: String?
    var alreadyPackedInBoxId: String?

    var retryCount: Int
    var lastAttemptAt: Date?
    var createdAt: Date

    /// Server-assigned id once successfully inserted, copied here so the UI can
    /// potentially deep-link to the panel row.
    var serverBoxItemId: String?

    init(
        localId: UUID = UUID(),
        boxId: String,
        manifestId: String,
        consignmentId: String,
        projectName: String,
        cabinetName: String,
        partNumber: String,
        scannedAt: Date,
        deviceId: String,
        stationId: String,
        operatorName: String?,
        status: PendingScanStatus = .pending
    ) {
        self.localId = localId.uuidString
        self.boxId = boxId
        self.manifestId = manifestId
        self.consignmentId = consignmentId
        self.projectName = projectName
        self.cabinetName = cabinetName
        self.partNumber = partNumber
        self.panelUid = "\(projectName)|\(cabinetName)|\(partNumber)"
        self.scannedAt = scannedAt
        self.deviceId = deviceId
        self.stationId = stationId
        self.operatorName = operatorName
        self.statusRaw = status.rawValue
        self.errorCode = nil
        self.errorMessage = nil
        self.alreadyPackedInBoxId = nil
        self.retryCount = 0
        self.lastAttemptAt = nil
        self.createdAt = .now
        self.serverBoxItemId = nil
    }

    var status: PendingScanStatus {
        get { PendingScanStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }
}

enum PendingScanStatus: String, Codable {
    case pending
    case syncing
    case synced
    case conflict   // server says already packed in another box — needs user resolution
    case rejected   // batch was rejected (box closed, etc.) — needs user resolution
}
