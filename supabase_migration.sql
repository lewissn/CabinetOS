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
