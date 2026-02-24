import Foundation

// MARK: - Mock Data
// jobIdentifier mirrors the Ops system's source_name / job_identifier convention.
// source_name is derived from the manifest CSV filename (without extension).
// Example: CSV "Lewis Nichols - 29248.csv" → source_name = "Lewis Nichols - 29248"
// The QR code on every label in that job will contain exactly this string.

enum MockData {
    static let manifests: [Manifest] = [
        Manifest(
            id: "manifest-001",
            name: "Week 8 — Production Run",
            createdAt: ISO8601DateFormatter().date(from: "2026-02-20T09:00:00Z")!,
            consignmentCount: 3,
            status: .active
        ),
        Manifest(
            id: "manifest-002",
            name: "Week 7 — Production Run",
            createdAt: ISO8601DateFormatter().date(from: "2026-02-13T09:00:00Z")!,
            consignmentCount: 2,
            status: .active
        ),
    ]

    static let consignments: [String: [Consignment]] = [
        "manifest-001": [
            Consignment(
                id: "cons-001",
                manifestId: "manifest-001",
                // jobIdentifier = source_name = QR code value = CSV filename without extension
                jobIdentifier: "Lewis Nichols - 29248",
                customerName: "Lewis Nichols",
                expectedItemCount: 24,
                packedItemCount: 0,
                status: .open
            ),
            Consignment(
                id: "cons-002",
                manifestId: "manifest-001",
                jobIdentifier: "Sarah Mitchell - 29249",
                customerName: "Sarah Mitchell",
                expectedItemCount: 16,
                packedItemCount: 0,
                status: .open
            ),
            Consignment(
                id: "cons-003",
                manifestId: "manifest-001",
                jobIdentifier: "James Cooper - 29250",
                customerName: "James Cooper",
                expectedItemCount: 32,
                packedItemCount: 0,
                status: .open
            ),
        ],
        "manifest-002": [
            Consignment(
                id: "cons-004",
                manifestId: "manifest-002",
                jobIdentifier: "Emily Watson - 29240",
                customerName: "Emily Watson",
                expectedItemCount: 20,
                packedItemCount: 20,
                status: .complete
            ),
            Consignment(
                id: "cons-005",
                manifestId: "manifest-002",
                jobIdentifier: "David Brown - 29241",
                customerName: "David Brown",
                expectedItemCount: 12,
                packedItemCount: 8,
                status: .open
            ),
        ],
    ]

    // MARK: - Mock packing_panel_registry equivalent
    // In production, this comes from the Ops packing_panel_registry table.
    // Panel UID format (Ops system): "{source_name}|{cabinet_name}|{part_number}"
    // Part numbers are always 1–2 digit numeric strings.
    // Cabinet names are always alphanumeric (never purely numeric).

    static func registryItems(for consignmentId: String) -> [FinishConsignmentResponse.MissingItem] {
        switch consignmentId {
        case "cons-001":
            // 6 cabinets × 4 parts = 24 items for "Lewis Nichols - 29248"
            var items: [FinishConsignmentResponse.MissingItem] = []
            let cabinets = ["LDC", "UDC", "BC1", "TC1", "WC1", "SC1"]
            for cab in cabinets {
                for part in 1...4 {
                    items.append(FinishConsignmentResponse.MissingItem(
                        id: nil,
                        projectName: "Lewis Nichols - 29248", // = source_name = jobIdentifier
                        cabinetName: cab,
                        partNumber: "\(part)"
                    ))
                }
            }
            return items
        case "cons-002":
            // 4 cabinets × 4 parts = 16 items for "Sarah Mitchell - 29249"
            var items: [FinishConsignmentResponse.MissingItem] = []
            let cabinets = ["LDC", "UDC", "BC1", "TC1"]
            for cab in cabinets {
                for part in 1...4 {
                    items.append(FinishConsignmentResponse.MissingItem(
                        id: nil,
                        projectName: "Sarah Mitchell - 29249",
                        cabinetName: cab,
                        partNumber: "\(part)"
                    ))
                }
            }
            return items
        default:
            return []
        }
    }
}
