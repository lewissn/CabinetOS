import Foundation

// MARK: - Job Index Models
//
// Mirrors the Ops API's /api/job-index and /api/search responses.
//
// Almost every field is optional on purpose. A job's record is assembled from
// whichever feeds have reached it — a CSV export, a webhook, a Sales Order
// lookup — so absence is the normal case, not an error. Views hide what is
// missing rather than showing empty rows.

// MARK: - Provenance

/// Where a record's information came from, and therefore how far to trust it.
enum JobDataSource: String, Codable, CaseIterable {
    /// A ShopVOX response received recently. The only source that may be
    /// presented as a confirmed ShopVOX status.
    case live
    /// Assembled from a Sales Order — order facts, not job facts.
    case derived
    /// From a Jobs-view CSV export. True as at the export, not now.
    case imported
    /// Produced by this app: scanning, packing. Ours, and authoritative.
    case local
    /// Assembled from a manifest with no ShopVOX confirmation at all.
    case inferred

    /// Unknown values decode as `.inferred` — the weakest reading — so a new
    /// server-side source can never be shown as more trustworthy than it is.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = JobDataSource(rawValue: raw) ?? .inferred
    }

    var label: String {
        switch self {
        case .live:     return "Live from ShopVOX"
        case .derived:  return "From Sales Order"
        case .imported: return "From export"
        case .local:    return "Tracked here"
        case .inferred: return "Not confirmed"
        }
    }

    /// Short form for a badge, where the long label will not fit.
    var shortLabel: String {
        switch self {
        case .live:     return "Live"
        case .derived:  return "Order"
        case .imported: return "Export"
        case .local:    return "Ours"
        case .inferred: return "Unconfirmed"
        }
    }
}

// MARK: - Search

struct JobSearchResponse: Decodable {
    let ok: Bool
    let query: String
    let results: [JobSearchResult]
    let customers: [ShopVoxCustomer]?
    let customerLookupFailed: Bool?
    let interpretedAs: QueryInterpretation?
}

/// How the server read the query. Surfaced so a search that returns nothing
/// can explain what it looked for rather than just saying "no results".
struct QueryInterpretation: Decodable {
    let numeric: String?
    let postcode: String?
    let normalised: String?
}

struct JobSearchResult: Decodable, Identifiable, Hashable {
    let id: String
    let jobNumber: String?
    let salesOrderNumber: String?
    let shopifyOrderNumber: String?
    let customerPo: String?
    let customerName: String?
    let customerPostcode: String?
    let jobTitle: String?
    let shipToCity: String?
    let orderDueDate: String?

    let dataSource: JobDataSource
    let isStale: Bool
    let sourceCapturedAt: String?

    /// Which field produced the match, so the row can show why it appeared.
    let matchField: String?
    let matchKind: String?

    static func == (a: JobSearchResult, b: JobSearchResult) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// The strongest reference we can put in front of a person, preferring the
    /// number they are most likely to be holding.
    var primaryReference: String? {
        if let so = salesOrderNumber { return "SO \(so)" }
        if let jb = jobNumber { return "JB \(jb)" }
        if let shopify = shopifyOrderNumber { return "#\(shopify)" }
        return nil
    }

    var displayTitle: String {
        customerName ?? jobTitle ?? primaryReference ?? "Untitled job"
    }
}

struct ShopVoxCustomer: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let email: String?
    let phone: String?
    let city: String?
}

// MARK: - Detail

struct JobDetail: Decodable {
    let ok: Bool
    let id: String
    /// The stable in-app route for this job — the one a QR code will encode.
    let path: String?

    let references: JobReferences
    let customer: JobCustomer
    let dates: JobDates
    let logistics: JobLogistics
    let production: JobProduction

    let instructions: JobInstructions?
    let lineItems: [JobLineItem]?

    let team: JobTeam?
    let proof: JobProof?

    let steps: [JobStep]
    let aliases: [JobAlias]
    let provenance: JobProvenance

    let workflowCapabilities: WorkflowCapabilities?

    let shopvoxUrl: String?
    let canOpenInShopvox: Bool
}

/// The written instructions on a job. Every field is null on most jobs in this
/// account, so the view renders nothing at all rather than empty headings.
struct JobInstructions: Decodable {
    let description: String?
    let productionDetails: String?
    let designDetails: String?
    let shippingDetails: String?
    let bomDetails: String?
    let installDetails: String?

    var isEmpty: Bool {
        sections.isEmpty
    }

    /// Populated sections only, in the order they matter on the floor.
    var sections: [(title: String, text: String)] {
        var out: [(String, String)] = []
        if let t = productionDetails { out.append(("Production notes", t)) }
        if let t = shippingDetails { out.append(("Shipping notes", t)) }
        if let t = bomDetails { out.append(("Materials", t)) }
        if let t = designDetails { out.append(("Design notes", t)) }
        if let t = installDetails { out.append(("Install notes", t)) }
        if let t = description { out.append(("Specification", t)) }
        return out
    }
}

struct JobLineItem: Decodable, Identifiable, Hashable {
    let id: String?
    let lineNumber: Int?
    let name: String?
    let description: String?
    let quantity: String?
    let unit: String?
    let workflowState: String?

    /// Identifiable needs something stable even when ShopVOX sent no id.
    var stableId: String { id ?? "\(lineNumber ?? 0)-\(name ?? "item")" }

    var displayName: String { name ?? "Item" }

    var quantityLabel: String? {
        guard let quantity else { return nil }
        if let unit, !unit.isEmpty, unit.lowercased() != "each" {
            return "\(quantity) \(unit)"
        }
        return "× \(quantity)"
    }
}

/// What the app may do to this job's workflow, and what it may not. Sent by
/// the server so a limitation is explained rather than met as an error.
struct WorkflowCapabilities: Decodable {
    let canStartAndComplete: Bool
    let canReopenCompletedStep: Bool
    let canAssign: Bool
    let note: String?
}

struct JobReferences: Decodable {
    let jobNumber: String?
    let salesOrderNumber: String?
    let projectNumber: String?
    let shopifyOrderNumber: String?
    let customerPo: String?
    let shopvoxJobId: String?

    /// Whether this section has anything worth rendering.
    var isEmpty: Bool {
        jobNumber == nil && salesOrderNumber == nil && projectNumber == nil
            && shopifyOrderNumber == nil && customerPo == nil
    }
}

struct JobCustomer: Decodable {
    let name: String?
    let postcode: String?
    let contactName: String?
    let contactEmail: String?

    var isEmpty: Bool {
        name == nil && postcode == nil && contactName == nil && contactEmail == nil
    }
}

struct JobDates: Decodable {
    /// When this job leaves. ShopVOX's `dueDate`, which is the field the
    /// office actually moves and the one despatch alerts watch.
    let despatchDate: String?
    /// Which ShopVOX field that came from, shown so the app never implies a
    /// precision it does not have.
    let despatchDateSource: String?
    /// When the server last confirmed the despatch date against ShopVOX.
    let despatchDateSeenAt: String?

    /// The same value under its older name.
    let orderDueDate: String?
    let productionDueDate: String?

    /// Recorded but deliberately not what alerts fire on — ShopVOX's
    /// `shippingDate` is populated on about half of orders here and nobody
    /// maintains it.
    let shippingDate: String?
    let inHandDate: String?

    var isEmpty: Bool {
        despatchDate == nil && orderDueDate == nil && productionDueDate == nil
            && shippingDate == nil && inHandDate == nil
    }
}

struct JobLogistics: Decodable {
    let shippingMethod: String?
    let shipToCity: String?

    var isEmpty: Bool { shippingMethod == nil && shipToCity == nil }
}

struct JobProduction: Decodable {
    let currentStep: String?
    let currentStepGroup: String?
    let currentStage: String?
    let workflowState: String?
    let daysLeft: Int?
    let priority: Int?

    var isEmpty: Bool {
        currentStep == nil && currentStepGroup == nil && currentStage == nil
            && workflowState == nil && daysLeft == nil
    }
}

/// The people ShopVOX has attached to the job.
struct JobTeam: Decodable {
    let salesRep: String?
    let productionManager: String?
    let designer: String?

    var isEmpty: Bool {
        salesRep == nil && productionManager == nil && designer == nil
    }
}

/// ShopVOX exposes a *current* proof and says nothing about approval, so this
/// is never presented as final or approved.
struct JobProof: Decodable {
    /// Whether ShopVOX has a proof on this job at all. About one job in twenty
    /// has none, which is ordinary rather than a fault.
    let available: Bool?
    let label: String?
    /// Path on the Ops server that streams the file behind our credential.
    /// Preferred over `url`: the ShopVOX asset URLs are public and unsigned.
    let path: String?
    let thumbnailPath: String?
    /// The raw ShopVOX address, for opening in a browser where our credential
    /// cannot travel.
    let url: String?
    let thumbnailUrl: String?
    let note: String?

    var isEmpty: Bool { !(available ?? (url != nil)) }
    var displayLabel: String { label ?? "Current proof" }
}

struct JobStep: Decodable, Identifiable, Hashable {
    /// ShopVOX's own id for this step, and what a start/complete is addressed
    /// to. Null for a step reconstructed from a webhook, which carries only a
    /// name — such a step can be shown but not moved.
    let shopvoxStepId: String?
    let name: String
    let group: String?
    let state: String
    let stateLabel: String?
    let observedAt: String?
    let dataSource: JobDataSource
    /// Who worked the step. ShopVOX may list several names on one step.
    let assignedToName: String?
    let estimatedTime: Double?

    let canAct: Bool?
    let actions: [StepActionAvailability]?

    enum CodingKeys: String, CodingKey {
        case shopvoxStepId = "id"
        case name, group, state, stateLabel, observedAt, dataSource
        case assignedToName, estimatedTime, canAct, actions
    }

    /// Identity for SwiftUI. The name is unique per job and is present even
    /// when ShopVOX's id is not.
    var id: String { shopvoxStepId ?? name }

    func action(_ kind: StepActionKind) -> StepActionAvailability? {
        actions?.first { $0.action == kind.rawValue }
    }

    var isActionable: Bool { (canAct ?? false) && shopvoxStepId != nil }

    /// ShopVOX uses several words for "not finished but not running either".
    var isComplete: Bool { state == "completed" }
    var isActive: Bool { state == "started" }
    var isHalted: Bool { state == "paused" || state == "idling" || state == "stopped" }

    var displayState: String {
        // The server sends its own wording so both apps agree; fall back only
        // for a response from an older deploy.
        if let stateLabel { return stateLabel }
        switch state {
        case "completed": return "Done"
        case "started":   return "In progress"
        case "paused":    return "Paused"
        case "idling":    return "Idle"
        case "stopped":   return "Stopped"
        case "ready":     return "Ready"
        case "pending":   return "Not started"
        default:          return state.capitalized
        }
    }
}

enum StepActionKind: String, CaseIterable, Identifiable {
    case start
    case stop
    case complete

    var id: String { rawValue }

    var title: String {
        switch self {
        case .start:    return "Start"
        case .stop:     return "Pause"
        case .complete: return "Complete"
        }
    }

    var systemImage: String {
        switch self {
        case .start:    return "play.fill"
        case .stop:     return "pause.fill"
        case .complete: return "checkmark"
        }
    }
}

/// Whether one action is offered on one step, and the reason when it is not.
/// Rendered on the disabled control so it explains itself.
struct StepActionAvailability: Decodable, Hashable {
    let action: String
    let allowed: Bool
    let reason: String?
}

/// The server's answer to a start/stop/complete.
struct StepActionResponse: Decodable {
    let ok: Bool
    let action: String?
    let stepName: String?
    let previousState: String?
    let state: String?
    /// False when ShopVOX accepted the change but the job could not be
    /// re-read — a different thing from success, and said so.
    let confirmed: Bool?
    let message: String?
    let duplicate: Bool?
    let error: String?
    let reason: String?
    let stateUnchanged: Bool?
}

struct JobAlias: Decodable, Identifiable, Hashable {
    let kind: String
    let value: String
    let confidence: String

    var id: String { "\(kind)|\(value)" }

    var kindLabel: String {
        switch kind {
        case "erp_project_name":      return "Panel label"
        case "manifest_source_name":  return "Manifest"
        case "shopify_order":         return "Shopify"
        case "customer_po":           return "Customer PO"
        case "legacy_job_number":     return "Old job no."
        default:                      return kind.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// A guessed link must never look like an established fact.
    var needsConfirmation: Bool { confidence != "confirmed" }
}

struct JobProvenance: Decodable {
    let dataSource: JobDataSource
    let label: String
    let capturedAt: String?
    let isStale: Bool
    let staleSince: String?
    let updatedAt: String?
}

// MARK: - Date views

struct ProductionViewResponse: Decodable {
    let ok: Bool
    let view: String
    let today: String
    let count: Int

    /// What the dates in this response actually mean. Rendered verbatim so a
    /// view can never imply these are confirmed production schedules.
    let dateBasisLabel: String
    let caveat: String

    /// When a period is empty, the next date that does have orders. Computed
    /// server-side so the app never has to guess at the despatch rhythm.
    let nextDue: NextDueDate?

    let jobs: [ProductionJob]
}

struct NextDueDate: Decodable {
    let date: String
    let count: Int
}

struct ProductionJob: Decodable, Identifiable, Hashable {
    let id: String
    let jobNumber: String?
    let salesOrderNumber: String?
    let customerName: String?
    let customerPostcode: String?
    let jobTitle: String?
    let orderDueDate: String?
    let shippingMethod: String?
    let shipToCity: String?
    let currentStep: String?
    let currentStepGroup: String?
    let isOverdue: Bool
    let dataSource: JobDataSource
    let isStale: Bool

    var displayTitle: String { customerName ?? jobTitle ?? "Untitled job" }

    var primaryReference: String? {
        if let so = salesOrderNumber { return "SO \(so)" }
        if let jb = jobNumber { return "JB \(jb)" }
        return nil
    }
}
