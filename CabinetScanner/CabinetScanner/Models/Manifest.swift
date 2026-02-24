import Foundation

struct Manifest: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let createdAt: Date
    let consignmentCount: Int
    let status: ManifestStatus

    enum ManifestStatus: String, Codable {
        case active
        case complete
    }
}
