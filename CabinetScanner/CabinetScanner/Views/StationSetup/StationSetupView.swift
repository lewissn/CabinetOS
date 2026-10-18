import CabinetDesign
import SwiftUI

/// First run on a device: which station it is and who's working it.
struct StationSetupView: View {
    @EnvironmentObject var appState: AppState
    @State private var operatorName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenTitle("Set up this device")
                Text("Once it's set, the device goes straight to packing.")
                    .paperType(.subhead)
                    .foregroundStyle(PaperColor.secondary)
                    .padding(.top, PaperSpace.xs)

                VStack(alignment: .leading, spacing: PaperSpace.s) {
                    PaperLabel("Station")
                    // Packaging is the only station this app sets up; shown as
                    // the chosen chip rather than a choice of one.
                    PaperChips(["Packaging"], label: { $0 }, isSelected: { _ in true }) { _ in }
                        .allowsHitTesting(false)
                }
                .section()

                PaperUnderlineField("Operator (optional)", text: $operatorName, placeholder: "Your name")
                    .textInputAutocapitalization(.words)
                    .section(top: PaperSpace.xxl)

                VStack(alignment: .leading, spacing: 0) {
                    PaperSectionHeader("This device")
                    FactRow(label: "Device ID", value: String(appState.deviceId.prefix(8)) + "…")
                }
                .section()

                Button("Start packing") {
                    appState.saveStation(
                        stationId: "packaging",
                        operatorName: operatorName.trimmingCharacters(in: .whitespaces)
                    )
                }
                .buttonStyle(.paperPill(.accent, .floor, fullWidth: true))
                .section()
            }
            .screen()
            .padding(.bottom, 120)
        }
        .paperRootScreen()
    }
}
