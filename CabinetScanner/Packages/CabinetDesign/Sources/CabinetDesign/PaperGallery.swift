import SwiftUI

/// Every token and component on one scrolling page. Drop `PaperGallery()` into a preview or a
/// debug screen to see the system in both themes. Values shown are samples.
public struct PaperGallery: View {
    public init() {}

    public var body: some View {
        ScrollView {
            PaperGalleryContent()
                .paperMargins()
                .padding(.vertical, PaperSpace.section)
        }
        .paperBackground()
    }
}

/// The gallery without the scroll view (renderable with `ImageRenderer`).
public struct PaperGalleryContent: View {
    @State private var segment = 1
    @State private var tab = 0
    @State private var range = "1M"
    @State private var field = "70.4"
    @State private var search = ""
    @State private var chips: Set<String> = ["Chest"]

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: PaperSpace.section) {
            header
            PaperHairline()
            typeScale
            PaperHairline()
            colours
            PaperHairline()
            controls
            PaperHairline()
            indicators
            PaperHairline()
            charts
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                Text("Sun 18 Oct · ").foregroundStyle(PaperColor.secondary)
                Text("Paper design").foregroundStyle(PaperColor.accent)
            }
            .paperType(.label)
            Text("Good evening").paperType(.greeting).foregroundStyle(PaperColor.ink)
            Text("Light-first, no cards, hairlines and whitespace. Red only for progress, primary actions, the latest data point and suggestions.")
                .paperType(.subhead).foregroundStyle(PaperColor.secondary)
        }
    }

    private var typeScale: some View {
        VStack(alignment: .leading, spacing: PaperSpace.m) {
            PaperLabel("Type")
            PaperFigure("70.4", unit: "kg", style: .heroS)
            Text("Large title").paperType(.largeTitle).foregroundStyle(PaperColor.ink)
            Text("Title").paperType(.title).foregroundStyle(PaperColor.ink)
            Text("Headline").paperType(.headline).foregroundStyle(PaperColor.ink)
            Text("Body, for list rows and text").paperType(.body).foregroundStyle(PaperColor.ink)
            Text("Subhead in body grey").paperType(.subhead).foregroundStyle(PaperColor.body)
            Text("Footnote in secondary grey").paperType(.footnote).foregroundStyle(PaperColor.secondary)
            PaperLabel("Section label")
        }
    }

    private var colours: some View {
        VStack(alignment: .leading, spacing: PaperSpace.m) {
            PaperLabel("Colour")
            HStack(spacing: PaperSpace.s) {
                ForEach(Array([PaperColor.ink, PaperColor.body, PaperColor.secondary, PaperColor.tertiary, PaperColor.faint, PaperColor.dot, PaperColor.track, PaperColor.hairline].enumerated()), id: \.offset) { _, c in
                    RoundedRectangle(cornerRadius: 4).fill(c).frame(height: 28)
                }
            }
            HStack(spacing: PaperSpace.s) {
                ForEach(Array((PaperColor.series + [PaperColor.accentSoft]).enumerated()), id: \.offset) { _, c in
                    RoundedRectangle(cornerRadius: 4).fill(c).frame(height: 28)
                }
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: PaperSpace.l) {
            PaperLabel("Controls")
            HStack(spacing: 14) {
                Button {} label: { HStack(spacing: 6) { Text("Begin"); PaperIcon(.arrowRight, size: 13, lineWidth: 2, color: .white) } }
                    .buttonStyle(.paperPill(.accent, .compact))
                Button("Change") {}.buttonStyle(.paperText())
                Spacer()
                Button {} label: { PaperIcon(.swap, size: 18, color: PaperColor.secondary) }.buttonStyle(.paperIcon)
            }
            Button("Primary action") {}.buttonStyle(.paperPrimary)
            HStack(spacing: PaperSpace.m) {
                Button("Ink") {}.buttonStyle(.paperPill(.ink, .compact))
                Button("Outline") {}.buttonStyle(.paperPill(.outline, .compact))
                Button("Disabled") {}.buttonStyle(.paperPill(.accent, .compact)).disabled(true)
            }
            PaperChips(["Chest", "Back", "Shoulders", "Legs"], label: { $0 }, isSelected: { chips.contains($0) }) { c in
                if chips.contains(c) { chips.remove(c) } else { chips.insert(c) }
            }
            HStack {
                PaperLabel("Time")
                Spacer()
                PaperSegmented([(0, "45 min"), (1, "60 min"), (2, "75 min")], selection: $segment, accessibilityLabel: "Time")
            }
            PaperTextTabs([("1M", "1M"), ("3M", "3M"), ("6M", "6M"), ("1Y", "1Y"), ("All", "All")], selection: $range)
            PaperUnderlineField("Weight", text: $field, unit: "kg", keyboard: .decimalPad)
            PaperSearchField(text: $search)
            PaperSuggestion("12 on every set, twice. Ready for 22 kg.", onAction: {}, onDismiss: {})
            PaperRow("Incline dumbbell press", detail: "3 × 8–12 · last 20 kg", trailing: "+4 kg", chevron: true)
            PaperTabBar([.init(0, title: "Today", glyph: .target), .init(1, title: "Training", glyph: .barbell),
                         .init(2, title: "Food", glyph: .clock), .init(3, title: "Progress", glyph: .trend)], selection: $tab)
        }
    }

    private var indicators: some View {
        VStack(alignment: .leading, spacing: PaperSpace.l) {
            PaperLabel("Indicators")
            HStack(spacing: 26) {
                PaperRings(outer: 0.61, inner: 0.77, centreText: "61%").frame(width: 116, height: 116)
                VStack(alignment: .leading, spacing: PaperSpace.m) {
                    PaperRing(0.8, track: PaperColor.track).frame(width: 52, height: 52)
                    HStack(spacing: PaperSpace.s) {
                        PaperCheck(.open); PaperCheck(.done); PaperCheck(.mutedDone); PaperCheck(.active)
                    }
                }
            }
            PaperSegmentedProgress([1, 0.67, 0, 0, 0])
            PaperBar(0.76)
            PaperTargetBar(value: 6, target: 10, color: PaperColor.accent)
            PaperCompositionBar([
                PaperSegment(id: "p", fraction: 0.7, color: PaperColor.ink),
                PaperSegment(id: "c", fraction: 0.25, color: PaperColor.accent),
                PaperSegment(id: "f", fraction: nil, color: PaperColor.muted),
            ])
            HStack(spacing: PaperSpace.m) {
                Text("16").paperType(.callout, numeric: true).foregroundStyle(PaperColor.tertiary)
                PaperConnector().frame(width: 36)
                Text("20").paperType(.figureS, numeric: true).foregroundStyle(PaperColor.ink)
                Spacer()
                PaperConnector(dashed: true, color: PaperColor.accent).frame(width: 60)
            }
            HStack(alignment: .top, spacing: PaperSpace.m) {
                PaperStat("70.3", label: "7-day avg")
                PaperStat("+0.1", label: "kg / week")
                PaperStat("21", label: "weigh-ins")
            }
            PaperDotGrid(columns: 12) { col, row in
                col < 3 ? ((col + row) % 2 == 0 ? .done : .empty) : (col == 3 && row == 6 ? .now : .future)
            }
            PaperEmptyState("Nothing here yet", message: "One line on what will appear, and how to start.", actionTitle: "Start") {}
        }
    }

    private var charts: some View {
        let start = Calendar.current.date(byAdding: .day, value: -27, to: .now) ?? .now
        let line = (0..<28).map { i in PaperPoint(date: Calendar.current.date(byAdding: .day, value: i, to: start) ?? start, value: 70 + Double(i) * 0.015) }
        let raw = line.enumerated().compactMap { i, p in i % 4 == 2 ? nil : PaperPoint(date: p.date, value: p.value + (Double((i * 7) % 5) - 2) * 0.12) }
        return VStack(alignment: .leading, spacing: PaperSpace.l) {
            PaperLabel("Charts")
            HStack {
                PaperFigure("70.4", unit: "kg", style: .heroS)
                Spacer()
                PaperSparkline(line).frame(width: 160, height: 40)
            }
            PaperTrendChart(raw: raw, line: line, marks: [("Goal", 70.6)]).frame(height: 200)
            PaperBarChart([.init(id: "1", label: "W1", value: 2480), .init(id: "2", label: "W2", value: 2590),
                           .init(id: "3", label: "W3", value: 2710), .init(id: "4", label: "W4", value: 2780)], target: 3000)
                .frame(height: 132)
            HStack {
                Text("Back squat").paperType(.body).foregroundStyle(PaperColor.ink)
                Spacer()
                PaperMiniTrend([50, 52.5, 57.5, 60]).frame(width: 80, height: 28)
            }
        }
    }
}

#Preview("Light") { PaperGallery().preferredColorScheme(.light) }
#Preview("Dark") { PaperGallery().preferredColorScheme(.dark) }
