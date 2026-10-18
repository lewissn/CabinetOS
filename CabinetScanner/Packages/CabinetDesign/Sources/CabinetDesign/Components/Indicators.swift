import SwiftUI

// MARK: - Segmented control

/// Pill segmented control (e.g. "Goals | Charts", "45 / 60 / 75 min").
public struct PaperSegmented<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    let accessibilityLabel: String

    @Namespace private var ns

    public init(_ options: [(value: Value, label: String)], selection: Binding<Value>, accessibilityLabel: String) {
        self.options = options
        self._selection = selection
        self.accessibilityLabel = accessibilityLabel
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { selection = option.value }
                } label: {
                    Text(option.label)
                        .font(.brand(13, selected ? .medium : .regular, relativeTo: .footnote))
                        .monospacedDigit()
                        .foregroundStyle(selected ? PaperColor.ink : PaperColor.secondary)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 30)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(PaperColor.raised)
                                    .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
                                    .matchedGeometryEffect(id: "segment", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(PaperColor.segment, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Underlined text tabs (e.g. chart ranges "1M 3M 6M 1Y All").
public struct PaperTextTabs<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value

    public init(_ options: [(value: Value, label: String)], selection: Binding<Value>) {
        self.options = options
        self._selection = selection
    }

    public var body: some View {
        HStack(spacing: 18) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Button(option.label) { withAnimation(.easeInOut(duration: 0.2)) { selection = option.value } }
                    .font(.brand(13, selected ? .medium : .regular, relativeTo: .footnote))
                    .foregroundStyle(selected ? PaperColor.ink : PaperColor.secondary)
                    .frame(minHeight: 32)
                    .overlay(alignment: .bottom) {
                        if selected { Capsule().fill(PaperColor.accent).frame(height: 1.5).offset(y: -2) }
                    }
                    .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

// MARK: - Bars

/// Thin rounded progress bar (3 pt). Fraction clamps to 0…1.
public struct PaperBar: View {
    let fraction: Double
    let color: Color
    let track: Color
    let height: CGFloat

    public init(_ fraction: Double, color: Color = PaperColor.accent, track: Color = PaperColor.track, height: CGFloat = 3) {
        self.fraction = fraction
        self.color = color
        self.track = track
        self.height = height
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(color).frame(width: max(0, min(1, fraction.isFinite ? fraction : 0)) * geo.size.width)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// One bar per step, each filled by its own fraction (e.g. exercises in a workout).
public struct PaperSegmentedProgress: View {
    let fractions: [Double]
    let spacing: CGFloat

    public init(_ fractions: [Double], spacing: CGFloat = 4) {
        self.fractions = fractions
        self.spacing = spacing
    }

    public var body: some View {
        HStack(spacing: spacing) {
            ForEach(Array(fractions.enumerated()), id: \.offset) { _, f in
                PaperBar(f, color: PaperColor.accent, track: PaperColor.hairline, height: 4)
            }
        }
    }
}

/// Bar against a target: the lower target sits at a midpoint tick.
public struct PaperTargetBar: View {
    let value: Double
    let target: Double
    let color: Color

    public init(value: Double, target: Double, color: Color = PaperColor.ink) {
        self.value = value
        self.target = target
        self.color = color
    }

    public var body: some View {
        GeometryReader { geo in
            let maxValue = max(1, target * 2)
            ZStack(alignment: .leading) {
                Capsule().fill(PaperColor.track).frame(height: 6)
                Capsule().fill(color).frame(width: geo.size.width * min(1, value / maxValue), height: 6)
                Rectangle().fill(PaperColor.faint).frame(width: 1, height: 12).offset(x: geo.size.width * target / maxValue)
            }
            .frame(height: geo.size.height)
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }
}

/// Diagonal hatching for unknown values. Unknown is never drawn as zero.
public struct PaperHatch: View {
    let color: Color
    let spacing: CGFloat
    let lineWidth: CGFloat

    public init(color: Color = PaperColor.border, spacing: CGFloat = 5, lineWidth: CGFloat = 2) {
        self.color = color
        self.spacing = spacing
        self.lineWidth = lineWidth
    }

    public var body: some View {
        Canvas { ctx, size in
            var path = Path()
            var x: CGFloat = -size.height
            while x < size.width + size.height {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += spacing
            }
            ctx.stroke(path, with: .color(color), lineWidth: lineWidth)
        }
        .accessibilityHidden(true)
    }
}

/// A segment of a composition bar. `fraction == nil` means unknown.
public struct PaperSegment: Identifiable, Sendable {
    public let id: String
    public let fraction: Double?
    public let color: Color

    public init(id: String, fraction: Double?, color: Color) {
        self.id = id
        self.fraction = fraction
        self.color = color
    }
}

/// Composition bar: known parts proportionally; if any part is unknown the rest is hatched.
/// Pass `remainder` to fill unused space (e.g. calories left) when nothing is unknown.
public struct PaperCompositionBar: View {
    let segments: [PaperSegment]
    let height: CGFloat
    let radius: CGFloat
    let gap: CGFloat
    let remainder: Color?

    public init(_ segments: [PaperSegment], height: CGFloat = 12, radius: CGFloat = 3, gap: CGFloat = 3, remainder: Color? = nil) {
        self.segments = segments
        self.height = height
        self.radius = radius
        self.gap = gap
        self.remainder = remainder
    }

    public var body: some View {
        GeometryReader { geo in
            let known = segments.compactMap { s -> (PaperSegment, Double)? in
                guard let f = s.fraction, f > 0.001 else { return nil }
                return (s, f)
            }
            let hasUnknown = segments.contains { $0.fraction == nil }
            let total = known.reduce(0) { $0 + $1.1 }
            let scale = total > 1 ? 1 / total : 1
            let pieces = known.count + ((hasUnknown || remainder != nil) ? 1 : 0)
            let usable = max(0, geo.size.width - gap * CGFloat(max(0, pieces - 1)))
            HStack(spacing: gap) {
                ForEach(known, id: \.0.id) { seg, f in
                    RoundedRectangle(cornerRadius: radius).fill(seg.color).frame(width: max(2, usable * f * scale))
                }
                if hasUnknown {
                    PaperHatch().clipShape(RoundedRectangle(cornerRadius: radius)).frame(maxWidth: .infinity)
                } else if let remainder {
                    RoundedRectangle(cornerRadius: radius).fill(remainder).frame(maxWidth: .infinity)
                }
            }
        }
        .frame(height: height)
    }
}

// MARK: - Rings

/// Concentric rings: outer in red, inner in ink (e.g. calories and protein).
public struct PaperRings: View {
    let outer: Double
    let inner: Double
    let lineWidth: CGFloat
    let centreText: String?

    public init(outer: Double, inner: Double, lineWidth: CGFloat = 11, centreText: String? = nil) {
        self.outer = outer
        self.inner = inner
        self.lineWidth = lineWidth
        self.centreText = centreText
    }

    public var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let scale = size / 148
            ZStack {
                ring(radius: 66 * scale, fraction: outer, color: PaperColor.accent, lw: lineWidth * scale)
                ring(radius: 49 * scale, fraction: inner, color: PaperColor.ink, lw: lineWidth * scale)
                if let centreText {
                    Text(centreText)
                        .font(.brand(25 * scale, .medium, relativeTo: .title3))
                        .monospacedDigit()
                        .foregroundStyle(PaperColor.ink)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .frame(width: 70 * scale)
                }
            }
            .frame(width: size, height: size)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func ring(radius: CGFloat, fraction: Double, color: Color, lw: CGFloat) -> some View {
        ZStack {
            Circle().stroke(PaperColor.track, lineWidth: lw)
            Circle()
                .trim(from: 0, to: max(0, min(1, fraction.isFinite ? fraction : 0)))
                .stroke(color, style: StrokeStyle(lineWidth: lw, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: radius * 2, height: radius * 2)
    }
}

/// Single ring countdown or progress (e.g. a timer on a dark bar).
public struct PaperRing: View {
    let fraction: Double
    let color: Color
    let track: Color
    let lineWidth: CGFloat

    public init(_ fraction: Double, color: Color = PaperColor.accent, track: Color = PaperColor.track, lineWidth: CGFloat = 4) {
        self.fraction = fraction
        self.color = color
        self.track = track
        self.lineWidth = lineWidth
    }

    public var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
    }
}

// MARK: - Marks

/// Completion circle: open, done (red), muted done (grey) or active (red ring).
public struct PaperCheck: View {
    public enum State: Sendable { case open, done, mutedDone, active }
    let state: State
    let size: CGFloat

    public init(_ state: State, size: CGFloat = 26) {
        self.state = state
        self.size = size
    }

    public var body: some View {
        ZStack {
            switch state {
            case .open: Circle().strokeBorder(PaperColor.ink, lineWidth: 1.5)
            case .active: Circle().strokeBorder(PaperColor.accent, lineWidth: 1.5)
            case .done, .mutedDone:
                Circle().fill(state == .done ? PaperColor.success : PaperColor.dot)
                PaperIcon(.check, size: size * 0.5, lineWidth: 3, color: .white)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Legend swatch: filled square (or dot), or hollow for "unknown / empty".
public struct PaperSwatch: View {
    let color: Color
    let hollow: Bool
    let size: CGFloat
    let round: Bool

    public init(_ color: Color, hollow: Bool = false, size: CGFloat = 8, round: Bool = false) {
        self.color = color
        self.hollow = hollow
        self.size = size
        self.round = round
    }

    public var body: some View {
        Group {
            if hollow {
                RoundedRectangle(cornerRadius: round ? size / 2 : 2).strokeBorder(PaperColor.dot, lineWidth: 1)
            } else {
                RoundedRectangle(cornerRadius: round ? size / 2 : 2).fill(color)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// "Then → now" connector: a hairline ending in a red dot, solid or dashed. Every line must
/// mean something; use it to link a past value to the current one.
public struct PaperConnector: View {
    let dashed: Bool
    let showsDot: Bool
    let color: Color
    let dotColor: Color
    let lineWidth: CGFloat

    public init(dashed: Bool = false, showsDot: Bool = true, color: Color = PaperColor.dot, dotColor: Color = PaperColor.accent, lineWidth: CGFloat = 1.5) {
        self.dashed = dashed
        self.showsDot = showsDot
        self.color = color
        self.dotColor = dotColor
        self.lineWidth = lineWidth
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .trailing) {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: geo.size.height / 2))
                    p.addLine(to: CGPoint(x: geo.size.width - (showsDot ? 3 : 0), y: geo.size.height / 2))
                }
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, dash: dashed ? [4, 3] : []))
                if showsDot { Circle().fill(dotColor).frame(width: 6, height: 6) }
            }
        }
        .frame(height: 7)
        .accessibilityHidden(true)
    }
}

/// Soft red banner for a suggestion the user can accept or dismiss.
public struct PaperSuggestion: View {
    let text: String
    let actionTitle: String
    let onAction: () -> Void
    let onDismiss: (() -> Void)?

    public init(_ text: String, actionTitle: String = "Use", onAction: @escaping () -> Void, onDismiss: (() -> Void)? = nil) {
        self.text = text
        self.actionTitle = actionTitle
        self.onAction = onAction
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: PaperSpace.m) {
            PaperIcon(.arrowUp, size: 14, lineWidth: 2.4, color: PaperColor.accentInk)
            Text(text)
                .paperType(.subhead, numeric: true)
                .foregroundStyle(PaperColor.body)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(actionTitle, action: onAction)
                .font(.brand(14, .semibold, relativeTo: .subheadline))
                .foregroundStyle(PaperColor.accentInk)
                .frame(minWidth: 36, minHeight: 36)
            if let onDismiss {
                Button(action: onDismiss) { PaperIcon(.close, size: 12, lineWidth: 2, color: PaperColor.secondary) }
                    .frame(width: 28, height: 36)
                    .accessibilityLabel("Dismiss")
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(PaperColor.accentSoft, in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Calm empty state: one line of title, one of explanation, optional action. No illustrations.
public struct PaperEmptyState: View {
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    public init(_ title: String, message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: PaperSpace.s) {
            Text(title).paperType(.body).foregroundStyle(PaperColor.ink)
            Text(message).paperType(.subhead).foregroundStyle(PaperColor.secondary).fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.paperText(PaperColor.accentInk, .subhead, weight: .medium))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, PaperSpace.l)
    }
}
