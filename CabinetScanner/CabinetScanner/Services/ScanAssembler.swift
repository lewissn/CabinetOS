import Foundation
import CoreGraphics

// MARK: - Scan Assembler
//
// Assembles a triplet from a rolling buffer of barcode detections across multiple camera frames.
//
// Label format (per label printed in factory):
//   1. QR code         → projectName  (= source_name in Ops, e.g. "Lewis Nichols - 29248")
//   2. Code128 (alpha) → cabinetName  (e.g. "LDC", "UDC")  — always alphanumeric, never purely numeric
//   3. Code128 (digit) → partNumber   (e.g. "4", "12")     — always 1–2 digits, always numeric
//
// Classification rule (confirmed with Lewis, Feb 2026):
//   • partNumber  = all-digit string of length 1–2
//   • cabinetName = any other Code128 value
//   Edge cases (two numeric, two alpha) cannot occur given the confirmed label format.

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

    private var lastCommitTime: Date?
    private(set) var lastCommittedTriplet: ScanTriplet?

    init(
        bufferWindowMs: Double = Configuration.scanBufferWindowMs,
        cooldownMs: Double = Configuration.scanDebounceCooldownMs,
        requiredStability: Int = Configuration.requiredFrameStability
    ) {
        self.bufferWindowMs = bufferWindowMs
        self.cooldownMs = cooldownMs
        self.requiredStability = requiredStability
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

        buffer.append(contentsOf: detections)

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

    // MARK: - Assembly Logic

    private func attemptAssembly() -> AssemblyStatus {
        let qrValues     = stableValues(for: .qr)
        let code128Values = stableValues(for: .code128)

        // ── Step 1: Need exactly 1 stable QR code (projectName / source_name) ──
        guard let projectName = qrValues.first else {
            if !code128Values.isEmpty {
                return .searching(hint: "Find project QR code")
            }
            return .searching(hint: "Position label in the scan area")
        }

        // ── Step 2: Need 2 stable Code128 barcodes ──
        guard code128Values.count >= 2 else {
            if code128Values.isEmpty {
                return .searching(hint: "Find cabinet and part barcodes")
            }
            // One found — tell user which is missing
            let found = code128Values[0]
            if isPartNumber(found) {
                return .searching(hint: "Found part \(found) — find cabinet barcode")
            } else {
                return .searching(hint: "Found cabinet \(found) — find part number")
            }
        }

        // ── Step 3: Classify Code128 values ──
        let (cabinetName, partNumber) = classifyCodes(code128Values)

        guard let cabinet = cabinetName, let part = partNumber else {
            // Both values decoded but couldn't classify — shouldn't happen given confirmed label format,
            // but handle gracefully.
            let allDigits = code128Values.allSatisfy { isPartNumber($0) }
            if allDigits {
                return .searching(hint: "Cabinet barcode not found — reposition label")
            } else {
                return .searching(hint: "Part number not found — reposition label")
            }
        }

        // ── Step 4: Commit ──
        let triplet = ScanTriplet(
            projectName: projectName,
            cabinetName: cabinet,
            partNumber: part
        )
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

    /// Separate stable Code128 values into cabinetName and partNumber.
    /// Rule: 1–2 digit all-numeric string → partNumber; everything else → cabinetName.
    private func classifyCodes(_ values: [String]) -> (cabinet: String?, part: String?) {
        let parts    = values.filter { isPartNumber($0) }
        let cabinets = values.filter { !isPartNumber($0) }

        return (cabinets.first, parts.first)
    }

    /// A part number is confirmed to be: all digits, 1–2 characters long.
    /// Cabinet names are never purely numeric, so this unambiguously classifies Code128 values.
    private func isPartNumber(_ value: String) -> Bool {
        guard value.count >= 1 && value.count <= 2 else { return false }
        return value.allSatisfy { $0.isNumber }
    }
}
