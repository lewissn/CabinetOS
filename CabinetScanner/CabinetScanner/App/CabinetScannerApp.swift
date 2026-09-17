import SwiftUI

@main
struct CabinetScannerApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var router = AppRouter()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        if Configuration.useOfflineQueue {
            // Start network monitoring + scan-queue lifecycle as soon as the
            // app boots so we can drain pending scans the moment connectivity
            // returns, even if the user never opens the scanner this session.
            NetworkMonitor.shared.start()
            NetworkMonitor.shared.onRestore {
                Task { await ScanQueueService.shared.flush() }
            }
            Task {
                await ScanQueueService.shared.start(monitor: NetworkMonitor.shared)
                await ScanQueueService.shared.flush()
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(router)
                // cabinetscanner://job/<id>, and the Ops https URL a QR code
                // on a label will eventually carry.
                .onOpenURL { url in router.open(url) }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                if Configuration.useOfflineQueue {
                    Task { await ScanQueueService.shared.flush() }
                }
                // Catch up on anything raised while the app was in the
                // background, then keep the feed current while it is open.
                NotificationService.shared.startPolling()

            case .background, .inactive:
                // Nothing is lost by stopping: the server holds every
                // notification and read state is per device, so whatever
                // happened while this was shut is still unread on return.
                NotificationService.shared.stopPolling()

            @unknown default:
                break
            }
        }
    }
}
