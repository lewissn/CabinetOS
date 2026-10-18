import CabinetDesign
import SwiftUI

struct RootView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        MainTabView()
    }
}

// MARK: - Tab enumeration

enum AppTab: Int, CaseIterable {
    case dashboard
    case jobs
    case packaging
    case stock
    case settings

    var title: String {
        switch self {
        case .dashboard: "Today"
        case .jobs: "Jobs"
        case .packaging: "Packing"
        case .stock: "Stock"
        case .settings: "Settings"
        }
    }

    var glyph: PaperGlyph {
        switch self {
        case .dashboard: .today
        case .jobs: .job
        case .packaging: .box
        case .stock: .stock
        case .settings: .settings
        }
    }
}

// MARK: - Tab bar
//
// PaperTabBar over a ZStack of the five tabs. Each tab is kept alive (hidden
// by opacity, not torn down) so its navigation stack, scroll position and
// loaded data survive switching away, as they did under TabView.

struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var router: AppRouter
    @StateObject private var toaster = Toaster()

    private var selectedTab: Binding<AppTab> {
        Binding(get: { router.selectedTab }, set: { router.selectedTab = $0 })
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                tabContent(.dashboard) {
                    DashboardView(switchToPackaging: { router.selectedTab = .packaging })
                }
                tabContent(.jobs) { JobsHubView() }
                tabContent(.packaging) { packagingTab }
                tabContent(.stock) { StockView() }
                tabContent(.settings) { SettingsPlaceholderView() }
            }
            .overlay(alignment: .bottom) {
                ToastView(message: $toaster.message, autoDismissAfter: .seconds(2.4))
            }
            // An arriving despatch change, over whatever is on screen. Tapping it
            // goes to the job, which is the only useful thing to do about one.
            .notificationBanner { notification in
                if let jobId = notification.jobId {
                    router.openJob(jobId)
                } else {
                    router.selectedTab = .dashboard
                }
            }

            PaperTabBar(AppTab.allCases.map { .init($0, title: $0.title, glyph: $0.glyph) }, selection: selectedTab)
                .overlay(alignment: .top) { currentMark }
        }
        .environmentObject(toaster)
        .paperBackground()
        .paperStatusBarBackdrop()
    }

    /// The current tab gets the accent as a short bar: amber marks the current
    /// place, never text.
    private var currentMark: some View {
        let tabs = AppTab.allCases
        let i = CGFloat(tabs.firstIndex(of: router.selectedTab) ?? 0)
        return GeometryReader { geo in
            let w = geo.size.width / CGFloat(tabs.count)
            Capsule().fill(PaperColor.accent)
                .frame(width: 28, height: 3)
                .position(x: w * i + w / 2, y: 1.5)
                .animation(PaperMotion.spring, value: router.selectedTab)
        }
        .frame(height: 3)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func tabContent<V: View>(_ tab: AppTab, @ViewBuilder _ view: () -> V) -> some View {
        let current = router.selectedTab == tab
        return view()
            .opacity(current ? 1 : 0)
            .allowsHitTesting(current)
            .accessibilityHidden(!current)
    }

    @ViewBuilder
    private var packagingTab: some View {
        if appState.isStationConfigured {
            NavigationStack {
                PackagingHomeView()
            }
        } else {
            NavigationStack {
                StationSetupView()
            }
        }
    }
}

// MARK: - Settings

private struct SettingsPlaceholderView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ScreenTitle("Settings")

                    VStack(alignment: .leading, spacing: 0) {
                        PaperSectionHeader("Station")
                        FactRow(label: "Station", value: appState.stationId)
                        FactRow(label: "Operator", value: appState.operatorName.isEmpty ? "–" : appState.operatorName)
                        FactRow(label: "Device ID", value: String(appState.deviceId.prefix(8)) + "…")
                    }
                    .section(top: PaperSpace.xxl)

                    DeviceTokenSection().section()

                    VStack(alignment: .leading, spacing: 0) {
                        PaperSectionHeader("Server")
                        FactRow(label: "Mode", value: Configuration.apiMode.rawValue.capitalized)
                        FactRow(label: "Host", value: Configuration.baseURL)
                    }
                    .section()

                    #if DEBUG
                    DebugHostSection().section()
                    #endif
                }
                .screen()
                .padding(.bottom, 120)
            }
            .scrollDismissesKeyboard(.interactively)
            .paperRootScreen()
        }
    }
}


// MARK: - Device access token
//
// Job search, the production board and despatch notifications are behind
// authentication; the older despatch endpoints are not. The token is entered
// once per device so nobody has to sign in mid-shift, and is held in the
// Keychain rather than compiled in — a baked-in token ships to every device
// and cannot be revoked singly.
//
// "Check access" is the important part of this screen. A refused token and a
// server that was never given any token fail identically from here, and only
// the server can tell the two apart — so this asks it, and prints the answer.

private struct DeviceTokenSection: View {
    @EnvironmentObject private var router: AppRouter
    @State private var token: String = Configuration.deviceAPIToken ?? ""
    @State private var didSave = false
    @State private var isChecking = false
    @State private var check: DeviceCheckResult?
    @State private var checkError: String?
    @FocusState private var isFocused: Bool

    private let service = JobIndexService()

    private var status: (String, Tone) {
        if didSave { return ("Saved", .done) }
        if Configuration.hasDeviceAPIToken { return ("Set", .neutral) }
        return ("Not set", .soon)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaperSectionHeader("Job search access") {
                StatusText(status.0, tone: status.1)
            }

            // A link that arrived before this device could act on it. Saying
            // so is the difference between "Settings opened for no reason" and
            // "this is the one thing standing between you and that job".
            if router.isWaitingForAccess {
                Notice(text: "A job link is waiting. Add this device's access token and it will open.", tone: .soon)
                    .padding(.top, PaperSpace.s)
            }

            VStack(alignment: .leading, spacing: PaperSpace.xs) {
                PaperLabel("Access token")
                SecureField("Paste the access token", text: $token)
                    .paperType(.body)
                    .foregroundStyle(PaperColor.ink)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($isFocused)
                    .padding(.bottom, PaperSpace.xs)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(isFocused ? PaperColor.accent : PaperColor.dot).frame(height: isFocused ? 1.5 : 1)
                    }
                    .accessibilityLabel("Access token")
            }
            .padding(.top, PaperSpace.l)

            HStack(spacing: PaperSpace.m) {
                Button("Save") {
                    Configuration.setDeviceAPIToken(token)
                    // Show what was actually stored, so a stray "Bearer " or a
                    // line break that has just been removed is visible.
                    token = Configuration.deviceAPIToken ?? ""
                    isFocused = false
                    didSave = true
                    Task {
                        await runCheck()
                        // The destination was held through setting up, which
                        // is the whole point of holding it.
                        if check?.authenticated == true, router.pendingJobId != nil {
                            router.selectedTab = .jobs
                        }
                    }
                }
                .buttonStyle(.paperPill(.accent, .regular))
                .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty)

                Button {
                    Task { await runCheck() }
                } label: {
                    if isChecking {
                        ProgressView().tint(PaperColor.ink)
                    } else {
                        Text("Check access")
                    }
                }
                .buttonStyle(.paperPill(.outline, .regular))
                .disabled(isChecking)

                Spacer(minLength: 0)
            }
            .padding(.top, PaperSpace.l)

            if let check {
                DeviceCheckSummary(result: check).padding(.top, PaperSpace.l)
            } else if let checkError {
                Notice(text: checkError, tone: .soon).padding(.top, PaperSpace.l)
            }

            if Configuration.hasDeviceAPIToken {
                Button("Remove token", role: .destructive) {
                    Configuration.setDeviceAPIToken(nil)
                    token = ""
                    didSave = false
                    check = nil
                    checkError = nil
                }
                .buttonStyle(.paperText(PaperColor.danger, .subhead, weight: .medium))
                .padding(.top, PaperSpace.s)
            }

            Text("Needed for Jobs, the production board and despatch alerts. Packing works without it. Either the whole \"name:token\" line or just the token will do.")
                .paperType(.footnote)
                .foregroundStyle(PaperColor.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, PaperSpace.m)
        }
        .onChange(of: token) { _, _ in
            didSave = false
            check = nil
        }
    }

    private func runCheck() async {
        isChecking = true
        checkError = nil
        do {
            check = try await service.deviceCheck()
        } catch {
            check = nil
            checkError = (error as? JobIndexError)?.errorDescription ?? error.localizedDescription
        }
        isChecking = false
    }
}

/// The server's verdict, rendered plainly enough to act on or to read out over
/// the phone to whoever looks after the deploy.
private struct DeviceCheckSummary: View {
    let result: DeviceCheckResult

    var body: some View {
        VStack(alignment: .leading, spacing: PaperSpace.xs) {
            StatusText(result.authenticated ? "Access confirmed" : "No access",
                       tone: result.authenticated ? .done : .held, style: .subhead)

            if let message = result.message {
                Text(message).paperType(.footnote).foregroundStyle(PaperColor.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let next = result.nextStep, !result.authenticated {
                Text(next).paperType(.footnote).foregroundStyle(PaperColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let server = result.server {
                // The number that separates "my token is wrong" from "that
                // deploy has no tokens at all".
                Text("Server: \(server.environment) · \(Format.count(server.deviceTokensConfigured, "device token")) configured")
                    .paperType(.caption, numeric: true)
                    .foregroundStyle(PaperColor.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}


#if DEBUG
// MARK: - Development host override
//
// Debug builds only, and compiled out of Release rather than disabled — see
// Configuration.baseURL. It exists so a server change can be exercised from a
// real device against a laptop before it is deployed.

private struct DebugHostSection: View {
    @State private var host: String = Configuration.debugHostOverride ?? ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaperSectionHeader("Development host")
            PaperUnderlineField("Host", text: $host, placeholder: "http://192.168.1.10:3000", keyboard: .URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.top, PaperSpace.s)

            HStack(spacing: PaperSpace.m) {
                Button("Use this host") {
                    Configuration.debugHostOverride = host
                    host = Configuration.debugHostOverride ?? ""
                }
                .buttonStyle(.paperPill(.outline, .regular))
                .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty)

                Button("Reset to production") {
                    Configuration.debugHostOverride = nil
                    host = ""
                }
                .buttonStyle(.paperText(PaperColor.danger, .subhead, weight: .medium))
                Spacer(minLength: 0)
            }
            .padding(.top, PaperSpace.l)

            Text("Debug builds only. Points the app at a machine running the Ops server locally; not present in a release build.")
                .paperType(.footnote)
                .foregroundStyle(PaperColor.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, PaperSpace.m)
        }
    }
}
#endif
