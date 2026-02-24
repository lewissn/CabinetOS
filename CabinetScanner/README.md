# CabinetScanner — iOS Packaging Scanner

Native iOS barcode scanner for cabinet packaging workflows. Scans QR + Code128 labels, assembles triplets (project / cabinet / part), validates against the Ops `packing_panel_registry`, and packs items into boxes.

---

## Setup

### Prerequisites
- Xcode 15+ (Swift 5, iOS 17 SDK)
- Physical iPhone with camera (simulator cannot scan barcodes)
- Apple Developer account for device deployment

### Open Project
1. Open `CabinetScanner.xcodeproj` in Xcode
2. Select your **development team** in Signing & Capabilities
3. Set a unique **Bundle Identifier** if needed (default: `com.cabinetOS.CabinetScanner`)
4. Build & run on a physical iPhone

---

## Mock vs Live Mode

Edit **`Services/Configuration.swift`** — one line change:

```swift
static var apiMode: APIMode = .mock   // ← change to .live for real backend
static var baseURL: String = "http://localhost:3000"  // ← set to Ops host
```

| Mode | What it does |
|------|-------------|
| `.mock` | Runs entirely offline with in-memory test data. No backend required. |
| `.live` | Calls the Ops Next.js server at `Configuration.baseURL + "/api/despatch/"` |

### Switching for production

```swift
// Services/Configuration.swift
static var apiMode: APIMode = .live
static var baseURL: String = "https://ops.thecabinetshop.co.uk"
```

---

## Architecture

```
CabinetScanner/
├── App/              — Entry point, AppState (deviceId/operator/stationId), RootView
├── Models/           — Manifest, Consignment, Box, BoxItem, ScanResult
├── Services/         — APIProtocol, LiveAPIService, MockAPIService, MockData,
│                       Configuration, ServiceContainer,
│                       CameraService, ScanAssembler, HapticService, RealtimeService
├── ViewModels/       — ManifestList, ConsignmentList, BoxList, BoxDetail, Scanner
└── Views/
    ├── StationSetup/ — First-launch station/operator config
    ├── Manifests/    — Manifest picker
    ├── Consignments/ — Consignment list with status badges
    ├── Boxes/        — Box list, box detail, slide-to-close, missing items sheet
    ├── Scanner/      — Fullscreen camera + scan overlay + status HUD
    └── Components/   — Toast, SlideToClose, CameraPermission
```

---

## Scanner Engine

| Setting | Value |
|---------|-------|
| Symbologies | QR + Code128 only |
| Buffer window | 700 ms rolling |
| Frame stability | 2 frames minimum before accepting a code |
| Debounce cooldown | 1.2 s after successful commit |
| Capture resolution | 1080p (optimised for barcodes) |

### Triplet classification (Code128)

Confirmed data format (Feb 2026):
- **Part number** — always 1–2 digit numeric string (e.g. `"4"`, `"12"`)
- **Cabinet name** — always alphanumeric, never purely numeric (e.g. `"LDC"`, `"UDC"`)

The assembler classifies on this rule: `length ≤ 2 && all digits → partNumber`.
No ambiguous cases can arise given the confirmed label format.

---

## Ops API Integration

### Base URL

All iOS endpoints live under the **`/api/despatch/`** prefix on the Ops Next.js server:

```
Dev:  http://localhost:3000/api/despatch
Prod: https://ops.thecabinetshop.co.uk/api/despatch   ← confirm exact domain
```

This is set via `Configuration.apiBase` (derived from `baseURL`).

### Endpoint Map

| # | iOS call | Method | Ops path | Status |
|---|---------|--------|---------|--------|
| 1 | `fetchManifests` | GET | `/api/despatch/manifests` | ✅ likely exists |
| 2 | `fetchConsignments` | GET | `/api/despatch/manifests/:id/consignments` | ⚠️ verify / create |
| 3 | `fetchBoxes` | GET | `/api/despatch/consignments/:id/boxes` | 🆕 create |
| 4 | `createBox` | POST | `/api/despatch/consignments/:id/boxes` | 🆕 create |
| 5 | `fetchBoxDetail` | GET | `/api/despatch/boxes/:id` | 🆕 create |
| 6 | `scanItem` ⭐ | POST | `/api/despatch/boxes/:id/scan` | 🆕 create |
| 7 | `deleteBoxItem` | DELETE | `/api/despatch/box-items/:id` | 🆕 create |
| 8 | `deleteBox` | DELETE | `/api/despatch/boxes/:id` | 🆕 create |
| 9 | `closeBox` | POST | `/api/despatch/boxes/:id/close` | 🆕 create |
| 10 | `finishConsignment` | POST | `/api/despatch/consignments/:id/finish` | 🆕 create (wraps existing missing-panels logic) |

### Core Scan Endpoint — POST `/api/despatch/boxes/:boxId/scan`

Request body:
```json
{
  "manifestId":     "uuid",
  "consignmentId":  "uuid",
  "projectName":    "Lewis Nichols - 29248",
  "cabinetName":    "LDC",
  "partNumber":     "4",
  "deviceId":       "uuid-string",
  "stationId":      "packaging",
  "operator":       "optional string",
  "scannedAt":      "2026-02-24T10:00:00Z"
}
```

> **Key mapping**: `projectName` in the iOS request = `source_name` in `packing_panel_registry` = `job_identifier` on the consignment record. The QR code on every label prints the `source_name` verbatim (CSV filename without extension).

**Validation rules the Ops endpoint must enforce:**
1. Box exists and is `open`
2. `projectName` matches consignment's `job_identifier`
3. Panel UID `{projectName}|{cabinetName}|{partNumber}` exists in `packing_panel_registry`
4. Panel UID not already scanned into any other box for this manifest
5. Box belongs to the consignment in the request

Success response:
```json
{
  "ok": true,
  "added": { "boxItemId": "uuid", "projectName": "...", "cabinetName": "...", "partNumber": "4" },
  "boxProgress": { "packedCount": 12, "expectedCount": 24 }
}
```

Error response:
```json
{
  "ok": false,
  "code": "NOT_ON_MANIFEST|WRONG_CONSIGNMENT|ALREADY_PACKED|BOX_CLOSED",
  "message": "Human readable message",
  "details": { "alreadyPackedInBoxId": "optional-uuid" }
}
```

### Finish Consignment — POST `/api/despatch/consignments/:id/finish`

This endpoint should:
1. Call the existing `getMissingPanelsForConsignment(consignmentId)` from `src/lib/packing.ts`
2. If `missingItems.length > 0` → return `{ ok: false, missingItems: [...] }`
3. If none missing → mark consignment `complete`, return `{ ok: true, message: "..." }`

`missingItems` shape expected by iOS:
```json
[
  { "projectName": "Lewis Nichols - 29248", "cabinetName": "LDC", "partNumber": "4" }
]
```

---

## Source Name / Job Identifier Mapping

This is the critical join key between the iOS app and the Ops backend:

| System | Field name | Example value |
|--------|-----------|---------------|
| Manifest CSV filename | — | `Lewis Nichols - 29248.csv` |
| `packing_panel_registry` | `source_name` | `"Lewis Nichols - 29248"` |
| Ops consignment | `job_identifier` | `"Lewis Nichols - 29248"` |
| QR code on label | — | `"Lewis Nichols - 29248"` |
| iOS `Consignment.jobIdentifier` | `jobIdentifier` | `"Lewis Nichols - 29248"` |
| iOS scan request | `projectName` | `"Lewis Nichols - 29248"` |

The QR code value and `source_name` **must match exactly** for a scan to validate. The Ops `populateRegistryFromManifest()` function sets `source_name` from the CSV filename; that same string is printed onto every label in the job.

---

## Supabase Tables Needed (Packing-specific)

The existing Ops schema has `packing_panel_registry`. The following tables are **new** and need creating for the iOS packing flow:

### `packing_boxes`
| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid PK | |
| `consignment_id` | uuid FK → consignments | |
| `box_number` | int | Per-consignment sequential |
| `box_type` | text | `'panel'` / `'fitting_kit'` / `'drawer_runner'` |
| `status` | text | `'open'` / `'closed'` |
| `item_count` | int | Maintained by trigger or endpoint |
| `created_at` | timestamptz | |
| `closed_at` | timestamptz | nullable |

### `packing_box_items`
| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid PK | |
| `box_id` | uuid FK → packing_boxes | |
| `project_name` | text | = `source_name` = QR value |
| `cabinet_name` | text | |
| `part_number` | text | 1–2 digit numeric string |
| `scanned_at` | timestamptz | |
| `device_id` | text | |
| `operator` | text | nullable |

### Indexes & Constraints

```sql
-- Fast box lookup per consignment
CREATE INDEX idx_packing_boxes_consignment ON packing_boxes (consignment_id);

-- Fast item lookup per box
CREATE INDEX idx_packing_box_items_box ON packing_box_items (box_id);

-- Unique: each panel can only be packed once per manifest
-- (The Ops scan endpoint should enforce this in code, checking packing_panel_registry)
CREATE UNIQUE INDEX idx_packing_box_items_unique_panel
  ON packing_box_items (project_name, cabinet_name, part_number);
```

---

## Supabase Realtime Config (Future)

The app currently polls every 4 s on BoxDetail for multi-device sync.
To upgrade to push-based Realtime:

1. Enable Realtime on `packing_boxes` and `packing_box_items` in Supabase dashboard
2. Set `Configuration.useRealtime = true`
3. Implement `RealtimeService` with a Supabase WebSocket client (the current class has a polling stub ready to swap out)
4. Subscribe channels filtered by `consignment_id` / `box_id`

---

## iOS Signing Checklist

- [ ] Open project → Signing & Capabilities tab
- [ ] Set **Team**
- [ ] Confirm **Bundle Identifier** (`com.cabinetOS.CabinetScanner` or your own)
- [ ] Run on **physical device** (camera required for scanning)
- [ ] Camera usage description is set via build settings (`INFOPLIST_KEY_NSCameraUsageDescription`)

---

## Post-Build Checklist for Lewis

- [ ] Set `Configuration.baseURL` to the production Ops domain
- [ ] Set `Configuration.apiMode = .live`
- [ ] Create `packing_boxes` and `packing_box_items` tables in Supabase
- [ ] Add indexes listed above
- [ ] Create the 7 new Ops `/api/despatch/` routes (endpoints 3–10 above)
- [ ] Wire `/api/despatch/consignments/:id/finish` to `getMissingPanelsForConsignment` from `src/lib/packing.ts`
- [ ] Verify `source_name` in `packing_panel_registry` matches QR codes printed on labels exactly
- [ ] Confirm the Ops consignment record exposes `job_identifier` in the API response
- [ ] Test end-to-end with a real label on device in `.mock` mode first, then `.live`
