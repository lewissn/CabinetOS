import Foundation

// MARK: - Production board
//
// GET /api/board: the cutting-day board the website draws at /board. Read-only
// here. Stages only move with ShopVOX's steps, and booking days is an office
// task on the website.

struct ProductionBoardResponse: Decodable {
    let ok: Bool
    let board: CuttingBoard
    let notes: [String]
}

struct CuttingBoard: Decodable {
    let today: String
    let weeks: [Week]
    /// Waiting at Scheduled, no cutting day.
    let needsDay: [BoardCard]
    /// The cutting day has passed and production hasn't started.
    let missed: [BoardCard]
    /// Booked beyond the weeks shown.
    let later: [BoardCard]
    let inProduction: [BoardCard]
    /// Ready to pack, until despatched or collected.
    let completed: [BoardCard]

    struct Week: Decodable, Identifiable {
        /// The Monday.
        let weekOf: String
        /// Monday to Friday; null is a bank holiday.
        let days: [BoardDay?]

        var id: String { weekOf }
    }
}

struct BoardDay: Decodable, Identifiable {
    let date: String
    /// "mdf", "signature" or "either".
    let type: String
    let isToday: Bool
    let isPast: Bool
    let cards: [BoardCard]
    let used: Streams
    /// Cards on the day with no m².
    let unknownM2: Int
    let target: Streams
    let ceiling: Streams
    let collections: [String]
    let events: [Event]

    struct Streams: Decodable {
        let mdf: Double
        let signature: Double
    }

    struct Event: Decodable, Hashable {
        let kind: String
        let title: String
    }

    var id: String { date }
}

struct BoardCard: Decodable, Identifiable {
    /// Unique on the board: a split job has a card per cutting session.
    let key: String
    let jobId: String
    let customer: String?
    let salesOrderNumber: String?
    let shopifyOrderNumber: String?
    let carrier: String?
    let despatchDate: String?
    let step: Step?
    let group: String?
    let areaM2: Double?
    /// On a ShopVOX production date, not booked on the board.
    let tentative: Bool
    /// Warnings, as sentences.
    let flags: [String]

    struct Step: Decodable {
        let name: String
        let state: String
    }

    var id: String { key }
}
