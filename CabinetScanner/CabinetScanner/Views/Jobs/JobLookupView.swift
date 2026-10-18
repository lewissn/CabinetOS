import CabinetDesign
import SwiftUI

/// Opens the job page for a job known only by its sales order — a row on
/// Today, which comes from the jobs table rather than the job index.
///
/// Searches the index for the number and opens the one exact match. Two
/// matches (a repeat order number) are listed rather than guessed between.
struct JobLookupView: View {
    let salesOrder: String
    let customer: String

    private enum LoadState {
        case loading
        case found(JobSearchResult)
        case choices([JobSearchResult])
        case failed(String)
    }

    @State private var state: LoadState = .loading
    private let service = JobIndexService()

    var body: some View {
        Group {
            switch state {
            case .found(let result):
                JobDetailView(jobId: result.id, knownTitle: result.displayTitle, jobTitle: result.jobTitle, backLabel: "Back")
            case .loading:
                PushedScreen(back: "Back") {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        LoadingLine("Finding the job").section(top: PaperSpace.xxl)
                    }
                    .screen()
                }
            case .choices(let results):
                PushedScreen(back: "Back") {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        if results.isEmpty {
                            PaperEmptyState("Not in the job index",
                                            message: "SO \(salesOrder) hasn't been imported or seen by a webhook yet, so there's no job page for it.")
                                .section(top: PaperSpace.xxl)
                        } else {
                            VStack(alignment: .leading, spacing: 0) {
                                PaperSectionHeader("More than one job has this number")
                                ForEach(results) { result in
                                    NavigationLink {
                                        JobDetailView(jobId: result.id, knownTitle: result.displayTitle, jobTitle: result.jobTitle, backLabel: "Back")
                                    } label: {
                                        JobSearchResultRow(result: result)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .section(top: PaperSpace.xxl)
                        }
                    }
                    .screen()
                }
            case .failed(let message):
                PushedScreen(back: "Back") {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        PaperEmptyState("The job didn't load", message: message, actionTitle: "Try again") {
                            Task { await lookUp() }
                        }
                        .section(top: PaperSpace.xxl)
                    }
                    .screen()
                }
            }
        }
        .task { await lookUp() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: PaperSpace.s) {
            Code("SO \(salesOrder)", color: PaperColor.ink, size: 14)
            Text(customer)
                .paperType(.largeTitle)
                .foregroundStyle(PaperColor.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, PaperSpace.s)
    }

    private func lookUp() async {
        if case .found = state { return }
        state = .loading
        do {
            let response = try await service.search(query: salesOrder)
            let exact = response.results.filter { $0.salesOrderNumber == salesOrder }
            if exact.count == 1, let only = exact.first {
                state = .found(only)
            } else {
                state = .choices(exact)
            }
        } catch {
            state = .failed((error as? JobIndexError)?.errorDescription ?? error.localizedDescription)
        }
    }
}
