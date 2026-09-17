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
    static let productionBaseURL = "https://ops.thecabinetshop.co.uk"

    /// The host every request goes to.
    ///
    /// In a Debug build this can be pointed at a laptop running `npm run dev`,
    /// from Settings, so a change can be tried before it is deployed. The
    /// override is compiled out of Release entirely rather than merely hidden:
    /// a switch that lets a warehouse iPad be aimed at an arbitrary host is
    /// not something to leave in a shipped build behind a disabled toggle.
    static var baseURL: String {
        #if DEBUG
        if let override = debugHostOverride, !override.isEmpty { return override }
        #endif
        return productionBaseURL
    }

    #if DEBUG
    static let debugHostOverrideKey = "debugOpsHostOverride"

    static var debugHostOverride: String? {
        get { UserDefaults.standard.string(forKey: debugHostOverrideKey) }
        set {
            let trimmed = newValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty {
                UserDefaults.standard.set(
                    trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed,
                    forKey: debugHostOverrideKey
                )
            } else {
                UserDefaults.standard.removeObject(forKey: debugHostOverrideKey)
            }
        }
    }
    #endif

    // MARK: - Supabase (reserved for direct-mode / Realtime in future)
    static var supabaseURL: String = "https://boxzppyquduaqduamchi.supabase.co"
    static var supabaseAnonKey: String = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJveHpwcHlxdWR1YXFkdWFtY2hpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk3NzAzNjMsImV4cCI6MjA4NTM0NjM2M30.YDRqPmkPzQH3sWFN4SST1dfz-1XI2paXT3l7Q3suFr8"

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

    // MARK: - Offline scanning
    /// When true, BJS scans are validated locally against a cached registry
    /// and queued for batched sync to the server. When false, the legacy
    /// per-scan POST /scan path is used.
    static var useOfflineQueue: Bool = true

    // MARK: - Derived
    static var isLive: Bool { apiMode == .live }
    static var isMock: Bool { apiMode == .mock }

    /// Full prefix for all Ops despatch endpoints
    static var apiBase: String { baseURL + "/api/despatch" }

    /// Root for the newer Ops endpoints (search, job index, production views).
    /// These sit directly under /api rather than /api/despatch.
    static var apiRoot: String { baseURL + "/api" }

    // MARK: - Device authorisation
    //
    // The job-index endpoints require a credential; the older despatch routes
    // do not (yet). The token is issued per device and entered once at station
    // setup, so nobody has to log in during a shift.
    //
    // Deliberately not compiled in: a token baked into the binary is a token
    // that ships to every device and cannot be revoked individually.
    //
    // Stored in the Keychain rather than UserDefaults — see DeviceTokenStore,
    // which also migrates tokens saved by earlier builds.
    //
    // The Ops server accepts either the bare secret or the whole
    // `name:secret` line from DEVICE_API_TOKENS, so whichever half was pasted
    // here will work.

    static var deviceAPIToken: String? {
        DeviceTokenStore.load()
    }

    static func setDeviceAPIToken(_ token: String?) {
        DeviceTokenStore.save(token)
    }

    static var hasDeviceAPIToken: Bool {
        !(deviceAPIToken ?? "").isEmpty
    }
}
