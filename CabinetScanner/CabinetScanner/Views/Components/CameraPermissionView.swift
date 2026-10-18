import CabinetDesign
import SwiftUI

/// Shown when the camera isn't allowed: a title, one line and one action.
struct CameraPermissionView: View {
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            Spacer()
            PaperEmptyState(
                "The camera isn't allowed",
                message: "CabinetScanner needs the camera to read the labels on cabinet panels. Allow it in Settings.",
                actionTitle: "Open Settings",
                action: onOpenSettings
            )
            Spacer()
        }
        .screen()
        .paperBackground()
    }
}
