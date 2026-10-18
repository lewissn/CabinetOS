import Charts
import SwiftUI

/// A point on a line chart. Points with different `segment` values aren't joined, so gaps in
/// the data show as gaps rather than being interpolated.
public struct PaperPoint: Identifiable, Equatable, Sendable {
    public var id: Date { date }
    public let date: Date
    public let value: Double
    public let segment: Int

    public init(date: Date, value: Double, segment: Int = 0) {
        self.date = date
        self.value = value
        self.segment = segment
    }
}

public extension View {
    /// Axis styling: three trailing y labels over dashed hairline grid lines, three x date
    /// labels, Plus Jakarta Sans 11 pt in tertiary grey.
    func paperChartAxes(showX: Bool = true, showY: Bool = true, dateFormat: Date.FormatStyle = .dateTime.day().month(.abbreviated)) -> some View {
        self
            .chartXAxis {
                if showX {
                    AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                        AxisValueLabel(format: dateFormat, collisionResolution: .greedy)
                            .font(.brandFixed(11))
                            .foregroundStyle(PaperColor.tertiary)
                    }
                }
            }
            .chartYAxis {
                if showY {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4])).foregroundStyle(PaperColor.hairline)
                        AxisValueLabel().font(.brandFixed(11)).foregroundStyle(PaperColor.tertiary)
                    }
                }
            }
            .chartLegend(.hidden)
    }
}

/// Thin area chart with a soft red fill, no axes. Use small (e.g. 160 × 40) beside a figure.
public struct PaperSparkline: View {
    let points: [PaperPoint]

    public init(_ points: [PaperPoint]) {
        self.points = points
    }

    public var body: some View {
        let lo = points.map(\.value).min() ?? 0
        let hi = points.map(\.value).max() ?? 1
        let pad = max((hi - lo) * 0.25, abs(hi) * 0.002 + 0.01)
        let floor = lo - pad
        Chart {
            ForEach(points) { p in
                AreaMark(x: .value("Date", p.date), yStart: .value("Base", floor), yEnd: .value("Value", p.value), series: .value("Segment", p.segment))
                    .foregroundStyle(PaperColor.accent.opacity(0.08))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Date", p.date), y: .value("Value", p.value), series: .value("Segment", p.segment))
                    .foregroundStyle(PaperColor.accent)
                    .lineStyle(StrokeStyle(lineWidth: 1.75, lineCap: .round))
                    .interpolationMethod(.catmullRom)
            }
        }
        .chartYScale(domain: floor...(hi + pad * 0.4))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .accessibilityHidden(true)
    }
}

/// Raw readings as grey dots, a smoothed line in red over a soft fill, the latest point in red,
/// and optional horizontal reference marks (goals, milestones) when they're near the data.
public struct PaperTrendChart: View {
    let raw: [PaperPoint]
    let line: [PaperPoint]
    let marks: [(label: String, value: Double)]
    let showAxes: Bool
    let valueFormat: (Double) -> String

    public init(raw: [PaperPoint], line: [PaperPoint], marks: [(label: String, value: Double)] = [], showAxes: Bool = true,
                valueFormat: @escaping (Double) -> String = { PaperFormat.fixed($0, 1) }) {
        self.raw = raw
        self.line = line
        self.marks = marks
        self.showAxes = showAxes
        self.valueFormat = valueFormat
    }

    public var body: some View {
        let values = raw.map(\.value) + line.map(\.value)
        let lo = values.min() ?? 0
        let hi = values.max() ?? 1
        let span = max(hi - lo, max(abs(hi) * 0.01, 0.5))
        let near = marks.filter { $0.value >= lo - span * 0.6 && $0.value <= hi + span * 0.6 }
        let all = values + near.map(\.value)
        let domainLo = (all.min() ?? 0) - span * 0.12
        let domainHi = (all.max() ?? 1) + span * 0.12
        Chart {
            ForEach(line) { p in
                AreaMark(x: .value("Date", p.date), yStart: .value("Base", domainLo), yEnd: .value("Trend", p.value), series: .value("S", "a\(p.segment)"))
                    .foregroundStyle(PaperColor.accent.opacity(0.08))
                    .interpolationMethod(.catmullRom)
            }
            ForEach(near, id: \.label) { m in
                RuleMark(y: .value(m.label, m.value))
                    .foregroundStyle(PaperColor.borderStrong)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .leading, spacing: 2) {
                        Text(m.label).font(.brandFixed(10)).foregroundStyle(PaperColor.tertiary)
                    }
            }
            ForEach(raw) { p in
                PointMark(x: .value("Date", p.date), y: .value("Reading", p.value))
                    .foregroundStyle(PaperColor.borderStrong)
                    .symbolSize(22)
            }
            ForEach(line) { p in
                LineMark(x: .value("Date", p.date), y: .value("Trend", p.value), series: .value("S", "l\(p.segment)"))
                    .foregroundStyle(PaperColor.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)
            }
            if let last = line.last {
                PointMark(x: .value("Date", last.date), y: .value("Trend", last.value)).foregroundStyle(PaperColor.paper).symbolSize(110)
                PointMark(x: .value("Date", last.date), y: .value("Trend", last.value)).foregroundStyle(PaperColor.accent).symbolSize(55)
            }
        }
        .chartYScale(domain: domainLo...domainHi)
        .paperChartAxes(showX: showAxes, showY: showAxes)
    }
}

/// Bars where the latest is red and the rest are track grey, with an optional dashed target.
public struct PaperBarChart: View {
    public struct Bar: Identifiable, Sendable {
        public let id: String
        public let label: String
        public let value: Double
        public init(id: String, label: String, value: Double) {
            self.id = id
            self.label = label
            self.value = value
        }
    }

    let bars: [Bar]
    let target: Double?
    let showValues: Bool

    public init(_ bars: [Bar], target: Double? = nil, showValues: Bool = true) {
        self.bars = bars
        self.target = target
        self.showValues = showValues
    }

    public var body: some View {
        Chart {
            ForEach(Array(bars.enumerated()), id: \.element.id) { i, b in
                let latest = i == bars.count - 1
                BarMark(x: .value("Period", b.label), y: .value("Value", b.value), width: .ratio(0.7))
                    .foregroundStyle(latest ? PaperColor.accent : PaperColor.track)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .annotation(position: .bottom, spacing: 6) {
                        if showValues {
                            VStack(spacing: 1) {
                                Text(PaperFormat.int(b.value)).font(.brandFixed(11, latest ? .semibold : .regular)).monospacedDigit()
                                    .foregroundStyle(latest ? PaperColor.ink : PaperColor.secondary)
                                Text(b.label).font(.brandFixed(10)).foregroundStyle(PaperColor.tertiary)
                            }
                        }
                    }
            }
            if let target {
                RuleMark(y: .value("Target", target))
                    .foregroundStyle(PaperColor.ink)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .trailing, spacing: 3) {
                        Text(PaperFormat.int(target)).font(.brandFixed(11)).monospacedDigit().foregroundStyle(PaperColor.secondary)
                    }
            }
        }
        .chartYScale(domain: 0...(max(target ?? 0, bars.map(\.value).max() ?? 1) * 1.08))
        .chartXAxis(showValues ? .hidden : .automatic)
        .chartYAxis(.hidden)
        .padding(.bottom, showValues ? 34 : 0)   // room for the value and period labels under the bars
    }
}

/// Tiny trend line for list rows; the latest point is red when `highlight` is on.
public struct PaperMiniTrend: View {
    let values: [Double]
    let highlight: Bool

    public init(_ values: [Double], highlight: Bool = true) {
        self.values = values
        self.highlight = highlight
    }

    public var body: some View {
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                LineMark(x: .value("i", i), y: .value("v", v))
                    .foregroundStyle(highlight ? PaperColor.ink : PaperColor.borderStrong)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
            if highlight, let last = values.last {
                PointMark(x: .value("i", values.count - 1), y: .value("v", last)).foregroundStyle(PaperColor.accent).symbolSize(28)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
        .accessibilityHidden(true)
    }
}

/// Dot grid: one dot per day/slot. Filled for done, small for empty, red ring for "now".
public struct PaperDotGrid: View {
    public enum Dot: Sendable { case done, empty, future, now, none }
    let columns: Int
    let rows: Int
    let rowLabels: [String]
    let dot: (Int, Int) -> Dot

    public init(columns: Int, rows: Int = 7, rowLabels: [String] = ["M", "T", "W", "T", "F", "S", "S"], dot: @escaping (_ column: Int, _ row: Int) -> Dot) {
        self.columns = columns
        self.rows = rows
        self.rowLabels = rowLabels
        self.dot = dot
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 0) {
                    if !rowLabels.isEmpty {
                        Text(row < rowLabels.count ? rowLabels[row] : "").font(.brandFixed(10)).foregroundStyle(PaperColor.tertiary).frame(width: 16, alignment: .leading)
                    }
                    ForEach(0..<columns, id: \.self) { col in
                        mark(dot(col, row)).frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 11)
            }
        }
    }

    @ViewBuilder
    private func mark(_ d: Dot) -> some View {
        switch d {
        case .done: Circle().fill(PaperColor.ink).frame(width: 11, height: 11)
        case .now: Circle().strokeBorder(PaperColor.accent, lineWidth: 1.5).frame(width: 11, height: 11)
        case .empty: Circle().fill(PaperColor.dot).frame(width: 4, height: 4)
        case .future: Circle().fill(PaperColor.hairline).frame(width: 4, height: 4)
        case .none: Color.clear.frame(width: 4, height: 4)
        }
    }
}
