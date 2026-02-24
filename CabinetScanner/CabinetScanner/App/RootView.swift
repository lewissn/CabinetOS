import SwiftUI

struct RootView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        MainTabView()
    }
}

// MARK: - Tab bar

struct MainTabView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "square.grid.2x2")
                }

            packagingTab
                .tabItem {
                    Label("Packaging", systemImage: "shippingbox")
                }

            SettingsPlaceholderView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
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
