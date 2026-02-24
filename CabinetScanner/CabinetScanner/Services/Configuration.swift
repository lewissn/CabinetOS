import Foundation

enum APIMode: String {
    case live
    case mock
}

struct Configuration {
    // MARK: - Toggle this to switch between mock and live API
    static var apiMode: APIMode = .live

    // MARK: - Ops API Host
    // Dev:  http://localhost:3000
    // Prod: https://ops.thecabinetshop.co.uk  (confirm exact domain)
    // Set host ONLY — no trailing slash, no path prefix.
    // All iOS endpoints live under /api/despatch/ on the Ops server.
    static var baseURL: String = "https://ops.thecabinetshop.co.uk"

    // MARK: - Supabase (reserved for direct-mode / Realtime in future)
    static var supabaseURL: String = "https://your-project.supabase.co"
    static var supabaseAnonKey: String = "your-anon-key"

    // MARK: - Realtime
    // false = polling fallback (MVP); true = Supabase Realtime (future)
    static var useRealtime: Bool = false
    static var pollingIntervalSeconds: Double = 4.0

    // MARK: - Scanner tuning
    /// Rolling buffer window for multi-frame triplet assembly (ms)
    static var scanBufferWindowMs: Double = 700
    /// Cooldown after a successful commit — prevents double-scanning same label (ms)
    static var scanDebounceCooldownMs: Double = 1200
    /// How many frames a code must appear in to be considered stable
    static var requiredFrameStability: Int = 2

    // MARK: - Derived
    static var isLive: Bool { apiMode == .live }
    static var isMock: Bool { apiMode == .mock }

    /// Full prefix for all Ops despatch endpoints
    static var apiBase: String { baseURL + "/api/despatch" }
}
