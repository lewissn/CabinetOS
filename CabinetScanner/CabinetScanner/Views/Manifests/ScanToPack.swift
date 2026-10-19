import CabinetDesign
import SwiftUI

// MARK: - Scan to pack
//
// From Packing, one scan of a job label goes straight to that job's open
// courier consignment and its boxes. With none open, the raise sheet comes up
// already filled in, and raising it carries on into packing. It replaces
// "search the job, open it, find the button, raise, pack" at the bench.
//
// Everything here reuses the job page's own pieces: the label parser, the
// job index lookup, JobConsignmentViewModel and its raise sheet.

struct PackJobScreen: View {
    let target: JobLabelTarget

    private enum LoadState {
        case finding
        case found(id: String, title: String, reference: String?)
        case choices([JobSearchResult])
        case failed(String)
    }

    @State private var state: LoadState = .finding
    private let service = JobIndexService()

    var body: some View {
        Group {
            switch state {
            case .found(let id, let title, let reference):
                JobConsignmentScope(jobId: id) {
                    PackJobContent(title: title, reference: reference)
                }
                .id(id)
            case .finding:
                frame { LoadingLine("Finding the job").section(top: PaperSpace.xxl) }
            case .choices(let results):
                frame {
                    if results.isEmpty {
                        PaperEmptyState("Not in the job index",
                                        message: "\(label) hasn't been imported or seen by a webhook yet, so it can't be packed from here.")
                            .section(top: PaperSpace.xxl)
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            PaperSectionHeader("More than one job has this number")
                            ForEach(results) { result in
                                Button {
                                    state = .found(id: result.id, title: result.displayTitle, reference: result.salesOrderNumber.map { "SO \($0)" })
                                } label: {
                                    JobSearchResultRow(result: result)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .section(top: PaperSpace.xxl)
                    }
                }
            case .failed(let message):
                frame {
                    PaperEmptyState("The job didn't load", message: message, actionTitle: "Try again") {
                        Task { await find() }
                    }
                    .section(top: PaperSpace.xxl)
                }
            }
        }
        .task { await find() }
    }

    private var label: String {
        switch target {
        case .salesOrder(let number): "SO \(number)"
        case .jobId: "This job"
        }
    }

    private func frame<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let body = content()
        return PushedScreen(back: "Packing") {
            VStack(alignment: .leading, spacing: 0) {
                Code(label, color: PaperColor.ink, size: 14).padding(.top, PaperSpace.s)
                body
            }
            .screen()
        }
    }

    private func find() async {
        if case .found = state { return }
        state = .finding
        switch target {
        case .jobId(let id):
            state = .found(id: id, title: "This job", reference: nil)
        case .salesOrder(let number):
            do {
                let response = try await service.search(query: number)
                let exact = response.results.filter { $0.salesOrderNumber == number }
                if exact.count == 1, let only = exact.first {
                    state = .found(id: only.id, title: only.displayTitle, reference: "SO \(number)")
                } else {
                    state = .choices(exact)
                }
            } catch {
                state = .failed((error as? JobIndexError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }
}

/// The job, found: its open consignment's boxes, or the way to raise one.
private struct PackJobContent: View {
    let title: String
    let reference: String?

    @EnvironmentObject private var viewModel: JobConsignmentViewModel
    @State private var showingRaise = false
    @State private var offeredRaise = false

    var body: some View {
        if let open = viewModel.openConsignment {
            ManualManifestScreen(manifest: open.manualManifest(jobId: viewModel.jobId), backLabel: "Packing")
                .id(open.id)
        } else {
            PushedScreen(back: "Packing") {
                VStack(alignment: .leading, spacing: PaperSpace.s) {
                    if let reference { Code(reference, color: PaperColor.ink, size: 14) }
                    Text(title)
                        .paperType(.largeTitle)
                        .foregroundStyle(PaperColor.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    if viewModel.info == nil {
                        if let error = viewModel.errorMessage {
                            Notice(text: error, tone: .held).section(top: PaperSpace.xxl)
                        } else {
                            LoadingLine("Checking for an open consignment").section(top: PaperSpace.xxl)
                        }
                    } else {
                        Text("No courier consignment is open for this job.")
                            .paperType(.subhead)
                            .foregroundStyle(PaperColor.secondary)
                            .section(top: PaperSpace.xxl)
                        Button {
                            showingRaise = true
                        } label: {
                            Label { Text("Raise courier consignment") } icon: { PaperIcon(.truck, size: 18) }
                        }
                        .buttonStyle(.paperPill(.accent, .floor, fullWidth: true))
                        .padding(.top, PaperSpace.l)
                    }
                }
                .screen()
            }
            .sheet(isPresented: $showingRaise) {
                // Raising sets the open consignment, and this screen becomes
                // its boxes.
                RaiseConsignmentSheet { _ in showingRaise = false }
                    .environmentObject(viewModel)
                    .paperSheet(detents: [.medium, .large])
            }
            // The reason for scanning was to pack it: offer the raise sheet
            // once, as soon as it's known there's nothing open.
            .onChange(of: viewModel.info != nil) { _, loaded in
                guard loaded, !offeredRaise, viewModel.openConsignment == nil else { return }
                offeredRaise = true
                showingRaise = true
            }
        }
    }
}
