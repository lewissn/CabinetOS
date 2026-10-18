import CabinetDesign
import SwiftUI
import PDFKit

// MARK: - Proof Viewer
//
// Shows the artwork attached to a job. Confirmed against the live account:
// these are PDFs, typically 50–250KB, and 566 of the 602 indexed jobs have one.
//
// Fetched through the Ops server rather than from ShopVOX directly. The
// ShopVOX asset URLs are public and unsigned — anyone holding one can read a
// customer's artwork, for ever — so going via Ops puts the same credential in
// front of the proof as in front of the job it belongs to. "Open outside" and
// sharing still use the direct URL, because a credential cannot travel into
// Safari or into the share sheet.
//
// PDFKit rather than a web view: it gives pinch zoom, pan, page navigation and
// text selection for free, renders vector artwork crisply at any zoom, and
// does not execute anything in the document.
//
// The wording is deliberate throughout. ShopVOX exposes a *current* proof and
// publishes no approval state, so nothing here says "approved" or "final".

struct ProofViewerView: View {
    let jobId: String
    let jobTitle: String
    var label: String = "Current proof"
    /// The ShopVOX address, for opening or sharing outside the app.
    var externalURL: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var state: LoadState = .loading
    @State private var downloadedFile: URL?

    private let service = JobIndexService()

    enum LoadState {
        case loading
        case loaded(PDFDocument)
        /// Fetched, but not something PDFKit can render.
        case notAPdf(Data)
        /// ShopVOX has no proof on this job. Ordinary, not a fault.
        case noProof(String)
        case failed(String)
    }

    private var url: URL? {
        guard let externalURL else { return nil }
        return URL(string: externalURL)
    }

    var body: some View {
        VStack(spacing: 0) {
            PaperTopBar(.close, title: label, onLeading: { dismiss() }) {
                HStack(spacing: 0) {
                    // Saved to a file first, so the share sheet offers
                    // printing, Files and AirDrop rather than only a link
                    // somebody else would have to be able to open.
                    if let downloadedFile {
                        ShareLink(item: downloadedFile) {
                            PaperIcon(.arrowUp, size: 20)
                                .frame(width: PaperSpace.tap, height: PaperSpace.tap)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Share")
                    }
                    if let url {
                        // The fallback when PDFKit cannot render the file,
                        // and the route to a browser.
                        BarIcon(glyph: .arrowRight, label: "Open outside the app") { openURL(url) }
                    }
                }
            }
            .screen()
            .padding(.top, PaperSpace.s)

            content
        }
        .paperBackground()
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            VStack {
                LoadingLine("Loading the artwork")
                Spacer()
            }
            .screen()

        case .loaded(let document):
            PDFDocumentView(document: document)
                .ignoresSafeArea(edges: .bottom)

        case .notAPdf:
            message("This file can't be shown here", "The artwork isn't a PDF, so it can't be displayed in the app.",
                    action: url.map { u in ("Open it outside the app", { openURL(u) }) })

        case .noProof(let text):
            // An absent proof is not an error and is not offered a retry.
            message("No proof yet", text, action: nil)

        case .failed(let text):
            VStack(alignment: .leading, spacing: 0) {
                PaperEmptyState("The artwork didn't load", message: text, actionTitle: "Try again") {
                    Task { await load() }
                }
                if let url {
                    Button("Open it outside the app") { openURL(url) }
                        .buttonStyle(.paperText(PaperColor.ink, .subhead, weight: .medium))
                }
                Spacer()
            }
            .screen()
        }
    }

    private func message(_ title: String, _ text: String, action: (String, () -> Void)?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PaperEmptyState(title, message: text, actionTitle: action?.0, action: action?.1)
            Spacer()
        }
        .screen()
    }

    private func load() async {
        state = .loading

        let request: URLRequest
        do {
            request = try service.proofRequest(jobId: jobId)
        } catch {
            state = .failed(
                (error as? JobIndexError)?.errorDescription ?? error.localizedDescription
            )
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                state = .failed("The server did not answer properly.")
                return
            }

            if !(200...299).contains(http.statusCode) {
                state = describe(status: http.statusCode, body: data)
                return
            }

            if let document = PDFDocument(data: data) {
                state = .loaded(document)
                // Written to disk so the share sheet can offer it as a file.
                downloadedFile = try? write(data)
            } else {
                state = .notAPdf(data)
            }
        } catch {
            state = .failed("The file could not be downloaded. \(error.localizedDescription)")
        }
    }

    /// The server sends a reason with every refusal; use its words.
    private func describe(status: Int, body: Data) -> LoadState {
        struct Body: Decodable {
            let error: String?
            let reason: String?
        }

        let decoded = try? JSONDecoder().decode(Body.self, from: body)
        let message = decoded?.error

        if decoded?.reason == "no_proof" {
            return .noProof(message ?? "This job has no proof in ShopVOX.")
        }

        switch status {
        case 401, 403:
            return .failed(message ?? "This device is not allowed to open that file.")
        case 404:
            return .noProof(message ?? "That proof is no longer in ShopVOX.")
        default:
            return .failed(message ?? "The server returned an error (\(status)).")
        }
    }

    /// A temporary copy, named after the job so a shared file is identifiable.
    private func write(_ data: Data) throws -> URL {
        let safeName = jobTitle
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeName.isEmpty ? "proof" : safeName).pdf")

        try data.write(to: url, options: .atomic)
        return url
    }
}

// MARK: - PDFKit bridge

private struct PDFDocumentView: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = document
        // Fit the page on open, then let the reader zoom in as far as useful —
        // these are measured plans, so the detail matters.
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.maxScaleFactor = 8
        view.minScaleFactor = view.scaleFactorForSizeToFit
        view.backgroundColor = UIColor(PaperColor.segment)
        view.usePageViewController(false)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document !== document {
            view.document = document
            view.scaleFactor = view.scaleFactorForSizeToFit
        }
    }
}
