import CabinetDesign
import SwiftUI

/// The job's own ShopVOX steps as a track: done green, the current one
/// amber (an outline when it's paused), skipped hatched, the rest grey.
/// Never a percentage.
struct StepTrack: View {
    let steps: [JobStep]
    let currentIndex: Int?

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                segment(step, isCurrent: i == currentIndex)
            }
        }
        .frame(height: 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder private func segment(_ step: JobStep, isCurrent: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 2)
        if step.isSkipped {
            PaperHatch(color: PaperColor.border, spacing: 4, lineWidth: 1.5).clipShape(shape)
        } else if step.isComplete {
            shape.fill(PaperColor.success)
        } else if isCurrent {
            if step.isHalted {
                shape.strokeBorder(PaperColor.accent, lineWidth: 1.5)
            } else {
                shape.fill(PaperColor.accent)
            }
        } else {
            shape.fill(PaperColor.track)
        }
    }

    private var accessibilityText: String {
        let done = steps.filter(\.isComplete).count
        if let currentIndex, steps.indices.contains(currentIndex) {
            return "\(steps[currentIndex].name), step \(currentIndex + 1) of \(steps.count). \(done) done."
        }
        return "\(done) of \(steps.count) steps done"
    }
}

// MARK: - On a board row

/// The same track, small, for a row on the Jobs board: done green, the
/// current step amber (an outline when it's paused), the rest grey. The
/// current step is the first one not completed, as on the job page.
struct BoardStepTrack: View {
    let steps: [BoardStep]

    private var currentIndex: Int? { steps.firstIndex { !$0.isComplete } }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                let shape = RoundedRectangle(cornerRadius: 1.5)
                if step.isComplete {
                    shape.fill(PaperColor.success)
                } else if i == currentIndex {
                    if step.isHalted {
                        shape.strokeBorder(PaperColor.accent, lineWidth: 1.2)
                    } else {
                        shape.fill(PaperColor.accent)
                    }
                } else {
                    shape.fill(PaperColor.track)
                }
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }

    /// "Pack & Wrap · 7 of 8", or "All 8 done".
    var caption: String {
        guard let currentIndex else { return "All \(steps.count) done" }
        return "\(steps[currentIndex].name) · \(currentIndex + 1) of \(steps.count)"
    }
}
