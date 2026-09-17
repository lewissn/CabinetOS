import UIKit
import AudioToolbox

enum HapticService {
    static func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    static func error() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
    }

    static func warning() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }

    static func light() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    static func medium() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    static func heavy() {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
    }

    /// Play a short tick sound (system) — used for successful scans.
    static func playTickSound() {
        AudioServicesPlaySystemSound(1057)
    }

    /// Wrap milestone or personal best. Rising triple-tap so it reads as a
    /// reward rather than the plain success bump every close already gets.
    static func celebrate() {
        Task { @MainActor in
            HapticService.light()
            try? await Task.sleep(nanoseconds: 90_000_000)
            HapticService.medium()
            try? await Task.sleep(nanoseconds: 90_000_000)
            HapticService.heavy()
        }
        AudioServicesPlaySystemSound(1025)
    }

    // MARK: - Differentiated scan-error feedback
    //
    // Each error type has a distinct audio + haptic vocabulary so an operator
    // can react to a fault without taking their eyes off the cabinet.

    /// Panel was already packed elsewhere. Soft double-bump haptic + low tone.
    static func alreadyPacked() {
        Task { @MainActor in
            HapticService.medium()
            try? await Task.sleep(nanoseconds: 90_000_000)
            HapticService.medium()
        }
        AudioServicesPlaySystemSound(1073)  // SMS-received-1: short low tone
    }

    /// Panel is not on this manifest. Sharp triple-tap haptic + descending tones.
    static func notOnManifest() {
        Task { @MainActor in
            HapticService.heavy()
            try? await Task.sleep(nanoseconds: 60_000_000)
            HapticService.heavy()
            try? await Task.sleep(nanoseconds: 60_000_000)
            HapticService.heavy()
        }
        AudioServicesPlaySystemSound(1053)  // descending alert
    }

    /// Wrong consignment / box closed / batch rejected — long-buzz error.
    static func wrongConsignment() {
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(.error)
        AudioServicesPlaySystemSound(1053)
    }

    /// Cold-offline gate — the parts list isn't cached yet. Single warning bump.
    static func registryNotCached() {
        warning()
        AudioServicesPlaySystemSound(1306)
    }
}
