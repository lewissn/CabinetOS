import CabinetDesign
import SwiftUI
import UIKit

// MARK: - Shared design pieces
//
// The app-side half of the CabinetOS look, on top of the CabinetDesign
// package. Most of it comes from the concept app's Shared.swift, adapted to
// real data: nothing here invents a value, and an unknown one shows "–".

// MARK: - Tone: Cabinet Lab's status meanings

// The palette: green means done; amber is the brand and means in progress;
// ember (brick red) means act soon; red means held up or wrong.
enum Tone {
    case done       // green: done, packed, despatched
    case progress   // amber: ours and in progress, or paused
    case soon       // ember: act soon
    case held       // red: held up, late, a wrong scan
    case customer   // blue: the customer's move
    case neutral

    var color: Color {
        switch self {
        case .done: PaperColor.success
        case .progress: PaperColor.accent
        case .soon: PaperColor.ember
        case .held: PaperColor.danger
        case .customer: PaperColor.info
        case .neutral: PaperColor.dot
        }
    }

    /// For text: amber never carries words, so progress text is body ink.
    var textColor: Color {
        switch self {
        case .done: PaperColor.success
        case .progress, .neutral: PaperColor.body
        case .soon: PaperColor.ember
        case .held: PaperColor.danger
        case .customer: PaperColor.info
        }
    }

    /// For an icon beside text: amber icons use the readable amber ink.
    var iconColor: Color {
        switch self {
        case .progress: PaperColor.accentInk
        case .neutral: PaperColor.secondary
        default: textColor
        }
    }

    var soft: Color {
        switch self {
        case .done: PaperColor.successSoft
        case .progress: PaperColor.accentSoft
        case .soon: PaperColor.emberSoft
        case .held: PaperColor.dangerSoft
        case .customer: PaperColor.infoSoft
        case .neutral: PaperColor.segment
        }
    }
}

/// A status said once: a dot and words.
struct StatusText: View {
    let text: String
    let tone: Tone
    var style: PaperType = .footnote
    var lineLimit: Int? = 1

    init(_ text: String, tone: Tone, style: PaperType = .footnote, lineLimit: Int? = 1) {
        self.text = text
        self.tone = tone
        self.style = style
        self.lineLimit = lineLimit
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle().fill(tone.color).frame(width: 7, height: 7)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
            Text(text).paperType(style, numeric: true).foregroundStyle(tone.textColor).lineLimit(lineLimit)
                .fixedSize(horizontal: false, vertical: lineLimit == nil)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Job refs and panel codes in a fixed-width face.
struct Code: View {
    let text: String
    var color: Color = PaperColor.secondary
    var size: CGFloat = 13

    init(_ text: String, color: Color = PaperColor.secondary, size: CGFloat = 13) {
        self.text = text
        self.color = color
        self.size = size
    }

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .medium, design: .monospaced))
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

// MARK: - Notice: the one tinted surface

struct Notice: View {
    let text: String
    let tone: Tone
    var glyph: PaperGlyph = .alert
    var action: String?
    var onAction: () -> Void = {}

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: PaperSpace.m) {
            PaperIcon(glyph, size: 15, lineWidth: 2, color: tone.iconColor)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
            Text(text)
                .paperType(.subhead, numeric: true)
                .foregroundStyle(PaperColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let action {
                Button(action, action: onAction)
                    .buttonStyle(.paperText(PaperColor.ink, .subhead, weight: .semibold))
            }
        }
        .padding(.horizontal, PaperSpace.l)
        .padding(.vertical, action == nil ? PaperSpace.m : PaperSpace.xs)
        .background(tone.soft, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Figures

/// A figure with its unit beside it and an optional context line below.
struct Headline: View {
    let value: String
    let unit: String
    var detail: String?
    var style: PaperType = .hero

    var body: some View {
        VStack(alignment: .leading, spacing: PaperSpace.xs) {
            PaperFigure(value, unit: unit, style: style)
            if let detail {
                Text(detail).paperType(.subhead, numeric: true).foregroundStyle(PaperColor.secondary)
            }
        }
    }
}

/// A small icon button with a hit target and a count badge.
struct BarIcon: View {
    let glyph: PaperGlyph
    var badge: Int = 0
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PaperIcon(glyph, size: 22)
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Text(badge > 99 ? "99+" : "\(badge)")
                            .font(.brand(10, .semibold))
                            .monospacedDigit()
                            .foregroundStyle(PaperColor.onAccent)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(PaperColor.accent, in: Capsule())
                            .offset(x: 8, y: -6)
                    }
                }
        }
        .buttonStyle(.paperIcon)
        .accessibilityLabel(badge > 0 ? "\(label), \(badge)" : label)
    }
}

// MARK: - Rows

/// A tappable row with a hairline below, for content richer than PaperRow.
struct RowContainer<Content: View>: View {
    var verticalPadding: CGFloat = PaperSpace.m
    var minHeight: CGFloat = PaperSpace.tap
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.vertical, verticalPadding)
            .frame(minHeight: minHeight)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { PaperHairline(color: PaperColor.hairlineSoft) }
    }
}

/// A label/value line for a page of facts ("Despatch  Tue 21 Oct").
struct FactRow: View {
    let label: String
    let value: String
    var labelWidth: CGFloat = 124

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: PaperSpace.m) {
            Text(label).paperType(.subhead).foregroundStyle(PaperColor.secondary)
                .frame(width: labelWidth, alignment: .leading)
            Text(value).paperType(.subhead, numeric: true).foregroundStyle(PaperColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { PaperHairline(color: PaperColor.hairlineSoft) }
        .accessibilityElement(children: .combine)
    }
}

/// Quiet inline loading line: a small spinner and words. Used where a load
/// takes long enough to notice; nothing is drawn as zero while it runs.
struct LoadingLine: View {
    let text: String
    init(_ text: String = "Loading") { self.text = text }

    var body: some View {
        HStack(spacing: PaperSpace.s) {
            ProgressView().controlSize(.small).tint(PaperColor.secondary)
            Text(text).paperType(.subhead).foregroundStyle(PaperColor.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, PaperSpace.l)
    }
}

// MARK: - Screen scaffolding

struct ScreenTitle<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center) {
            Text(title)
                .paperType(.largeTitle)
                .foregroundStyle(PaperColor.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            trailing()
        }
        .padding(.top, PaperSpace.l)
    }
}

extension ScreenTitle where Trailing == EmptyView {
    init(_ title: String) { self.init(title) { EmptyView() } }
}

extension View {
    /// Paper margins, and a readable column on iPad.
    func screen() -> some View {
        frame(maxWidth: 720, alignment: .leading)
            .paperMargins()
            .frame(maxWidth: .infinity)
    }

    func section(top: CGFloat = PaperSpace.section) -> some View {
        padding(.top, top)
    }

    /// A tab's root screen: paper behind it and no system bar.
    func paperRootScreen() -> some View {
        paperBackground()
            .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - Lists that keep swipe actions
//
// Where a screen needs swipe-to-delete it stays a List, drawn as Paper:
// no backgrounds, no system separators (rows draw their own hairline), the
// 28 pt margins and a readable column on iPad.

/// A NavigationLink inside a List without the system's disclosure chevron
/// (the row draws its own).
struct ListLinkRow<Value: Hashable, Content: View>: View {
    let value: Value
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            NavigationLink(value: value) { EmptyView() }.opacity(0)
            content()
        }
    }
}

extension View {
    func paperListRow(top: CGFloat = 0, bottom: CGFloat = 0) -> some View {
        listRowInsets(EdgeInsets(top: top, leading: PaperSpace.margin, bottom: bottom, trailing: PaperSpace.margin))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    func paperList() -> some View {
        listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 0)
            .frame(maxWidth: 720 + PaperSpace.margin * 2)
            .frame(maxWidth: .infinity)
    }
}

/// Pushed screens hide the system bar and use PaperTopBar.
struct PushedScreen<Trailing: View, Content: View>: View {
    let back: String
    var title: String?
    var scrolls: Bool
    var onRefresh: (() async -> Void)?
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content
    @Environment(\.dismiss) private var dismiss

    init(
        back: String,
        title: String? = nil,
        scrolls: Bool = true,
        onRefresh: (() async -> Void)? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.back = back
        self.title = title
        self.scrolls = scrolls
        self.onRefresh = onRefresh
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            PaperTopBar(.back(back), title: title, onLeading: { dismiss() }) {
                HStack(spacing: 0) { trailing() }
            }
            .screen()
            if scrolls {
                if let onRefresh {
                    ScrollView { content().padding(.bottom, 120) }
                        .refreshable { await onRefresh() }
                } else {
                    ScrollView { content().padding(.bottom, 120) }
                }
            } else {
                content()
            }
        }
        .paperBackground()
        .toolbar(.hidden, for: .navigationBar)
    }
}

extension PushedScreen where Trailing == EmptyView {
    init(
        back: String,
        title: String? = nil,
        scrolls: Bool = true,
        onRefresh: (() async -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(back: back, title: title, scrolls: scrolls, onRefresh: onRefresh, trailing: { EmptyView() }, content: content)
    }
}

/// The body of a sheet: a top bar with Close, then the content in margins.
struct SheetScreen<Trailing: View, Content: View>: View {
    let title: String?
    var scrolls: Bool = true
    var onRefresh: (() async -> Void)?
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content
    @Environment(\.dismiss) private var dismiss

    init(_ title: String?, scrolls: Bool = true, onRefresh: (() async -> Void)? = nil,
         @ViewBuilder trailing: @escaping () -> Trailing, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.scrolls = scrolls
        self.onRefresh = onRefresh
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            PaperTopBar(.close, title: title, onLeading: { dismiss() }) { trailing() }
                .screen()
                .padding(.top, PaperSpace.s)
            if scrolls {
                if let onRefresh {
                    ScrollView { content().screen().padding(.bottom, PaperSpace.section) }
                        .refreshable { await onRefresh() }
                } else {
                    ScrollView { content().screen().padding(.bottom, PaperSpace.section) }
                }
            } else {
                content().screen()
            }
        }
        .paperBackground()
    }
}

extension SheetScreen where Trailing == EmptyView {
    init(_ title: String?, scrolls: Bool = true, onRefresh: (() async -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(title, scrolls: scrolls, onRefresh: onRefresh, trailing: { EmptyView() }, content: content)
    }
}

// MARK: - Tab activation
//
// All five tabs stay alive (see MainTabView), so `.task` and `.onAppear` on a
// tab's screens run once at launch, not each time the tab is opened as they
// did under TabView. Screens that refreshed on return, or that poll or count
// down while visible, follow `isTabActive` instead.

private struct TabActiveKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var isTabActive: Bool {
        get { self[TabActiveKey.self] }
        set { self[TabActiveKey.self] = newValue }
    }
}

private struct TabActivityModifier: ViewModifier {
    @Environment(\.isTabActive) private var isActive
    let onChange: (Bool) -> Void

    func body(content: Content) -> some View {
        content.onChange(of: isActive) { _, active in onChange(active) }
    }
}

extension View {
    /// Called when this view's tab becomes current (true) or is left (false).
    func onTabActiveChange(_ action: @escaping (Bool) -> Void) -> some View {
        modifier(TabActivityModifier(onChange: action))
    }

    /// Runs `action` each time the user comes back to this view's tab.
    func onTabReturn(_ action: @escaping () async -> Void) -> some View {
        onTabActiveChange { active in
            if active { Task { await action() } }
        }
    }
}

/// Reloads a tab whose figures depend on the date. Every tab stays alive, so
/// without this an iPad left on Today on Sunday still showed Sunday's
/// "tomorrow" (Monday) on Monday morning.
private struct ResumeModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isTabActive) private var isActive
    let action: () async -> Void

    func body(content: Content) -> some View {
        content
            // Back from the background. Not from .inactive alone: pulling
            // down Control Center passes through that.
            .onChange(of: scenePhase) { old, new in
                if isActive, old == .background, new == .active { Task { await action() } }
            }
            // Midnight, a clock change or a time zone change, while open.
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                if isActive { Task { await action() } }
            }
    }
}

extension View {
    /// Runs `action` when the app comes back to the foreground or the day
    /// changes, while this view's tab is current. A tab that isn't current
    /// reloads when it's returned to instead (see `onTabReturn`).
    func onResume(_ action: @escaping () async -> Void) -> some View {
        modifier(ResumeModifier(action: action))
    }
}

// MARK: - App-wide toast
//
// For a confirmation that should outlive the screen that caused it, such as
// "Box 3 closed · 14 panels" as the box screen pops back to the list.

@MainActor
final class Toaster: ObservableObject {
    @Published var message: String?
    /// The message confirms a box sealed: the toast draws its seal.
    @Published var sealed = false
    func show(_ text: String, sealed: Bool = false) {
        self.sealed = sealed
        message = text
    }
}

// MARK: - Formatting

enum Format {
    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = TimeZone(identifier: "Europe/London")
        f.dateFormat = format
        return f
    }

    private static let longDay = formatter("EEEE d MMMM")
    private static let shortDay = formatter("EEE d MMM")
    private static let time = formatter("HH:mm")

    /// "Saturday 18 October"
    static func today(_ date: Date = .now) -> String { longDay.string(from: date) }
    /// "Sat 18 Oct"
    static func day(_ date: Date) -> String { shortDay.string(from: date) }
    /// "14:05"
    static func time(_ date: Date) -> String { time.string(from: date) }

    /// "Today 14:05", "Yesterday 09:12", "Thu 16 Oct 11:30"
    static func when(_ date: Date, now: Date = .now) -> String {
        "\(PaperFormat.relativeDay(date, now: now)) \(time(date))"
    }

    static var greeting: String {
        let h = Calendar.current.component(.hour, from: .now)
        return h < 12 ? "Morning" : (h < 18 ? "Afternoon" : "Evening")
    }

    /// "1 box", "3 boxes"
    static func count(_ n: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(PaperFormat.int(n)) \(n == 1 ? singular : (plural ?? singular + "s"))"
    }
}

// MARK: - Interactive back swipe with the system bar hidden
//
// Hiding the navigation bar (every pushed screen uses PaperTopBar instead)
// also switches off UIKit's edge swipe back, which people rely on. Keep it on
// whenever there is somewhere to go back to.

extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}

extension String {
    /// "Label sent to Munbyn" → "label sent to Munbyn", for joining phrases.
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}
