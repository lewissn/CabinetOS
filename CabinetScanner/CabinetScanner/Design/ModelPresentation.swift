import CabinetDesign
import SwiftUI

// MARK: - How models read on screen
//
// View-side only: these map existing fields to the design's status
// meanings. They add no data and change nothing the models hold.

extension AppNotification {
    /// A date pulled towards us is the one to act on soon; the rest are news.
    var tone: Tone { isUrgent ? .soon : .neutral }
}
