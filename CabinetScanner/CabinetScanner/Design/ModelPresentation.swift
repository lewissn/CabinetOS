import CabinetDesign
import SwiftUI

// MARK: - How models read on screen
//
// View-side only: these map existing fields to the design's status
// meanings. They add no data and change nothing the models hold.

extension AppNotification {
    /// A date pulled towards us is the one to act on soon; the rest are news.
    var tone: Tone { isUrgent ? .soon : .neutral }
}

extension Box.BoxType {
    /// Sentence case, for titles and rows: "Panel box", "Fitting kit box".
    var label: String {
        switch self {
        case .panel: "Panel box"
        case .fittingKit: "Fitting kit box"
        case .drawerRunner: "Drawer runner box"
        case .hangingRail: "Hanging rail box"
        }
    }

    /// For the add chips: "+ Panels", "+ Fitting kit".
    var chipLabel: String {
        switch self {
        case .panel: "Panels"
        case .fittingKit: "Fitting kit"
        case .drawerRunner: "Drawer runners"
        case .hangingRail: "Hanging rail"
        }
    }
}

extension Box {
    /// "Panel box 3"
    var title: String { "\(boxType.label) \(boxNumber)" }
}

extension Consignment {
    /// The customer, for a row title.
    var title: String { customerName.isEmpty ? jobIdentifier : customerName }

    /// The job identifier without the customer's name when it repeats it:
    /// "Lewis Nichols - 29248" → "29248". Nil when there's nothing more to say.
    var jobRef: String? {
        guard !customerName.isEmpty, customerName != jobIdentifier else { return nil }
        if jobIdentifier.hasPrefix(customerName) {
            let rest = jobIdentifier.dropFirst(customerName.count)
                .trimmingCharacters(in: CharacterSet(charactersIn: " -–—|·"))
            return rest.isEmpty ? nil : rest
        }
        return jobIdentifier
    }

    var tone: Tone {
        if status == .complete { return .done }
        if packedItemCount >= expectedItemCount, expectedItemCount > 0 { return .done }
        return packedItemCount > 0 ? .progress : .neutral
    }

    /// "Complete", "Packing", "To pack"
    var statusLabel: String {
        if status == .complete { return "Complete" }
        if packedItemCount >= expectedItemCount, expectedItemCount > 0 { return "All packed" }
        return packedItemCount > 0 ? "Packing" : "To pack"
    }

    /// "12 of 32 panels", or "–" when nothing is expected.
    var packedLine: String {
        expectedItemCount > 0
            ? "\(PaperFormat.int(packedItemCount)) of \(PaperFormat.int(expectedItemCount)) panels"
            : "\(PaperFormat.int(packedItemCount)) packed"
    }

    var packedFraction: Double? {
        expectedItemCount > 0 ? Double(packedItemCount) / Double(expectedItemCount) : nil
    }
}

extension ProductionDateView {
    /// Sentence case, for the board's tabs.
    var label: String {
        switch self {
        case .overdue: "Overdue"
        case .thisWeek: "This week"
        case .today: "Today"
        // The next working day, as Ops now counts it: "Monday" on a Friday.
        case .tomorrow: WorkingDay.name()
        case .nextWeek: "Next week"
        case .upcoming: "Upcoming"
        case .yesterday: "Yesterday"
        case .recentlyCompleted: "Recent"
        }
    }
}
