import Foundation
import SwiftUI

// MARK: - Notifications
//
// Mirrors GET /api/notifications on the Ops server.
//
// The wording — the headline, the supporting line, and how pressing it is —
// is all computed server-side and sent whole. That is deliberate: this app and
// the Ops website both show these, and two clients re-deriving "brought
// forward" from a pair of dates is two chances to disagree about the most
// important word on the screen.
//
// What this app decides for itself is presentation: colour, weight, ordering
// and what a tap does.

struct NotificationFeed: Decodable {
    let ok: Bool
    /// Everything outstanding for this device, not only what this page held —
    /// a badge that changes with the page size is worse than no badge.
    let unreadCount: Int
    let notifications: [AppNotification]
    /// The departments the server filtered by. Shown in Settings so a
    /// misconfigured audience looks like a setting rather than like no news.
    let departments: [String]?
    /// The server's clock, so the `since` cursor never depends on this
    /// device's time being right.
    let serverTime: String?
}

struct AppNotification: Decodable, Identifiable, Hashable {
    let id: String
    let kind: String

    let title: String
    let body: String?
    let severity: String

    /// "brought_forward" · "postponed" · "set" · "cleared"
    let direction: String?
    let previousDate: String?
    let newDate: String?
    let daysMoved: Int?
    let isBroughtForward: Bool?

    /// "That is tomorrow." — how pressing it is now, rather than when it
    /// happened. Absent unless the date is close and moving towards us.
    let urgencyNote: String?

    let job: NotificationJob?
    let changedBy: String?

    let detectedAt: String
    let detectionSource: String?

    /// Where this opens — "/jobs/<id>". The same route a QR code will encode.
    let linkPath: String?

    let read: Bool
    let readAt: String?

    static func == (a: AppNotification, b: AppNotification) -> Bool {
        a.id == b.id && a.read == b.read
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    // MARK: Presentation

    /// A despatch date pulled towards us is the case the whole feature exists
    /// for, so it is the only one that gets the loud treatment.
    var isUrgent: Bool { severity == "urgent" }

    var accentColour: Color {
        switch severity {
        case "urgent": return .orange
        case "info":   return .secondary
        default:       return .blue
        }
    }

    var systemImage: String {
        switch direction {
        case "brought_forward": return "arrow.left.to.line"
        case "postponed":       return "arrow.right.to.line"
        case "cleared":         return "calendar.badge.minus"
        case "set":             return "calendar.badge.plus"
        default:                return "bell"
        }
    }

    /// The short form for a banner, where the full title will not fit.
    var shortTitle: String {
        guard let reference = job?.reference else { return title }
        switch direction {
        case "brought_forward": return "\(reference) brought forward"
        case "postponed":       return "\(reference) postponed"
        default:                return title
        }
    }

    /// The job this concerns, when it is still in the index.
    var jobId: String? { job?.id }
}

struct NotificationJob: Decodable, Hashable {
    let id: String?
    /// "SO 9731" — how somebody refers to this job out loud.
    let reference: String?
    let name: String?
    let customerName: String?
}
