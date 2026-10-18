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

        let printer = UIPrinter(url: url)
        let controller = makeController(pdf: pdf, jobName: jobName)
        let name = savedPrinterName ?? printer.displayName
        return await withCheckedContinuation { continuation in
            controller.print(to: printer) { _, completed, error in
                if let error {
                    continuation.resume(returning: .failed("\(name) didn't take the label: \(error.localizedDescription)"))
                } else {
                    continuation.resume(returning: completed ? .printed(printerName: name) : .cancelled)
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
            let completion: UIPrintInteractionController.CompletionHandler = { _, completed, error in
                if let error {
                    continuation.resume(returning: .failed(error.localizedDescription))
                } else {
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
    }

    // MARK: Paper

    /// Pick the 4×6" label from whatever the printer offers.
    nonisolated func printInteractionController(_ controller: UIPrintInteractionController,
                                                choosePaper paperList: [UIPrintPaper]) -> UIPrintPaper {
        UIPrintPaper.bestPaper(forPageSize: LabelPrinter.pageSize, withPapersFrom: paperList)
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
        case .cancelled: nil
        case .failed(let message): message
        }
    }
}
