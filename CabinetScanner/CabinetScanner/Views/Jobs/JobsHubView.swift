import SwiftUI

// MARK: - Jobs Hub
//
// Search and the production board share one tab.
//
// They were briefly separate tabs, which pushed the app to six and made iOS
// collapse Stock and Settings behind "More" — burying two screens the team
// already relied on. Combining them is also the better design: searching for a
// job and browsing what is due are the same task at different levels of
// specificity, and the search field is where a person's hand goes first.
//
// Typing in the search field replaces the board with results; clearing it
// brings the board back. Nothing is lost, and the tab bar stays at five.

struct JobsHubView: View {
    @StateObject private var search = JobSearchViewModel()
    @StateObject private var board = ProductionViewsViewModel()
    @EnvironmentObject private var router: AppRouter

    /// The job a link or a notification asked for, pushed onto this stack.
    @State private var linkedJobId: String?

    private var isSearching: Bool { !search.trimmedQuery.isEmpty }

    var body: some View {
        NavigationStack {
            Group {
                if isSearching {
                    JobSearchResults(viewModel: search)
                } else {
                    ProductionBoard(viewModel: board)
                }
            }
            .navigationTitle(isSearching ? "Search" : "Jobs")
            .navigationDestination(for: JobSearchResult.self) { result in
                JobDetailView(jobId: result.id, knownTitle: result.displayTitle)
            }
            .navigationDestination(for: ProductionJob.self) { job in
                JobDetailView(jobId: job.id, knownTitle: job.displayTitle)
            }
            // A deep link or a tapped notification. Kept as its own
            // destination rather than pushed as a value, because the only
            // thing known about it is the id.
            .navigationDestination(item: $linkedJobId) { id in
                JobDetailView(jobId: id)
            }
            .searchable(
                text: $search.query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Sales order, customer, Shopify number…"
            )
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .task { await board.load() }
            // Taken on appearing AND on change: a link can arrive while this
            // tab is already showing, or before it has ever been opened.
            .task(id: router.pendingJobId) { takePendingJob() }
        }
    }

    private func takePendingJob() {
        guard router.pendingJobId != nil else { return }
        // Searching and a pushed detail screen fight each other; clear the
        // field so the link lands on the job rather than under a result list.
        search.clear()
        linkedJobId = router.consumeJob()
    }
}
