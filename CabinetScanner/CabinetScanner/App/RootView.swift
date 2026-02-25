import SwiftUI

struct RootView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        MainTabView()
    }
}

// MARK: - Tab enumeration

enum AppTab: Int {
    case dashboard
    case packaging
    case stock
    case settings
}

// MARK: - Tab bar

struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: AppTab = .dashboard

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(switchToPackaging: { selectedTab = .packaging })
                .tabItem {
                    Label("Dashboard", systemImage: "square.grid.2x2")
                }
                .tag(AppTab.dashboard)

            packagingTab
                .tabItem {
                    Label("Packaging", systemImage: "shippingbox")
                }
                .tag(AppTab.packaging)

            StockView()
                .tabItem {
                    Label("Stock", systemImage: "archivebox")
                }
                .tag(AppTab.stock)

            SettingsPlaceholderView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(AppTab.settings)
        }
    }

    @ViewBuilder
    private var packagingTab: some View {
        if appState.isStationConfigured {
            NavigationStack {
                ManifestListView()
            }
        } else {
            NavigationStack {
                StationSetupView()
            }
        }
    }
}

// MARK: - Minimal settings placeholder

private struct SettingsPlaceholderView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            List {
                Section("Station") {
                    LabeledContent("Device ID", value: String(appState.deviceId.prefix(8)) + "...")
                    LabeledContent("Station", value: appState.stationId)
                    LabeledContent("Operator", value: appState.operatorName.isEmpty ? "—" : appState.operatorName)
                }

                Section("API") {
                    LabeledContent("Mode", value: Configuration.apiMode.rawValue.capitalized)
                    LabeledContent("Host", value: Configuration.baseURL)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
