import CabinetDesign
import SwiftUI

// MARK: - Scan outcome: what the band says
//
// The scanner's states mapped to a word, a colour and an icon, readable
// across a bench. Built from ScannerViewModel's published values only; the
// view model's states and timing are unchanged.

enum ScanOutcome: Equatable {
    case ready(hint: String)
    case checking(String)
    case added(String)
    case problem(title: String, detail: String, tone: Tone)

    var tone: Tone {
        switch self {
        case .ready, .checking: .neutral
        case .added: .done
        case .problem(_, _, let tone): tone
        }
    }

    /// The corners and band only take a colour for a result.
    var isResult: Bool {
        switch self {
        case .added, .problem: true
        case .ready, .checking: false
        }
    }

    init(state: ScannerViewModel.ScanState, flash: String?) {
        switch state {
        case .error(let message):
            self = Self.problem(for: message)
        case .validating(let triplet):
            // The last "Added" stays up for its full second even when the
            // next label is already being checked, as the old banner did.
            self = flash.map { .added($0) } ?? .checking("\(triplet.cabinetName) · part \(triplet.partNumber)")
        case .success(let label):
            self = .added(flash ?? label)
        case .scanning(let hint):
            // The flash outlives the success state in continuous mode, so a
            // good scan always shows long enough to see.
            self = flash.map { .added($0) } ?? .ready(hint: hint)
        case .cooldown:
            self = flash.map { .added($0) } ?? .ready(hint: "Hold the next label in the frame")
        }
    }

    /// The error state carries only its message, so the headline word comes
    /// from what the message says. Anything unrecognised is still a clear
    /// "Not added" with the message underneath.
    private static func problem(for message: String) -> ScanOutcome {
        let m = message.lowercased()
        if m.contains("already") && m.contains("packed") {
            let detail = message == "This part has already been packed" ? "This panel is in a box already. Leave it out." : message
            return .problem(title: "Already packed", detail: detail, tone: .held)
        }
        if m.contains("not on this manifest") || m.contains("not_on_manifest") {
            return .problem(title: "Not on this manifest", detail: message, tone: .held)
        }
        if m.contains("consignment") && (m.contains("wrong") || m.contains("different") || m.contains("another")) {
            return .problem(title: "Not this consignment", detail: message, tone: .held)
        }
        if m.contains("open this box once while online") {
            return .problem(title: "Parts list not downloaded", detail: message, tone: .soon)
        }
        return .problem(title: "Not added", detail: message, tone: .held)
    }
}

/// The scan result: big word, colour and icon together, at a fixed height
/// so the screen doesn't jump between results.
struct ResultBand: View {
    let outcome: ScanOutcome
    var height: CGFloat = 112

    var body: some View {
        HStack(alignment: .center, spacing: PaperSpace.m) {
            icon.frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .paperType(.title)
                    .foregroundStyle(outcome.isResult ? outcome.tone.textColor : PaperColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(detail)
                    .paperType(.subhead, numeric: true)
                    .foregroundStyle(PaperColor.body)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, PaperSpace.l)
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .background(outcome.isResult ? outcome.tone.soft : PaperColor.paper, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            if !outcome.isResult { RoundedRectangle(cornerRadius: 12).strokeBorder(PaperColor.hairline, lineWidth: 1) }
        }
        .animation(PaperMotion.fade, value: outcome)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    @ViewBuilder private var icon: some View {
        switch outcome {
        case .ready: PaperIcon(.scan, size: 26, color: PaperColor.secondary)
        case .checking: ProgressView().tint(PaperColor.secondary)
        case .added: PaperIcon(.check, size: 26, lineWidth: 2.4, color: PaperColor.success)
        case .problem(_, _, let tone):
            if tone == .held {
                PaperIcon(.close, size: 24, lineWidth: 2.4, color: PaperColor.danger)
            } else {
                PaperIcon(.alert, size: 24, lineWidth: 2, color: tone.iconColor)
            }
        }
    }

    private var title: String {
        switch outcome {
        case .ready: "Ready to scan"
        case .checking: "Checking"
        case .added: "Added"
        case .problem(let title, _, _): title
        }
    }

    private var detail: String {
        switch outcome {
        case .ready(let hint): hint
        case .checking(let what): what
        case .added(let label): label
        case .problem(_, let detail, _): detail
        }
    }
}

/// The concept's viewfinder corners, which take the result's colour.
struct ScanCorners: View {
    let color: Color
    var length: CGFloat = 30
    var lineWidth: CGFloat = 4

    var body: some View {
        GeometryReader { g in
            let l = length, w = g.size.width, h = g.size.height
            Path { p in
                p.move(to: CGPoint(x: 0, y: l)); p.addLine(to: .zero); p.addLine(to: CGPoint(x: l, y: 0))
                p.move(to: CGPoint(x: w - l, y: 0)); p.addLine(to: CGPoint(x: w, y: 0)); p.addLine(to: CGPoint(x: w, y: l))
                p.move(to: CGPoint(x: w, y: h - l)); p.addLine(to: CGPoint(x: w, y: h)); p.addLine(to: CGPoint(x: w - l, y: h))
                p.move(to: CGPoint(x: l, y: h)); p.addLine(to: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: 0, y: h - l))
            }
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
        .animation(PaperMotion.fade, value: color)
        .accessibilityHidden(true)
    }
}
