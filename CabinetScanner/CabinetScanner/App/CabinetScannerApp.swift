import CabinetDesign
import SwiftUI
import UIKit

@main
struct CabinetScannerApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var router = AppRouter()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        PaperFonts.register()
        Self.styleSystemChrome()

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
                .tint(PaperColor.ink)
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

    /// Every screen draws its own bar with PaperTopBar, but alerts, menus and
    /// the odd system sheet still use UIKit chrome. Give that chrome the brand
    /// font and the paper background so it doesn't look like another app.
    private static func styleSystemChrome() {
        let ink = UIColor(PaperColor.ink)
        let title = UIFont(name: BrandWeight.semibold.rawValue, size: 17) ?? .systemFont(ofSize: 17, weight: .semibold)
        let large = UIFont(name: BrandWeight.semibold.rawValue, size: 32) ?? .systemFont(ofSize: 32, weight: .semibold)
        let body = UIFont(name: BrandWeight.regular.rawValue, size: 16) ?? .systemFont(ofSize: 16)

        let bar = UINavigationBarAppearance()
        bar.configureWithOpaqueBackground()
        bar.backgroundColor = UIColor(PaperColor.paper)
        bar.shadowColor = UIColor(PaperColor.hairline)
        bar.titleTextAttributes = [.font: title, .foregroundColor: ink]
        bar.largeTitleTextAttributes = [.font: large, .foregroundColor: ink]
        let button = UIBarButtonItemAppearance()
        button.normal.titleTextAttributes = [.font: body, .foregroundColor: ink]
        bar.buttonAppearance = button
        bar.backButtonAppearance = button
        UINavigationBar.appearance().standardAppearance = bar
        UINavigationBar.appearance().scrollEdgeAppearance = bar
        UINavigationBar.appearance().compactAppearance = bar
        UINavigationBar.appearance().tintColor = ink

        let segmentFont = UIFont(name: BrandWeight.medium.rawValue, size: 13) ?? .systemFont(ofSize: 13, weight: .medium)
        UISegmentedControl.appearance().setTitleTextAttributes([.font: segmentFont, .foregroundColor: ink], for: .normal)
        UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(PaperColor.raised)
        UISegmentedControl.appearance().backgroundColor = UIColor(PaperColor.segment)
    }
}
