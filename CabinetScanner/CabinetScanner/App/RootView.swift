import SwiftUI

struct RootView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
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
