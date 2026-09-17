-- ============================================================
-- CabinetOS vNext – Supabase Migration
-- Run this in your Supabase SQL Editor
-- ============================================================

-- 1. Panel stock tracking table
-- Stores sheet counts per material. Upserted by the iOS app.
-- Does NOT modify price_library_panels.

CREATE TABLE IF NOT EXISTS panel_stock (
    material_name  TEXT PRIMARY KEY,
    qty_sheets     INTEGER NOT NULL DEFAULT 0,
    updated_at     TIMESTAMPTZ DEFAULT NOW(),
    updated_by     TEXT
);

ALTER TABLE panel_stock ENABLE ROW LEVEL SECURITY;

CREATE POLICY "panel_stock_all_access"
    ON panel_stock FOR ALL
    USING (true)
    WITH CHECK (true);

GRANT SELECT, INSERT, UPDATE, DELETE ON panel_stock TO anon, authenticated, service_role;


-- 2. Purchase list table
-- Simple shopping list – no workflow, no status tracking.

CREATE TABLE IF NOT EXISTS purchase_list (
    id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    item_name   TEXT NOT NULL,
    quantity    INTEGER NOT NULL DEFAULT 1,
    note        TEXT,
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE purchase_list ENABLE ROW LEVEL SECURITY;

CREATE POLICY "purchase_list_all_access"
    ON purchase_list FOR ALL
    USING (true)
    WITH CHECK (true);

GRANT SELECT, INSERT, UPDATE, DELETE ON purchase_list TO anon, authenticated, service_role;


-- 3. Ensure jobs table has postcode column (safe to run if it already exists)
-- Uncomment if your jobs table does not yet have a postcode column:
--
-- ALTER TABLE jobs ADD COLUMN IF NOT EXISTS postcode TEXT;


-- ============================================================
-- 4. Manual Manifests (courier shipments)
-- ============================================================

CREATE TABLE IF NOT EXISTS manual_manifests (
    id           UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    manifest_name TEXT NOT NULL,
    manifest_type TEXT NOT NULL DEFAULT 'manual',
    courier      TEXT,
    status       TEXT NOT NULL DEFAULT 'open',   -- 'open' | 'finished'
    note         TEXT,
    created_by   UUID,
    created_at   TIMESTAMPTZ DEFAULT NOW(),
    updated_at   TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE manual_manifests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "manual_manifests_all_access"
    ON manual_manifests FOR ALL
    USING (true)
    WITH CHECK (true);

GRANT SELECT, INSERT, UPDATE, DELETE ON manual_manifests TO anon, authenticated, service_role;


-- 5. Manual Manifest Boxes
CREATE TABLE IF NOT EXISTS manual_manifest_boxes (
    id           UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    manifest_id  UUID NOT NULL REFERENCES manual_manifests(id) ON DELETE CASCADE,
    box_number   INTEGER NOT NULL,
    status       TEXT NOT NULL DEFAULT 'open',   -- 'open' | 'closed'
    length_mm    INTEGER,
    width_mm     INTEGER,
    height_mm    INTEGER,
    weight_kg    NUMERIC,
    created_at   TIMESTAMPTZ DEFAULT NOW(),
    updated_at   TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE manual_manifest_boxes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "manual_manifest_boxes_all_access"
    ON manual_manifest_boxes FOR ALL
    USING (true)
    WITH CHECK (true);

GRANT SELECT, INSERT, UPDATE, DELETE ON manual_manifest_boxes TO anon, authenticated, service_role;


-- 6. Manual Manifest Items (scanned labels + manual hardware items)
CREATE TABLE IF NOT EXISTS manual_manifest_items (
    id               UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    box_id           UUID NOT NULL REFERENCES manual_manifest_boxes(id) ON DELETE CASCADE,
    item_type        TEXT NOT NULL DEFAULT 'label',   -- 'label' | 'manual'
    project_name     TEXT,
    cabinet_name     TEXT,
    part_number      TEXT,
    manual_item_name TEXT,
    qty              INTEGER NOT NULL DEFAULT 1,
    created_at       TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE manual_manifest_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "manual_manifest_items_all_access"
    ON manual_manifest_items FOR ALL
    USING (true)
    WITH CHECK (true);

GRANT SELECT, INSERT, UPDATE, DELETE ON manual_manifest_items TO anon, authenticated, service_role;
