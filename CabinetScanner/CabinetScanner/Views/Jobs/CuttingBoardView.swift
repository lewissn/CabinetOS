import CabinetDesign
import SwiftUI

// MARK: - Production board
//
// The cutting-day board from the website, read-only. Each job sits on its
// cutting day, then In production, then Completed until it's despatched. Cards
// move when ShopVOX's steps do; booking days is done on the website.

@MainActor
final class CuttingBoardViewModel: ObservableObject {
    @Published private(set) var response: ProductionBoardResponse?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let service = JobIndexService()

    func load() async {
        isLoading = true
        do {
            response = try await service.productionBoard()
            errorMessage = nil
        } catch {
            if !Task.isCancelled {
                errorMessage = (error as? JobIndexError)?.errorDescription ?? error.localizedDescription
            }
        }
        isLoading = false
    }
}

struct CuttingBoardView: View {
    @ObservedObject var viewModel: CuttingBoardViewModel
    @AppStorage("board.stage") private var stage: Stage = .cutting

    enum Stage: String, Hashable {
        case cutting, production, completed
    }

    var body: some View {
        if let response = viewModel.response {
            loaded(response)
        } else if let error = viewModel.errorMessage, !viewModel.isLoading {
            PaperEmptyState("The board didn't load", message: error, actionTitle: "Try again") {
                Task { await viewModel.load() }
            }
        } else {
            VStack(spacing: 0) {
                ForEach(0..<6, id: \.self) { _ in SearchResultSkeleton() }
            }
            .allowsHitTesting(false)
        }
    }

    private func loaded(_ response: ProductionBoardResponse) -> some View {
        let board = response.board
        return VStack(alignment: .leading, spacing: 0) {
            // A poll that fails leaves the last good board up, and says so.
            if let error = viewModel.errorMessage {
                Notice(text: "This may be out of date. \(error)", tone: .soon).padding(.bottom, PaperSpace.m)
            }
            ForEach(response.notes, id: \.self) { note in
                Notice(text: note, tone: .soon).padding(.bottom, PaperSpace.m)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                PaperTextTabs([
                    (Stage.cutting, "Cutting days"),
                    (Stage.production, "In production \(board.inProduction.count)"),
                    (Stage.completed, "Completed \(board.completed.count)"),
                ], selection: $stage)
                .padding(.trailing, PaperSpace.margin)
            }
            .scrollClipDisabled()

            Group {
                switch stage {
                case .cutting:
                    cuttingDays(board)
                case .production:
                    cards(board.inProduction, empty: ("Nothing in production", "No job has CNC, edging, sanding or QC under way."))
                case .completed:
                    cards(board.completed, empty: ("Nothing completed", "No jobs are waiting to be despatched or collected."))
                }
            }
            .padding(.top, PaperSpace.l)
        }
    }

    @ViewBuilder
    private func cards(_ cards: [BoardCard], empty: (title: String, message: String)) -> some View {
        if cards.isEmpty {
            PaperEmptyState(empty.title, message: empty.message)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(cards) { BoardCardLink(card: $0) }
            }
        }
    }

    private func cuttingDays(_ board: CuttingBoard) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            cardGroup("Cutting day missed", board.missed)
            cardGroup("Needs a cutting day", board.needsDay)
            ForEach(board.weeks) { week in
                VStack(alignment: .leading, spacing: 0) {
                    if let monday = JobDateFormatting.parse(week.weekOf) {
                        Text("Week of \(JobDateFormatting.medium(monday))")
                            .paperType(.label)
                            .foregroundStyle(PaperColor.secondary)
                            .padding(.bottom, PaperSpace.s)
                    }
                    ForEach(Array(week.days.enumerated()), id: \.offset) { index, day in
                        if let day {
                            // A past day with nothing on it has nothing to say.
                            if !day.isPast || !day.cards.isEmpty {
                                BoardDaySection(day: day)
                            }
                        } else if let date = holidayDate(week: week, index: index) {
                            Text("\(JobDateFormatting.medium(date)) · Bank holiday")
                                .paperType(.footnote)
                                .foregroundStyle(PaperColor.tertiary)
                                .padding(.vertical, PaperSpace.m)
                        }
                    }
                }
                .padding(.bottom, PaperSpace.xl)
            }
            cardGroup("Booked later", board.later)
        }
    }

    private func holidayDate(week: CuttingBoard.Week, index: Int) -> Date? {
        JobDateFormatting.parse(week.weekOf).flatMap { Calendar.london.date(byAdding: .day, value: index, to: $0) }
    }

    @ViewBuilder
    private func cardGroup(_ title: String, _ cards: [BoardCard]) -> some View {
        if !cards.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                PaperSectionHeader(title) {
                    Text(PaperFormat.int(cards.count)).paperType(.footnote, numeric: true).foregroundStyle(PaperColor.tertiary)
                }
                ForEach(cards) { BoardCardLink(card: $0) }
            }
            .padding(.bottom, PaperSpace.xl)
        }
    }
}

// MARK: - A cutting day

private struct BoardDaySection: View {
    let day: BoardDay

    /// The streams worth a line: what the day is for, and anything booked on it
    /// regardless.
    private var streams: [(name: String, used: Double, target: Double, ceiling: Double)] {
        var lines: [(String, Double, Double, Double)] = []
        if day.type != "signature" || day.used.mdf > 0 {
            lines.append(("MDF", day.used.mdf, day.target.mdf, day.ceiling.mdf))
        }
        if day.type != "mdf" || day.used.signature > 0 {
            lines.append(("Signature", day.used.signature, day.target.signature, day.ceiling.signature))
        }
        return lines
    }

    private var title: String {
        guard let date = JobDateFormatting.parse(day.date) else { return day.date }
        return (day.isToday ? "Today, " : "") + JobDateFormatting.medium(date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PaperSpace.s) {
            Text(title).paperType(.bodyL, numeric: true).foregroundStyle(PaperColor.ink)
                .accessibilityAddTraits(.isHeader)

            ForEach(streams, id: \.name) { stream in
                capacity(stream)
            }
            if day.unknownM2 > 0 {
                Text("Plus \(Format.count(day.unknownM2, "job")) with no m² yet")
                    .paperType(.caption, numeric: true)
                    .foregroundStyle(PaperColor.tertiary)
            }
            ForEach(day.events, id: \.self) { event in
                StatusText(event.title, tone: .soon, lineLimit: nil)
            }
            if !day.collections.isEmpty {
                Text("Collection: \(day.collections.joined(separator: ", "))")
                    .paperType(.footnote)
                    .foregroundStyle(PaperColor.secondary)
            }

            if day.cards.isEmpty {
                Text("Nothing booked").paperType(.footnote).foregroundStyle(PaperColor.tertiary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(day.cards) { BoardCardLink(card: $0) }
                }
            }
        }
        .padding(.vertical, PaperSpace.m)
        .overlay(alignment: .bottom) { PaperHairline(color: PaperColor.hairlineSoft) }
    }

    private func capacity(_ stream: (name: String, used: Double, target: Double, ceiling: Double)) -> some View {
        let isOver = stream.ceiling > 0 && stream.used > stream.ceiling
        let isFull = stream.target > 0 && stream.used > stream.target
        let color = isOver ? PaperColor.danger : (isFull ? PaperColor.ember : PaperColor.accent)
        return VStack(alignment: .leading, spacing: 3) {
            Text("\(stream.name): \(PaperFormat.trimmed(stream.used)) of \(PaperFormat.trimmed(stream.target)) m², at most \(PaperFormat.trimmed(stream.ceiling))")
                .paperType(.caption, numeric: true)
                .foregroundStyle(isOver ? PaperColor.danger : PaperColor.secondary)
            PaperBar(stream.ceiling > 0 ? min(1, stream.used / stream.ceiling) : 0, color: color, height: 4)
                .frame(height: 4)
        }
    }
}

// MARK: - A card

private struct BoardCardLink: View {
    let card: BoardCard

    private var reference: String? {
        card.salesOrderNumber.map { "SO \($0)" } ?? card.shopifyOrderNumber.map { "#\($0)" }
    }

    private var title: String { card.customer ?? reference ?? "Job" }

    /// "14.2 m² · Signature · APC"
    private var facts: String? {
        var parts: [String] = []
        if let area = card.areaM2 { parts.append("\(PaperFormat.trimmed(area)) m²") }
        if let group = card.group { parts.append(group == "mdf" ? "MDF" : group.capitalized) }
        if let carrier = card.carrier { parts.append(carrier) }
        if card.tentative { parts.append("Not booked yet") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        NavigationLink(value: LinkedJob(id: card.jobId, title: card.customer)) {
            RowContainer(verticalPadding: PaperSpace.m) {
                VStack(alignment: .leading, spacing: PaperSpace.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: PaperSpace.m) {
                        Text(title).paperType(.body).foregroundStyle(PaperColor.ink).lineLimit(1)
                        Spacer(minLength: PaperSpace.s)
                        if let due = DueLine.make(isoDate: card.despatchDate) {
                            StatusText(due.text, tone: due.tone).fixedSize()
                        }
                    }
                    if reference != nil, card.customer != nil, let reference { Code(reference) }
                    if let step = card.step {
                        StatusText(step.name, tone: Tone(stepState: step.state))
                    }
                    if let facts {
                        Text(facts).paperType(.caption, numeric: true).foregroundStyle(PaperColor.secondary)
                    }
                    ForEach(card.flags, id: \.self) { flag in
                        Text(flag).paperType(.footnote).foregroundStyle(PaperColor.ember)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private extension Tone {
    init(stepState state: String) {
        switch state {
        case "completed": self = .done
        case "started", "paused", "idling", "stopped": self = .progress
        default: self = .neutral
        }
    }
}
