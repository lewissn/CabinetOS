import SwiftUI

// MARK: - Rows

/// A list row: title, optional detail, optional trailing value, optional chevron, hairline below.
public struct PaperRow: View {
    let title: String
    let detail: String?
    let trailing: String?
    let chevron: Bool

    public init(_ title: String, detail: String? = nil, trailing: String? = nil, chevron: Bool = false) {
        self.title = title
        self.detail = detail
        self.trailing = trailing
        self.chevron = chevron
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).paperType(.body).foregroundStyle(PaperColor.ink).lineLimit(1)
                if let detail {
                    Text(detail).paperType(.footnote, numeric: true).foregroundStyle(PaperColor.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: PaperSpace.m)
            if let trailing {
                Text(trailing).paperType(.subhead, numeric: true).foregroundStyle(PaperColor.body)
            }
            if chevron { PaperIcon(.chevronRight, size: 14, color: PaperColor.faint) }
        }
        .padding(.vertical, PaperSpace.m)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { PaperHairline(color: PaperColor.hairlineSoft) }
    }
}

/// Section header: label on the left, optional detail or action on the right.
public struct PaperSectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: () -> Trailing

    public init(_ title: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.trailing = trailing
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            PaperLabel(title)
            Spacer()
            trailing()
        }
    }
}

public extension PaperSectionHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.title = title
        self.trailing = { EmptyView() }
    }
}

/// Big light figure with a small unit or context beside it, e.g. "70.4 kg", "1,840 of 3,000 kcal".
public struct PaperFigure: View {
    let value: String
    let unit: String?
    let style: PaperType

    public init(_ value: String, unit: String? = nil, style: PaperType = .heroS) {
        self.value = value
        self.unit = unit
        self.style = style
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: PaperSpace.s) {
            Text(value).paperType(style, numeric: true).foregroundStyle(PaperColor.ink)
            if let unit { Text(unit).paperType(.subhead, numeric: true).foregroundStyle(PaperColor.secondary) }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Small stat block: figure over caption, for rows of three.
public struct PaperStat: View {
    let value: String
    let label: String

    public init(_ value: String, label: String) {
        self.value = value
        self.label = label
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).paperType(.statFigure, numeric: true).foregroundStyle(PaperColor.ink)
            Text(label).paperType(.caption).foregroundStyle(PaperColor.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Flow

/// Wraps children onto new lines (chips, tags).
public struct PaperFlowLayout: Layout {
    var spacing: CGFloat

    public init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, width: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth { y += row; x = 0; row = 0 }
            x += size.width + spacing
            row = max(row, size.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: min(width, maxWidth), height: y + row)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { y += row; x = bounds.minX; row = 0 }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}

/// Wrapping chips for single or multiple selection.
public struct PaperChips<T: Hashable>: View {
    let options: [T]
    let label: (T) -> String
    let isSelected: (T) -> Bool
    let onTap: (T) -> Void

    public init(_ options: [T], label: @escaping (T) -> String, isSelected: @escaping (T) -> Bool, onTap: @escaping (T) -> Void) {
        self.options = options
        self.label = label
        self.isSelected = isSelected
        self.onTap = onTap
    }

    public var body: some View {
        PaperFlowLayout(spacing: PaperSpace.s) {
            ForEach(options, id: \.self) { option in
                Button(label(option)) { onTap(option) }
                    .buttonStyle(.paperChip(selected: isSelected(option)))
                    .accessibilityAddTraits(isSelected(option) ? .isSelected : [])
            }
        }
    }
}

// MARK: - Sheets and navigation

public extension View {
    /// Paper bottom sheet: paper background, 28 pt corners, drag indicator.
    func paperSheet(detents: Set<PresentationDetent> = [.large]) -> some View {
        self
            .presentationDetents(detents)
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
            .presentationBackground(PaperColor.paper)
    }
}

/// Top bar for sheets and pushed screens: close or "‹ Back" on the left, a centred title,
/// an optional trailing action. Use with the system navigation bar hidden.
public struct PaperTopBar<Trailing: View>: View {
    public enum Leading { case close, back(String), none }
    let leading: Leading
    let title: String?
    let onLeading: () -> Void
    @ViewBuilder let trailing: () -> Trailing

    public init(_ leading: Leading = .close, title: String? = nil, onLeading: @escaping () -> Void, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.leading = leading
        self.title = title
        self.onLeading = onLeading
        self.trailing = trailing
    }

    public var body: some View {
        ZStack {
            if let title {
                Text(title)
                    .font(.brand(17, .semibold, relativeTo: .headline))
                    .tracking(-0.34)
                    .foregroundStyle(PaperColor.ink)
                    .accessibilityAddTraits(.isHeader)
            }
            HStack {
                switch leading {
                case .close:
                    Button(action: onLeading) { PaperIcon(.close, size: 18) }
                        .buttonStyle(.paperIcon)
                        .padding(.leading, -10)
                        .accessibilityLabel("Close")
                case .back(let label):
                    Button(action: onLeading) {
                        HStack(spacing: 4) { PaperIcon(.chevronLeft, size: 18); Text(label).paperType(.callout) }
                            .foregroundStyle(PaperColor.ink)
                    }
                    .buttonStyle(.paperText(PaperColor.ink, .callout))
                    .padding(.leading, -6)
                    .accessibilityLabel("Back to \(label)")
                case .none:
                    EmptyView()
                }
                Spacer()
                trailing()
            }
        }
        .frame(minHeight: PaperSpace.tap)
    }
}

public extension PaperTopBar where Trailing == EmptyView {
    init(_ leading: Leading = .close, title: String? = nil, onLeading: @escaping () -> Void) {
        self.init(leading, title: title, onLeading: onLeading) { EmptyView() }
    }
}

/// Bottom tab bar: hairline on top, line glyphs; the current tab is ink with an amber mark. Pair with a ZStack of
/// tab contents (keep them alive with opacity) or a TabView with its own bar hidden.
public struct PaperTabBar<Tab: Hashable>: View {
    public struct Item {
        public let tab: Tab
        public let title: String
        public let glyph: PaperGlyph

        public init(_ tab: Tab, title: String, glyph: PaperGlyph) {
            self.tab = tab
            self.title = title
            self.glyph = glyph
        }
    }

    let items: [Item]
    @Binding var selection: Tab

    public init(_ items: [Item], selection: Binding<Tab>) {
        self.items = items
        self._selection = selection
    }

    public var body: some View {
        VStack(spacing: 0) {
            PaperHairline()
            HStack(spacing: 0) {
                ForEach(items, id: \.tab) { item in
                    let selected = item.tab == selection
                    Button { selection = item.tab } label: {
                        VStack(spacing: 5) {
                            PaperIcon(item.glyph, size: 22, color: selected ? PaperColor.ink : PaperColor.tertiary)
                            Text(item.title)
                                .font(.brand(11, .medium, relativeTo: .caption2))
                                .foregroundStyle(selected ? PaperColor.ink : PaperColor.tertiary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 10)
                        .padding(.bottom, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.title)
                    .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
                }
            }
        }
        .background(PaperColor.paper.ignoresSafeArea(edges: .bottom))
    }
}
