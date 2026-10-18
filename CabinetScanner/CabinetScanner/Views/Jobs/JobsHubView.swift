import CabinetDesign
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

    /// The navigation stack, held explicitly.
    ///
    /// `navigationDestination(item:)` pushes on nil→value and pops on
    /// value→nil, but does NOT swap when the value changes from one job to
    /// another — which is exactly what happens when somebody scans one label
    /// and then the next, and it left the first job on screen. An explicit
    /// path describes the whole stack, so replacing it is one state change
    /// that SwiftUI applies as written.
    @State private var path = NavigationPath()
    @State private var scanningLabel = false

    private var isSearching: Bool { !search.trimmedQuery.isEmpty }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ScreenTitle("Jobs") {
                        BarIcon(glyph: .qr, label: "Scan a job label") { scanningLabel = true }
                    }
                    PaperSearchField(text: $search.query, prompt: "Sales order, customer, Shopify number")
                        .padding(.top, PaperSpace.m)

                    Group {
                        if isSearching {
                            JobSearchResults(viewModel: search)
                        } else {
                            ProductionBoard(viewModel: board)
                        }
                    }
                    .padding(.top, PaperSpace.l)
                }
                .screen()
                .padding(.bottom, 120)
            }
            .scrollDismissesKeyboard(.immediately)
            .refreshable {
                if !isSearching { await board.load() }
            }
            .paperRootScreen()
            // No `.id()` here. Forcing a new identity does make SwiftUI
            // rebuild the screen, but it tears the old one down mid-transition
            // and the replacement came up blank. JobDetailView follows its
            // `jobId` instead — see its `.task(id:)` — so a reused screen
            // reloads for the new job on its own.
            .navigationDestination(for: JobSearchResult.self) { result in
                JobDetailView(jobId: result.id, knownTitle: result.displayTitle, jobTitle: result.jobTitle)
            }
            .navigationDestination(for: ProductionJob.self) { job in
                JobDetailView(jobId: job.id, knownTitle: job.displayTitle, jobTitle: job.jobTitle)
            }
            // A deep link or a tapped notification. Only an id is known.
            .navigationDestination(for: LinkedJob.self) { linked in
                JobDetailView(jobId: linked.id)
            }
            // A scanned label that carries a sales order rather than an id.
            .navigationDestination(for: SalesOrderLookup.self) { lookup in
                JobLookupView(salesOrder: lookup.salesOrder, customer: "Sales order \(lookup.salesOrder)")
            }
            .fullScreenCover(isPresented: $scanningLabel) {
                JobLabelScannerView(
                    onFound: { target in
                        scanningLabel = false
                        open(target)
                    },
                    onCancel: { scanningLabel = false }
                )
            }
            .task { await board.load() }
        }
        // Attached to the STACK, not to its root content.
        //
        // On the root it never fired for a second scan: `.task` and
        // `.onChange` are tied to a view being in the hierarchy, and pushing
        // a detail screen takes the root out of it. So the first label opened
        // its job and every one after that did nothing, which is precisely
        // the scanning case this exists for.
        //
        // `initial: true` covers a link that arrived before this tab had ever
        // been opened.
        .onChange(of: router.pendingJobId, initial: true) { _, _ in
            openPendingJob()
        }
        // Every tab is alive from launch, so coming back to this one is when
        // the board refreshes, and when a link held through Settings opens.
        .onTabReturn {
            openPendingJob()
            if !isSearching { await board.load() }
        }
        .onResume {
            if !isSearching { await board.load() }
        }
    }

    /// Open what a scanned job label points at, replacing the stack as a
    /// deep link does, so backing out returns to the board.
    private func open(_ target: JobLabelTarget) {
        search.clear()
        switch target {
        case .jobId(let id):
            router.openJob(id)
        case .salesOrder(let number):
            path = NavigationPath()
            path.append(SalesOrderLookup(salesOrder: number))
        }
    }

    private func openPendingJob() {
        // A link that arrives before the device has its token stays pending:
        // the router has sent the person to Settings, which says a job is
        // waiting, and Save brings them back here to open it.
        guard Configuration.hasDeviceAPIToken, let id = router.consumeJob() else { return }

        // Searching and a pushed detail screen fight each other; clear the
        // field so the job is not opened on top of a result list.
        search.clear()

        // Replace the stack rather than appending. Scanning a second label
        // should land on that job, not bury it under the first — and backing
        // out should return to the board, not walk back through every label
        // handled this shift.
        path = NavigationPath()
        path.append(LinkedJob(id: id))
    }
}

/// A job reached by id alone — a scanned label, or a tapped notification.
/// Distinct from `JobSearchResult` and `ProductionJob` so the stack can tell
/// the three apart.
struct LinkedJob: Hashable {
    let id: String
}

/// A job reached by its sales order number, from a scanned label.
struct SalesOrderLookup: Hashable {
    let salesOrder: String
}
