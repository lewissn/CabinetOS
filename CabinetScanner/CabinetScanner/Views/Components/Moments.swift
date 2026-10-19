import AVFoundation
import CabinetDesign
import SwiftUI
import UIKit

// MARK: - Moments
//
// Three points in the bench's day get a little ceremony, because each ends a
// piece of physical work: a box sealed, a consignment finished, a label
// found. Each is short, says what happened in words as well as motion, and
// never stands between someone and the next thing. With Reduce Motion on they
// appear complete.

// MARK: - The seal: a ring that closes, then a check

/// A ring that draws itself closed, then a check inside it. The mark for a
/// box sealed and a consignment finished.
struct SealMark: View {
    var size: CGFloat = 20
    var colour: Color = PaperColor.accent
    var checkColour: Color = PaperColor.ink
    /// Draw on appear; false shows it finished.
    var animated = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ring: CGFloat = 0
    @State private var check: CGFloat = 0

    var body: some View {
        let line = min(max(1.6, size / 11), 5)
        ZStack {
            Circle()
                .trim(from: 0, to: ring)
                .stroke(colour, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            CheckShape()
                .trim(from: 0, to: check)
                .stroke(checkColour, style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))
                .padding(size * 0.28)
        }
        .frame(width: size, height: size)
        .onAppear {
            guard animated, !reduceMotion else {
                ring = 1; check = 1
                return
            }
            withAnimation(.easeOut(duration: 0.42)) { ring = 1 }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.72).delay(0.32)) { check = 1 }
        }
        .accessibilityHidden(true)
    }
}

/// A check, drawn left to right so trimming it reads as a pen stroke.
struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.04))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY - rect.height * 0.12))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.14))
        return p
    }
}

// MARK: - Boxes just sealed

/// Boxes closed in the last few seconds, so their row in the list can draw
/// its seal as the list comes back into view.
@MainActor
final class SealCenter: ObservableObject {
    static let shared = SealCenter()
    @Published private var sealed: [String: Date] = [:]

    func mark(_ boxId: String) {
        sealed[boxId] = .now
    }

    func isFresh(_ boxId: String) -> Bool {
        guard let at = sealed[boxId] else { return false }
        return Date.now.timeIntervalSince(at) < 6
    }
}

/// The mark on a box row: drawn once for a box just sealed, nothing
/// otherwise (the "Closed" status already says it).
struct FreshSeal: View {
    let boxId: String
    @ObservedObject private var center = SealCenter.shared

    var body: some View {
        if center.isFresh(boxId) {
            SealMark(size: 18)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
        }
    }
}

// MARK: - Haptics

extension HapticService {
    /// A box sealed: a soft press, then a firm click, like a lid going down.
    static func seal() {
        let soft = UIImpactFeedbackGenerator(style: .soft)
        let rigid = UIImpactFeedbackGenerator(style: .rigid)
        soft.prepare(); rigid.prepare()
        soft.impactOccurred(intensity: 0.7)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.11) {
            rigid.impactOccurred(intensity: 0.9)
        }
    }

    /// One box landing on the stack as a consignment folds up.
    static func land(_ intensity: CGFloat = 0.55) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: intensity)
    }
}

// MARK: - A consignment finished

/// What to say when a consignment is finished.
struct FinishMoment: Identifiable {
    let id = UUID()
    let name: String
    /// Known on the consignment's own screen; nil from the job page, where
    /// the stack is only a picture and no count is claimed.
    let boxCount: Int?
    /// ShopVOX accepted Pack & Wrap and Despatch.
    let movedJobOn: Bool
    var onDone: (() -> Void)?
}

@MainActor
final class MomentCenter: ObservableObject {
    static let shared = MomentCenter()
    @Published var finish: FinishMoment?

    func play(_ moment: FinishMoment) { finish = moment }

    func end() {
        let done = finish?.onDone
        finish = nil
        done?()
    }
}

/// The boxes slide together and stack, the stack closes into a seal, and the
/// line underneath says what happened. About two seconds; a tap ends it.
struct FinishMomentOverlay: View {
    @ObservedObject var center = MomentCenter.shared

    var body: some View {
        ZStack {
            if let moment = center.finish {
                FinishMomentView(moment: moment) { center.end() }
                    .id(moment.id)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: center.finish?.id)
    }
}

private struct FinishMomentView: View {
    let moment: FinishMoment
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 0 spread out · 1 stacked · 2 sealed
    @State private var phase = 0

    private var shown: Int { min(max(moment.boxCount ?? 3, 1), 8) }

    var body: some View {
        ZStack {
            PaperColor.paper.ignoresSafeArea()

            VStack(spacing: PaperSpace.xxl) {
                ZStack {
                    ForEach(0..<shown, id: \.self) { index in
                        box(index)
                    }
                    if phase == 2 {
                        SealMark(size: 96, colour: PaperColor.accent, checkColour: PaperColor.ink, animated: !reduceMotion)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                }
                .frame(height: 110)

                VStack(spacing: PaperSpace.xs) {
                    Text("Consignment finished")
                        .paperType(.title)
                        .foregroundStyle(PaperColor.ink)
                    Text(detail)
                        .paperType(.subhead, numeric: true)
                        .foregroundStyle(PaperColor.secondary)
                        .multilineTextAlignment(.center)
                    if moment.movedJobOn {
                        Text("Pack & Wrap and Despatch completed in ShopVOX")
                            .paperType(.footnote)
                            .foregroundStyle(PaperColor.accentInk)
                            .padding(.top, PaperSpace.xs)
                    }
                }
                .opacity(phase == 2 ? 1 : 0)
                .offset(y: phase == 2 ? 0 : 8)
                .paperMargins()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onDone() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isModal)
        .task { await run() }
    }

    private var detail: String {
        if let n = moment.boxCount { return "\(moment.name) · \(Format.count(n, "box", "boxes"))" }
        return moment.name
    }

    /// Spread out, each box sits on its own spot; stacked, they settle into
    /// one pile with a slight offset each; sealed, the pile gives way to the
    /// mark.
    private func box(_ index: Int) -> some View {
        let spacing: CGFloat = 40
        let spreadX = (CGFloat(index) - CGFloat(shown - 1) / 2) * spacing
        let stackY = -CGFloat(index) * 5
        return RoundedRectangle(cornerRadius: 7)
            .fill(index == shown - 1 ? PaperColor.accent : PaperColor.surface)
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(PaperColor.borderStrong, lineWidth: 1.2))
            .frame(width: 34, height: 28)
            .offset(x: phase == 0 ? spreadX : 0, y: phase == 0 ? 0 : stackY)
            .scaleEffect(phase == 2 ? 0.6 : 1)
            .opacity(phase == 2 ? 0 : 1)
            .animation(reduceMotion ? nil
                       : .spring(response: 0.42, dampingFraction: 0.78).delay(Double(index) * 0.07),
                       value: phase)
    }

    private func run() async {
        if reduceMotion {
            phase = 2
            HapticService.success()
            try? await Task.sleep(for: .seconds(1.6))
            onDone()
            return
        }
        try? await Task.sleep(for: .seconds(0.25))
        phase = 1
        // A light tick as each box lands, rising slightly towards the top.
        for index in 0..<shown {
            try? await Task.sleep(for: .seconds(index == 0 ? 0.3 : 0.07))
            HapticService.land(0.45 + 0.4 * CGFloat(index) / CGFloat(max(shown - 1, 1)))
        }
        try? await Task.sleep(for: .seconds(0.3))
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { phase = 2 }
        HapticService.success()
        try? await Task.sleep(for: .seconds(1.7))
        onDone()
    }
}

// MARK: - A label found: corners that snap onto it

/// Converts where Vision found a code into the camera preview's own
/// coordinates, so the scan corners can close on the label itself.
@MainActor
final class PreviewGeometry {
    weak var layer: AVCaptureVideoPreviewLayer?

    /// `box` is Vision's: normalised, origin bottom-left, in the camera's
    /// unrotated frame. The preview layer works in metadata coordinates,
    /// which are the same frame with the origin top-left.
    func rect(forVisionBox box: CGRect) -> CGRect? {
        guard let layer, !box.isEmpty else { return nil }
        let metadata = CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
        let rect = layer.layerRectConverted(fromMetadataOutputRect: metadata)
        // Anything implausible falls back to closing the window in place.
        guard rect.width > 16, rect.height > 16, layer.bounds.insetBy(dx: -20, dy: -20).contains(rect) else { return nil }
        return rect
    }
}

/// The four corner brackets of the scan window, as a shape so a change of
/// size or position animates smoothly.
struct CornersShape: Shape {
    var length: CGFloat

    var animatableData: CGFloat {
        get { length }
        set { length = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let l = min(length, rect.width / 2, rect.height / 2)
        let (x0, y0, x1, y1) = (rect.minX, rect.minY, rect.maxX, rect.maxY)
        var p = Path()
        p.move(to: CGPoint(x: x0, y: y0 + l)); p.addLine(to: CGPoint(x: x0, y: y0)); p.addLine(to: CGPoint(x: x0 + l, y: y0))
        p.move(to: CGPoint(x: x1 - l, y: y0)); p.addLine(to: CGPoint(x: x1, y: y0)); p.addLine(to: CGPoint(x: x1, y: y0 + l))
        p.move(to: CGPoint(x: x1, y: y1 - l)); p.addLine(to: CGPoint(x: x1, y: y1)); p.addLine(to: CGPoint(x: x1 - l, y: y1))
        p.move(to: CGPoint(x: x0 + l, y: y1)); p.addLine(to: CGPoint(x: x0, y: y1)); p.addLine(to: CGPoint(x: x0, y: y1 - l))
        return p
    }
}
