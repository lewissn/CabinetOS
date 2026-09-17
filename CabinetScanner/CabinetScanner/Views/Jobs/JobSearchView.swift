import SwiftUI

// MARK: - Job Search
//
// The universal search screen. Finds a job by sales order, job number,
// Shopify order, customer PO, customer name, postcode or title — and says on
// every row how far the information can be trusted.

// MARK: - Job Search Results
//
// The results half of the Jobs tab. Rendered in place of the production board
// while there is something in the search field.

struct JobSearchResults: View {
    @ObservedObject var viewModel: JobSearchViewModel

    var body: some View {
        content
    }

    @ViewBuilder
    private var content: some View {
        if let error = viewModel.errorMessage {
            ContentUnavailableView {
                Label("Search Unavailable", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("Try Again") { viewModel.retry() }
                    .buttonStyle(.borderedProminent)
            }

        } else if viewModel.isQueryTooShort {
            ContentUnavailableView(
                "Keep typing",
                systemImage: "character.cursor.ibeam",
                description: Text("Enter at least two characters.")
            )

        } else if viewModel.isSearching && viewModel.results.isEmpty {
            // A skeleton rather than a spinner: the shape of the answer is
            // already known, so the list does not jump when it arrives.
            List(0..<5, id: \.self) { _ in
                SearchResultSkeleton()
            }
            .listStyle(.plain)
            .allowsHitTesting(false)

        } else if viewModel.showsEmptyResult {
            noResults

        } else {
            resultsList
        }
    }

    private var noResults: some View {
        ContentUnavailableView {
            Label("No Matches", systemImage: "magnifyingglass")
        } description: {
            VStack(spacing: 8) {
                Text("Nothing matched \u{201C}\(viewModel.trimmedQuery)\u{201D}.")
                // Explaining how the query was read turns a dead end into
                // something the user can act on.
                if let numeric = viewModel.interpretation?.numeric {
                    Text("Looked for the number \(numeric) in job, sales order, Shopify and PO references.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                } else if let postcode = viewModel.interpretation?.postcode {
                    Text("Looked for the postcode \(postcode).")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("Jobs only appear here once they have been imported or seen by a webhook.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var resultsList: some View {
        List {
            if !viewModel.results.isEmpty {
                Section {
                    ForEach(viewModel.results) { result in
                        NavigationLink(value: result) {
                            JobSearchResultRow(result: result)
                        }
                    }
                } header: {
                    Text("Jobs")
                }
            }

            if !viewModel.customers.isEmpty {
                Section {
                    ForEach(viewModel.customers) { customer in
                        CustomerRow(customer: customer)
                    }
                } header: {
                    Text("Customers in ShopVOX")
                } footer: {
                    Text("Live from ShopVOX. These are companies, not jobs.")
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - Result row

struct JobSearchResultRow: View {
    let result: JobSearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(result.displayTitle)
                    .font(.headline)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if let reference = result.primaryReference {
                    Text(reference)
                        .font(.subheadline.monospacedDigit())
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                }
            }

            if let title = result.jobTitle, title != result.displayTitle {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                DueDateLabel(isoDate: result.orderDueDate)

                if let postcode = result.customerPostcode {
                    Text(postcode)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                ProvenanceBadge(
                    source: result.dataSource,
                    isStale: result.isStale,
                    compact: true
                )
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Customer row

struct CustomerRow: View {
    let customer: ShopVoxCustomer

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(customer.name)
                .font(.headline)
                .lineLimit(1)

            HStack(spacing: 10) {
                if let city = customer.city {
                    Label(city, systemImage: "mappin.and.ellipse")
                }
                if let email = customer.email {
                    Label(email, systemImage: "envelope")
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Skeleton

struct SearchResultSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 4)
                .fill(.quaternary)
                .frame(width: 180, height: 15)
            RoundedRectangle(cornerRadius: 4)
                .fill(.quaternary)
                .frame(width: 120, height: 11)
        }
        .padding(.vertical, 8)
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}
