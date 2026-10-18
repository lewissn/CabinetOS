import Foundation
import CoreGraphics

// MARK: - Scan Assembler
//
// Assembles a triplet from a rolling buffer of barcode detections across
// multiple camera frames.
//
// Two label formats are supported during the rollout of the larger labels.
// The assembler accepts whichever combination it sees first:
//
//   NEW labels (2 QR + 1 Code128 — preferred):
//     • QR (long)        → projectName  ("Lewis Nichols - 29248")
//     • QR (short)       → cabinetName  ("LDC", "UDC", "B-2")
//     • Code128 (digit)  → partNumber   ("4", "12")  — always 1–2 digits
//
//   LEGACY labels (1 QR + 2 Code128 — still in circulation):
//     • QR               → projectName
//     • Code128 (alpha)  → cabinetName  (any Code128 that isn't a part number)
//     • Code128 (digit)  → partNumber   (1–2 digits, all numeric)
//
// Classification:
//   • partNumber is unambiguous: the only 1–2 digit all-numeric value.
//   • Among QR codes, when an `expectedProjectName` is supplied (the project
//     name of the box being scanned into, known from the cached registry),
//     we match exactly: the QR equal to it is the projectName, the other QR
//     is the cabinetName. If no `expectedProjectName` is provided, we fall
//     back to a length heuristic — project names are nearly always longer
//     and contain a hyphen / digits, cabinet names are short codes.
//   • If only one QR is detected, the cabinetName comes from a non-part
//     Code128 (legacy format).

final class ScanAssembler {
    struct Detection {
        let payload: String
        let symbology: DetectedSymbology
        let centerPosition: CGPoint
        let timestamp: Date
    }

    enum DetectedSymbology {
        case qr
        case code128
    }

    enum AssemblyStatus: Equatable {
        case searching(hint: String)
        case assembled(ScanTriplet)
        case cooldown
    }

    private var buffer: [Detection] = []
    private let bufferWindowMs: Double
    private let cooldownMs: Double
    private let requiredStability: Int

    /// The project name of the box being scanned into, when known. Used to
    /// disambiguate the two QR codes on the new label format. Optional —
    /// when nil, we fall back to a length-based heuristic.
    private let expectedProjectName: String?

    private var lastCommitTime: Date?
    private(set) var lastCommittedTriplet: ScanTriplet?

    init(
        bufferWindowMs: Double = Configuration.scanBufferWindowMs,
        cooldownMs: Double = Configuration.scanDebounceCooldownMs,
        requiredStability: Int = Configuration.requiredFrameStability,
        expectedProjectName: String? = nil
    ) {
        self.bufferWindowMs = bufferWindowMs
        self.cooldownMs = cooldownMs
        self.requiredStability = requiredStability
        self.expectedProjectName = expectedProjectName
    }

    // MARK: - Public API

    /// Add a batch of detections from a single frame and attempt assembly.
    @discardableResult
    func addDetections(_ detections: [Detection]) -> AssemblyStatus {
        let now = Date()

        // Enforce debounce cooldown after a successful commit
        if let lastCommit = lastCommitTime {
            let elapsedMs = now.timeIntervalSince(lastCommit) * 1000
            if elapsedMs < cooldownMs {
                return .cooldown
            }
        }

        // A job label's QR is a link (https://ops…/jobs/<id>), and a panel
        // label never carries one. Read as a panel's project code it either
        // jammed assembly or paired with the wrong cabinet, so links are left
        // out — and if a link is all the camera can see, say what it is.
        let panelCodes = detections.filter { !Self.isLink($0.payload) }
        if panelCodes.isEmpty, !detections.isEmpty {
            return .searching(hint: "That's a job label. Scan the panel's own label.")
        }

        buffer.append(contentsOf: panelCodes)

        // Prune detections older than the rolling buffer window
        let cutoff = now.addingTimeInterval(-bufferWindowMs / 1000.0)
        buffer.removeAll { $0.timestamp < cutoff }

        return attemptAssembly()
    }

    /// Reset the assembler (call when scanner view closes or a new scan session starts).
    func reset() {
        buffer.removeAll()
        lastCommitTime = nil
        lastCommittedTriplet = nil
    }

    /// Clear the debounce cooldown early — e.g. after navigating to the next scan in continuous mode.
    func clearCooldown() {
        lastCommitTime = nil
    }

    /// A URL or deep link rather than a panel code.
    static func isLink(_ payload: String) -> Bool {
        let p = payload.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return p.contains("://") || p.hasPrefix("www.")
    }

    // MARK: - Assembly Logic

    private func attemptAssembly() -> AssemblyStatus {
        let qrValues       = stableValues(for: .qr)
        let code128Values  = stableValues(for: .code128)

        // The part number is the one unambiguous signal — short, all-digit
        // Code128. Pull it out first so the remaining values are easier to
        // classify.
        let partCandidates = code128Values.filter { isPartNumber($0) }
        let nonPartCode128 = code128Values.filter { !isPartNumber($0) }
        let partNumber = partCandidates.first

        // ── Path A: NEW label format — 2 QR + 1 Code128 (part number) ──────
        if qrValues.count >= 2 {
            let (projectName, cabinetName) = classifyTwoQRCodes(qrValues)
            guard let project = projectName, let cabinet = cabinetName else {
                return .searching(hint: "Reposition label — both QR codes need to be visible")
            }
            guard let part = partNumber else {
                return .searching(hint: "Found project + cabinet — find part number")
            }
            return commit(ScanTriplet(projectName: project, cabinetName: cabinet, partNumber: part))
        }

        // ── Path B: LEGACY label format — 1 QR + 2 Code128 ─────────────────
        if let project = qrValues.first {
            // Need a non-part Code128 (cabinet) and a part Code128 (number).
            if let cabinet = nonPartCode128.first, let part = partNumber {
                return commit(ScanTriplet(projectName: project, cabinetName: cabinet, partNumber: part))
            }
            if partNumber == nil && nonPartCode128.isEmpty {
                return .searching(hint: "Found project QR — find cabinet and part")
            }
            if partNumber == nil {
                return .searching(hint: "Found cabinet \(nonPartCode128.first ?? "") — find part number")
            }
            return .searching(hint: "Found part \(partNumber ?? "") — find cabinet")
        }

        // ── Nothing useful seen yet ─────────────────────────────────────────
        if code128Values.isEmpty {
            return .searching(hint: "Position label in the scan area")
        }
        return .searching(hint: "Find project QR code")
    }

    /// Commit a fully-assembled triplet, kick off the cooldown, and clear the
    /// buffer. Factored out because both label-format paths share it.
    private func commit(_ triplet: ScanTriplet) -> AssemblyStatus {
        lastCommitTime = Date()
        lastCommittedTriplet = triplet
        buffer.removeAll()
        return .assembled(triplet)
    }

    // MARK: - Stability

    /// Returns payloads that have appeared in ≥ requiredStability frames, sorted by frequency.
    private func stableValues(for symbology: DetectedSymbology) -> [String] {
        let matching = buffer.filter {
            switch (symbology, $0.symbology) {
            case (.qr, .qr):         return true
            case (.code128, .code128): return true
            default:                  return false
            }
        }

        var counts: [String: Int] = [:]
        for detection in matching {
            counts[detection.payload, default: 0] += 1
        }

        return counts
            .filter { $0.value >= requiredStability }
            .sorted { $0.value > $1.value }
            .map { $0.key }
    }

    // MARK: - Classification

    /// Separate two QR values into projectName and cabinetName.
    ///
    /// Strategy, in order of preference:
    ///   1. Exact match against `expectedProjectName` (from the box's
    ///      cached registry) → most reliable, zero ambiguity.
    ///   2. Length heuristic — project names are nearly always longer
    ///      ("Customer Name - 29248" ≈ 20+ chars) than cabinet names
    ///      ("LDC", "B-2"). If the lengths are very close (≤ 2 char diff)
    ///      and we have no expected name to anchor on, treat it as
    ///      ambiguous and ask the user to reposition.
    private func classifyTwoQRCodes(_ values: [String]) -> (project: String?, cabinet: String?) {
        guard values.count >= 2 else { return (values.first, nil) }
        let first = values[0]
        let second = values[1]

        // 1. Exact match on expected project name.
        if let expected = expectedProjectName {
            if first == expected { return (first, second) }
            if second == expected { return (second, first) }
            // Neither matches — could be a label from a different job.
            // Fall through to heuristic so we still produce a triplet; the
            // server-side check will reject it as WRONG_CONSIGNMENT and the
            // operator will see the right error.
        }

        // 2. Length heuristic.
        let longer  = first.count >= second.count ? first  : second
        let shorter = first.count >= second.count ? second : first

        // If lengths are nearly identical and we don't have an anchor, we
        // can't tell which is which — refuse to commit rather than guess.
        if expectedProjectName == nil && abs(first.count - second.count) <= 2 {
            return (nil, nil)
        }

        return (longer, shorter)
    }

    /// A part number is confirmed to be: all digits, 1–2 characters long.
    /// Cabinet names are never purely numeric, so this unambiguously classifies
    /// Code128 values on legacy labels.
    private func isPartNumber(_ value: String) -> Bool {
        guard value.count >= 1 && value.count <= 2 else { return false }
        return value.allSatisfy { $0.isNumber }
    }
}
