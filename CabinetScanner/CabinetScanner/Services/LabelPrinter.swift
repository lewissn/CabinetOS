import SwiftUI
import UIKit

// MARK: - Label printer
//
// Box labels go to a 4×6" thermal printer over AirPrint. Printing used to mean
// a share sheet, then Print, then the printer, then the paper size, every
// time. Now the printer is chosen once and remembered on the device, and each
// label after that goes straight to it with 4×6" already selected.
//
// Labels are drawn as vector PDF pages at exactly 4×6", so the printer's own
// driver rasterises them at its resolution and type stays crisp.

@MainActor
final class LabelPrinter: NSObject, UIPrintInteractionControllerDelegate {
    static let shared = LabelPrinter()

    /// 4 × 6 inches in points.
    nonisolated static let pageSize = CGSize(width: 288, height: 432)

    enum Outcome {
        case printed(printerName: String)
        /// Printed, but the printer didn't offer the label size this time,
        /// so it went on whatever it did offer (usually A4).
        case printedOnOtherPaper(printerName: String, paper: String)
        case cancelled
        case failed(String)
    }

    private let urlKey = "labelPrinter.url"
    private let nameKey = "labelPrinter.name"

    /// The remembered printer's name, for Settings and the confirmation toast.
    var savedPrinterName: String? { UserDefaults.standard.string(forKey: nameKey) }
    var hasSavedPrinter: Bool { UserDefaults.standard.url(forKey: urlKey) != nil }

    // MARK: Printing

    /// Print one page per label. With a remembered printer this is a single
    /// tap; the first time, it asks which printer to use and remembers it.
    func print(_ pages: [AnyView], jobName: String) async -> Outcome {
        guard let pdf = Self.pdf(for: pages) else { return .failed("The label couldn't be drawn.") }

        if !hasSavedPrinter {
            guard await choosePrinter() else { return .cancelled }
        }
        guard let url = UserDefaults.standard.url(forKey: urlKey) else { return .cancelled }

        let printer = savedPrinter(for: url)
        let name = savedPrinterName ?? printer.displayName

        // Ask the printer what it has loaded before every label. A printer
        // rebuilt from its address and never asked has no paper list of its
        // own, and iOS fills in A4 and Letter: that is how labels went to A4
        // after a few good prints.
        guard await contact(printer) else {
            return .failed("\(name) didn't answer. Check it's switched on and on the same Wi-Fi, then print again.")
        }

        let controller = makeController(pdf: pdf, jobName: jobName)
        Self.lastChoice = nil
        return await withCheckedContinuation { continuation in
            controller.print(to: printer) { _, completed, error in
                if let error {
                    continuation.resume(returning: .failed("\(name) didn't take the label: \(error.localizedDescription)"))
                } else if !completed {
                    continuation.resume(returning: .cancelled)
                } else if let choice = Self.lastChoice, !choice.isLabel {
                    continuation.resume(returning: .printedOnOtherPaper(printerName: name, paper: choice.name))
                } else {
                    continuation.resume(returning: .printed(printerName: name))
                }
            }
        }
    }

    /// The full system print sheet, with 4×6" preselected, for a different
    /// printer or more copies.
    func printWithOptions(_ pages: [AnyView], jobName: String) async -> Outcome {
        guard let pdf = Self.pdf(for: pages) else { return .failed("The label couldn't be drawn.") }
        let controller = makeController(pdf: pdf, jobName: jobName)
        return await withCheckedContinuation { continuation in
            let completion: UIPrintInteractionController.CompletionHandler = { controller, completed, error in
                if let error {
                    continuation.resume(returning: .failed(error.localizedDescription))
                } else {
                    // Whatever paper was picked here is the right one for
                    // this printer: a plain tap uses it from now on.
                    if completed { LabelPrinter.rememberPaper(controller.printPaper) }
                    continuation.resume(returning: completed ? .printed(printerName: "the printer") : .cancelled)
                }
            }
            if UIDevice.current.userInterfaceIdiom == .pad, let (view, rect) = Self.anchor() {
                controller.present(from: rect, in: view, animated: true, completionHandler: completion)
            } else {
                controller.present(animated: true, completionHandler: completion)
            }
        }
    }

    // MARK: The printer itself

    /// One printer object for the saved address, kept between labels rather
    /// than made afresh each time, so what it has said about its paper sticks.
    private var cachedPrinter: UIPrinter?

    private func savedPrinter(for url: URL) -> UIPrinter {
        if let cachedPrinter, cachedPrinter.url == url { return cachedPrinter }
        let printer = UIPrinter(url: url)
        cachedPrinter = printer
        return printer
    }

    /// Asks the printer whether it's there and what it has loaded.
    private func contact(_ printer: UIPrinter) async -> Bool {
        await withCheckedContinuation { continuation in
            printer.contactPrinter { available in continuation.resume(returning: available) }
        }
    }

    // MARK: Choosing the printer

    /// Ask which printer to use and remember it. Returns false if cancelled.
    @discardableResult
    func choosePrinter() async -> Bool {
        let initial = UserDefaults.standard.url(forKey: urlKey).map { UIPrinter(url: $0) }
        let picker = UIPrinterPickerController(initiallySelectedPrinter: initial)
        let chosen: UIPrinter? = await withCheckedContinuation { continuation in
            let completion: UIPrinterPickerController.CompletionHandler = { picker, selected, _ in
                continuation.resume(returning: selected ? picker.selectedPrinter : nil)
            }
            if UIDevice.current.userInterfaceIdiom == .pad, let (view, rect) = Self.anchor() {
                picker.present(from: rect, in: view, animated: true, completionHandler: completion)
            } else {
                picker.present(animated: true, completionHandler: completion)
            }
        }
        guard let chosen else { return false }
        UserDefaults.standard.set(chosen.url, forKey: urlKey)
        UserDefaults.standard.set(chosen.displayName, forKey: nameKey)
        return true
    }

    func forgetPrinter() {
        UserDefaults.standard.removeObject(forKey: urlKey)
        UserDefaults.standard.removeObject(forKey: nameKey)
        UserDefaults.standard.removeObject(forKey: Self.paperKey)
    }

    // MARK: Paper

    /// Pick the 4×6" label from whatever the printer offers.
    ///
    /// Not `UIPrintPaper.bestPaper`: that only accepts a paper whose
    /// *printable* area holds the whole page, and a thermal printer's 4×6"
    /// label has small margins, so it passed over the label and chose the
    /// next paper that fitted — A4 — and every label printed enlarged across
    /// two. This goes by the paper's size instead: the paper last chosen by
    /// hand in the full print sheet, otherwise the one closest to 4×6".
    nonisolated func printInteractionController(_ controller: UIPrintInteractionController,
                                                choosePaper paperList: [UIPrintPaper]) -> UIPrintPaper {
        let sizes = paperList.map(\.paperSize)
        if let index = LabelPrinter.paperIndex(in: sizes, preferring: LabelPrinter.rememberedPaperSize) {
            LabelPrinter.lastChoice = (true, LabelPrinter.describe(sizes[index]))
            return paperList[index]
        }
        // No label size on offer this time. Print anyway, but say so
        // afterwards rather than let an A4 label pass as a good one.
        let fallback = UIPrintPaper.bestPaper(forPageSize: LabelPrinter.pageSize, withPapersFrom: paperList)
        LabelPrinter.lastChoice = (false, LabelPrinter.describe(fallback.paperSize))
        return fallback
    }

    /// Whether the last job's paper was the label, and what it was. Written
    /// by the paper choice, read when the job completes.
    nonisolated(unsafe) static var lastChoice: (isLabel: Bool, name: String)?

    /// "A4", "Letter", "4 × 6 in", or the size in millimetres.
    nonisolated static func describe(_ size: CGSize) -> String {
        let (w, h) = (min(size.width, size.height), max(size.width, size.height))
        func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(w - a) < 6 && abs(h - b) < 6 }
        if near(595, 842) { return "A4" }
        if near(612, 792) { return "Letter" }
        if near(288, 432) { return "4 × 6 in" }
        return "\(Int((w / 72 * 25.4).rounded())) × \(Int((h / 72 * 25.4).rounded())) mm"
    }

    /// The paper to use from a printer's list of paper sizes: the remembered
    /// one if the printer has it, otherwise the closest to 4×6" (either way
    /// round, within half an inch). Nil when nothing is near.
    nonisolated static func paperIndex(in sizes: [CGSize], preferring remembered: CGSize?) -> Int? {
        func distance(_ a: CGSize, _ b: CGSize) -> CGFloat {
            let straight = abs(a.width - b.width) + abs(a.height - b.height)
            let turned = abs(a.width - b.height) + abs(a.height - b.width)
            return min(straight, turned)
        }
        if let remembered,
           let match = sizes.indices.min(by: { distance(sizes[$0], remembered) < distance(sizes[$1], remembered) }),
           distance(sizes[match], remembered) <= 4 {
            return match
        }
        guard let nearest = sizes.indices.min(by: { distance(sizes[$0], pageSize) < distance(sizes[$1], pageSize) }),
              distance(sizes[nearest], pageSize) <= 36 else { return nil }
        return nearest
    }

    /// The paper size chosen in the full print sheet, kept so a plain tap
    /// prints on the same paper next time.
    private static let paperKey = "labelPrinter.paperSize"

    nonisolated static var rememberedPaperSize: CGSize? {
        guard let stored = UserDefaults.standard.string(forKey: paperKey) else { return nil }
        let size = NSCoder.cgSize(for: stored)
        return size == .zero ? nil : size
    }

    /// Only ever a label-sized paper: an A4 left selected in the sheet must
    /// not become what every plain tap prints on.
    private static func rememberPaper(_ paper: UIPrintPaper?) {
        guard let paper, paperIndex(in: [paper.paperSize], preferring: nil) != nil else { return }
        UserDefaults.standard.set(NSCoder.string(for: paper.paperSize), forKey: paperKey)
    }

    // MARK: Helpers

    private func makeController(pdf: Data, jobName: String) -> UIPrintInteractionController {
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .grayscale
        info.orientation = .portrait
        info.jobName = jobName
        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = pdf
        controller.delegate = self
        return controller
    }

    /// A vector PDF with one 4×6" page per label.
    static func pdf(for pages: [AnyView]) -> Data? {
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
        for page in pages {
            let renderer = ImageRenderer(content: page.frame(width: pageSize.width, height: pageSize.height))
            renderer.proposedSize = ProposedViewSize(pageSize)
            renderer.render { _, draw in
                context.beginPDFPage(nil)
                draw(context)
                context.endPDFPage()
            }
        }
        context.closePDF()
        return data as Data
    }

    /// The old route, kept for printers the app can't reach directly: the
    /// share sheet with the label as a PDF.
    static func share(_ pages: [AnyView], fileName: String) {
        guard let pdf = pdf(for: pages) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(fileName).pdf")
        try? pdf.write(to: url, options: .atomic)
        guard let (view, rect) = anchor(), let root = view.window?.rootViewController else { return }
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = view
        activity.popoverPresentationController?.sourceRect = rect
        (root.presentedViewController ?? root).present(activity, animated: true)
    }

    private static func anchor() -> (UIView, CGRect)? {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let view = scene.windows.first(where: \.isKeyWindow)?.rootViewController?.view
                ?? scene.windows.first?.rootViewController?.view else { return nil }
        return (view, CGRect(x: view.bounds.midX, y: view.bounds.maxY - 120, width: 1, height: 1))
    }
}

extension LabelPrinter.Outcome {
    /// What to say afterwards. Nil when the person cancelled.
    var message: String? {
        switch self {
        case .printed(let name): "Label sent to \(name)"
        case .printedOnOtherPaper(let name, let paper):
            "\(name) printed it on \(paper): it didn't offer the 4 × 6 label this time. Hold Print and choose the label."
        case .cancelled: nil
        case .failed(let message): message
        }
    }
}
