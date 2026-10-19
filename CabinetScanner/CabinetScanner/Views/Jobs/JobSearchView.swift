import CabinetDesign
import SwiftUI

// MARK: - Job Search
//
// The universal search screen. Finds a job by sales order, job number,
// Shopify order, customer PO, customer name, postcode or title — and says on
// every row how far the information can be trusted.

// MARK: - Job Search Results
//
// The results half of the Jobs tab (and of Today). Rendered in place of the
// board while there is something in the search field.

struct JobSearchResults: View {
    @ObservedObject var viewModel: JobSearchViewModel
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        if let error = viewModel.errorMessage {
            // A missing or refused token is fixed in Settings, so that's
            // where the button goes; "Try again" would fail the same way.
            if viewModel.errorNeedsSettings {
                PaperEmptyState("Search needs this device's access token", message: error, actionTitle: "Open Settings") {
                    router.selectedTab = .settings
                }
            } else {
                PaperEmptyState("Search isn't available", message: error, actionTitle: "Try again") {
                    viewModel.retry()
                }
            }

        } else if viewModel.isQueryTooShort {
            PaperEmptyState("Keep typing", message: "Enter at least two characters.")

        } else if viewModel.isSearching && viewModel.results.isEmpty {
            // A skeleton rather than a spinner: the shape of the answer is
            // already known, so the list does not jump when it arrives.
            VStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { _ in SearchResultSkeleton() }
            }
            .allowsHitTesting(false)

        } else if viewModel.showsEmptyResult {
            PaperEmptyState("No matches for \u{201C}\(viewModel.trimmedQuery)\u{201D}", message: noResultsHint)

        } else {
            resultsList
        }
    }

    /// Explaining how the query was read turns a dead end into something the
    /// user can act on.
    private var noResultsHint: String {
        if let numeric = viewModel.interpretation?.numeric {
            return "Looked for the number \(numeric) in job, sales order, Shopify and PO references."
        }
        if let postcode = viewModel.interpretation?.postcode {
            return "Looked for the postcode \(postcode)."
        }
        return "Jobs only appear here once they have been imported or seen by a webhook."
    }

    private var resultsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !viewModel.results.isEmpty {
                PaperSectionHeader("Jobs") {
                    Text(Format.count(viewModel.results.count, "result"))
                        .paperType(.footnote, numeric: true)
                        .foregroundStyle(PaperColor.tertiary)
                }
                ForEach(viewModel.results) { result in
                    NavigationLink(value: result) {
                        JobSearchResultRow(result: result)
                    }
                    .buttonStyle(.plain)
                }
            }

            if !viewModel.customers.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    PaperSectionHeader("Customers in ShopVOX")
                    ForEach(viewModel.customers) { customer in
                        CustomerRow(customer: customer)
                    }
                    Text("Live from ShopVOX. These are companies, not jobs.")
                        .paperType(.footnote)
                        .foregroundStyle(PaperColor.tertiary)
                        .padding(.top, PaperSpace.m)
                }
                .section(top: viewModel.results.isEmpty ? 0 : PaperSpace.section)
            }
        }
    }
}

// MARK: - Job row (search results and the board)

/// One job: the customer, its due date as a status, the reference and the
/// title, and where the record came from. List rows get no step track —
/// search results don't carry the steps.
struct JobRowContent: View {
    let title: String
    let reference: String?
    let subtitle: String?
    let due: (text: String, tone: Tone)?
    let detail: String?
    /// The shipping method, as a small outlined tag.
    var tag: String? = nil
    let source: JobDataSource
    let isStale: Bool

    var body: some View {
        RowContainer(verticalPadding: PaperSpace.l) {
            VStack(alignment: .leading, spacing: PaperSpace.xs) {
                HStack(alignment: .firstTextBaseline, spacing: PaperSpace.m) {
                    Text(title).paperType(.body).foregroundStyle(PaperColor.ink).lineLimit(1)
                    Spacer(minLength: PaperSpace.s)
                    if let due { StatusText(due.text, tone: due.tone).fixedSize() }
                }
                HStack(spacing: 6) {
                    if let reference { Code(reference) }
                    if let subtitle {
                        Text(reference == nil ? subtitle : "· \(subtitle)")
                            .paperType(.footnote)
                            .foregroundStyle(PaperColor.secondary)
                            .lineLimit(1)
                    }
                }
                HStack(spacing: PaperSpace.m) {
                    if let tag, !tag.isEmpty {
                        Text(tag)
                            .paperType(.caption)
                            .foregroundStyle(PaperColor.body)
                            .lineLimit(1)
                            .padding(.horizontal, PaperSpace.s)
                            .padding(.vertical, 2)
                            .overlay(Capsule().strokeBorder(PaperColor.border, lineWidth: 1))
                            .layoutPriority(1)
                    }
                    if let detail {
                        Text(detail).paperType(.caption).foregroundStyle(PaperColor.secondary).lineLimit(1)
                            .layoutPriority(-1)
                    }
                    Spacer(minLength: 0)
                    ProvenanceBadge(source: source, isStale: isStale, compact: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct JobSearchResultRow: View {
    let result: JobSearchResult

    var body: some View {
        JobRowContent(
            title: result.displayTitle,
            reference: result.primaryReference,
            subtitle: result.jobTitle.flatMap { $0 == result.displayTitle ? nil : $0 },
            due: DueLine.make(isoDate: result.orderDueDate),
            detail: result.customerPostcode,
            source: result.dataSource,
            isStale: result.isStale
        )
    }
}

// MARK: - Customer row

struct CustomerRow: View {
    let customer: ShopVoxCustomer

    var body: some View {
        RowContainer {
            VStack(alignment: .leading, spacing: 3) {
                Text(customer.name).paperType(.body).foregroundStyle(PaperColor.ink).lineLimit(1)
                let detail = [customer.city, customer.email].compactMap { $0 }.joined(separator: " · ")
                if !detail.isEmpty {
                    Text(detail).paperType(.footnote).foregroundStyle(PaperColor.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Skeleton

struct SearchResultSkeleton: View {
    var body: some View {
        RowContainer(verticalPadding: PaperSpace.l) {
            VStack(alignment: .leading, spacing: PaperSpace.s) {
                Capsule().fill(PaperColor.track).frame(width: 180, height: 12)
                Capsule().fill(PaperColor.track).frame(width: 120, height: 9)
                Capsule().fill(PaperColor.hairlineSoft).frame(width: 90, height: 9)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityHidden(true)
    }
}
