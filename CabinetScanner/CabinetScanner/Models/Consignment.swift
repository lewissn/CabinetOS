import Foundation

struct Consignment: Identifiable, Codable, Hashable {
    let id: String
    let manifestId: String

    /// The primary job key — matches `source_name` in packing_panel_registry
    /// and `job_identifier` in the Ops consignment table.
    /// This is also what the QR code's projectName must equal for a scan to validate.
    /// Example value: "Lewis Nichols - 29248"  (derived from CSV filename on manifest upload)
    let jobIdentifier: String

    /// Human-readable customer name for display (may differ from jobIdentifier)
    let customerName: String

    let expectedItemCount: Int
    let packedItemCount: Int
    let status: ConsignmentStatus

    enum ConsignmentStatus: String, Codable {
        case open
        case complete
    }

    /// Display title shown in the consignment list
    var displayTitle: String {
        // If customerName is the same as jobIdentifier (common case), show it once
        if customerName.isEmpty || customerName == jobIdentifier {
            return jobIdentifier
        }
        return "\(customerName) — \(jobIdentifier)"
    }
}
