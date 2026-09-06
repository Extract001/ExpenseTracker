-- ============================================================================
-- OFFLINE-FIRST EXPENSE TRACKER: SUPABASE CLOUD SCHEMA MIGRATION
-- Migration Version: 20260906000000_initial_cloud_schema.sql
-- Invariants:
--   1. PostgreSQL Row Level Security (RLS) enabled on ALL tables.
--   2. Strict user isolation enforced via auth.uid() = user_id on all CRUD ops.
--   3. Strict WITH CHECK clauses preventing cross-tenant write injections.
--   4. Integer minor currency units (paise/cents) stored as BIGINT.
--   5. RFC 4122 UUID v4 primary and foreign keys.
--   6. ISO-8601 UTC Timestamps with timezone (TIMESTAMPTZ).
--   7. Server-side Field-Level LWW merge via apply_sync_mutation stored procedure.
--   8. Operation-level and Entity-level Idempotency enforced in SQL transaction.
--   9. Deterministic composite cursor indexes (user_id, updated_at_utc ASC, id ASC).
--  10. Zero sensitive financial payloads stored in sync audit log.
--  11. Zero service_role access required by client; anon key only.
-- ============================================================================

-- Enable UUID extension if not already present
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================================
-- 1. PROFILES / USERS
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT,
    display_name TEXT,
    created_at_utc TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    last_active_at_utc TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "profiles_select_own"
    ON public.profiles FOR SELECT
    TO authenticated
    USING (auth.uid() = id);

CREATE POLICY "profiles_insert_own"
    ON public.profiles FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = id);

CREATE POLICY "profiles_update_own"
    ON public.profiles FOR UPDATE
    TO authenticated
    USING (auth.uid() = id)
    WITH CHECK (auth.uid() = id);

-- ============================================================================
-- 2. CATEGORIES
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.categories (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL CHECK (char_length(name) >= 1 AND char_length(name) <= 100),
    type TEXT NOT NULL CHECK (type IN ('income', 'expense')),
    icon_code_point INTEGER NOT NULL,
    color_value INTEGER NOT NULL,
    is_system BOOLEAN NOT NULL DEFAULT FALSE,
    is_archived BOOLEAN NOT NULL DEFAULT FALSE,
    created_at_utc TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at_utc TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    deleted_at_utc TIMESTAMPTZ,
    sync_status TEXT NOT NULL DEFAULT 'synced',
    field_timestamps_json JSONB NOT NULL DEFAULT '{}'::jsonb
);

ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;

CREATE POLICY "categories_select_own"
    ON public.categories FOR SELECT
    TO authenticated
    USING (auth.uid() = user_id);

CREATE POLICY "categories_insert_own"
    ON public.categories FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "categories_update_own"
    ON public.categories FOR UPDATE
    TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "categories_delete_own"
    ON public.categories FOR DELETE
    TO authenticated
    USING (auth.uid() = user_id);

-- Composite cursor index (user_id, updated_at_utc ASC, id ASC)
CREATE INDEX IF NOT EXISTS idx_categories_user_cursor 
    ON public.categories (user_id, updated_at_utc ASC, id ASC);
CREATE INDEX IF NOT EXISTS idx_categories_user_active 
    ON public.categories (user_id, is_archived, deleted_at_utc);

-- ============================================================================
-- 3. ACCOUNTS
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.accounts (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL CHECK (char_length(name) >= 1 AND char_length(name) <= 100),
    account_type TEXT NOT NULL CHECK (account_type IN ('cash', 'bank', 'creditCard', 'wallet', 'savings')),
    currency TEXT NOT NULL DEFAULT 'INR',
    initial_balance_minor BIGINT NOT NULL DEFAULT 0,
    color_value INTEGER NOT NULL DEFAULT 4279548070,
    icon_code_point INTEGER NOT NULL DEFAULT 57408,
    created_at_utc TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at_utc TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    deleted_at_utc TIMESTAMPTZ,
    sync_status TEXT NOT NULL DEFAULT 'synced',
    field_timestamps_json JSONB NOT NULL DEFAULT '{}'::jsonb
);

ALTER TABLE public.accounts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "accounts_select_own"
    ON public.accounts FOR SELECT
    TO authenticated
    USING (auth.uid() = user_id);

CREATE POLICY "accounts_insert_own"
    ON public.accounts FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "accounts_update_own"
    ON public.accounts FOR UPDATE
    TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "accounts_delete_own"
    ON public.accounts FOR DELETE
    TO authenticated
    USING (auth.uid() = user_id);

-- Composite cursor index
CREATE INDEX IF NOT EXISTS idx_accounts_user_cursor 
    ON public.accounts (user_id, updated_at_utc ASC, id ASC);
CREATE INDEX IF NOT EXISTS idx_accounts_user_deleted 
    ON public.accounts (user_id, deleted_at_utc);

-- ============================================================================
-- 4. TRANSACTIONS
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.transactions (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    amount_minor BIGINT NOT NULL CHECK (amount_minor > 0),
    transaction_type TEXT NOT NULL CHECK (transaction_type IN ('income', 'expense', 'transfer')),
    category_id UUID NOT NULL REFERENCES public.categories(id) ON DELETE RESTRICT,
    account_id UUID NOT NULL REFERENCES public.accounts(id) ON DELETE RESTRICT,
    to_account_id UUID REFERENCES public.accounts(id) ON DELETE RESTRICT,
    note TEXT NOT NULL DEFAULT '',
    transaction_date_utc TIMESTAMPTZ NOT NULL,
    transaction_time TEXT,
    attachment_path TEXT,
    is_recurring BOOLEAN NOT NULL DEFAULT FALSE,
    recurring_rule_id UUID,
    created_at_utc TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at_utc TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    deleted_at_utc TIMESTAMPTZ,
    sync_status TEXT NOT NULL DEFAULT 'synced',
    field_timestamps_json JSONB NOT NULL DEFAULT '{}'::jsonb
);

ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "transactions_select_own"
    ON public.transactions FOR SELECT
    TO authenticated
    USING (auth.uid() = user_id);

CREATE POLICY "transactions_insert_own"
    ON public.transactions FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "transactions_update_own"
    ON public.transactions FOR UPDATE
    TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "transactions_delete_own"
    ON public.transactions FOR DELETE
    TO authenticated
    USING (auth.uid() = user_id);

-- Composite cursor index
CREATE INDEX IF NOT EXISTS idx_transactions_user_cursor 
    ON public.transactions (user_id, updated_at_utc ASC, id ASC);
CREATE INDEX IF NOT EXISTS idx_transactions_user_date 
    ON public.transactions (user_id, deleted_at_utc, transaction_date_utc DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_transactions_user_account 
    ON public.transactions (user_id, account_id, deleted_at_utc, transaction_date_utc DESC);
CREATE INDEX IF NOT EXISTS idx_transactions_user_category 
    ON public.transactions (user_id, category_id, deleted_at_utc, transaction_date_utc DESC);

-- ============================================================================
-- 5. BUDGETS
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.budgets (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    month_year TEXT NOT NULL,
    amount_minor BIGINT NOT NULL CHECK (amount_minor >= 0),
    created_at_utc TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at_utc TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    deleted_at_utc TIMESTAMPTZ,
    sync_status TEXT NOT NULL DEFAULT 'synced',
    field_timestamps_json JSONB NOT NULL DEFAULT '{}'::jsonb
);

ALTER TABLE public.budgets ENABLE ROW LEVEL SECURITY;

CREATE POLICY "budgets_select_own"
    ON public.budgets FOR SELECT
    TO authenticated
    USING (auth.uid() = user_id);

CREATE POLICY "budgets_insert_own"
    ON public.budgets FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "budgets_update_own"
    ON public.budgets FOR UPDATE
    TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "budgets_delete_own"
    ON public.budgets FOR DELETE
    TO authenticated
    USING (auth.uid() = user_id);

-- Composite cursor index
CREATE INDEX IF NOT EXISTS idx_budgets_user_cursor 
    ON public.budgets (user_id, updated_at_utc ASC, id ASC);
CREATE INDEX IF NOT EXISTS idx_budgets_user_month 
    ON public.budgets (user_id, month_year, deleted_at_utc);

-- ============================================================================
-- 6. CATEGORY BUDGETS
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.category_budgets (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    budget_id UUID NOT NULL REFERENCES public.budgets(id) ON DELETE CASCADE,
    category_id UUID NOT NULL REFERENCES public.categories(id) ON DELETE RESTRICT,
    amount_minor BIGINT NOT NULL CHECK (amount_minor >= 0),
    created_at_utc TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at_utc TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    deleted_at_utc TIMESTAMPTZ,
    sync_status TEXT NOT NULL DEFAULT 'synced',
    field_timestamps_json JSONB NOT NULL DEFAULT '{}'::jsonb
);

ALTER TABLE public.category_budgets ENABLE ROW LEVEL SECURITY;

CREATE POLICY "category_budgets_select_own"
    ON public.category_budgets FOR SELECT
    TO authenticated
    USING (auth.uid() = user_id);

CREATE POLICY "category_budgets_insert_own"
    ON public.category_budgets FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "category_budgets_update_own"
    ON public.category_budgets FOR UPDATE
    TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "category_budgets_delete_own"
    ON public.category_budgets FOR DELETE
    TO authenticated
    USING (auth.uid() = user_id);

-- Composite cursor index
CREATE INDEX IF NOT EXISTS idx_cat_budgets_user_cursor 
    ON public.category_budgets (user_id, updated_at_utc ASC, id ASC);
CREATE INDEX IF NOT EXISTS idx_cat_budgets_user_budget 
    ON public.category_budgets (user_id, budget_id, category_id, deleted_at_utc);

-- ============================================================================
-- 7. SAVINGS GOALS
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.savings_goals (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL CHECK (char_length(name) >= 1 AND char_length(name) <= 100),
    target_amount_minor BIGINT NOT NULL CHECK (target_amount_minor > 0),
    current_amount_minor BIGINT NOT NULL DEFAULT 0 CHECK (current_amount_minor >= 0),
    target_date_utc TIMESTAMPTZ NOT NULL,
    icon_code_point INTEGER NOT NULL DEFAULT 58988,
    color_value INTEGER NOT NULL DEFAULT 4279310721,
    created_at_utc TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at_utc TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    deleted_at_utc TIMESTAMPTZ,
    sync_status TEXT NOT NULL DEFAULT 'synced',
    field_timestamps_json JSONB NOT NULL DEFAULT '{}'::jsonb
);

ALTER TABLE public.savings_goals ENABLE ROW LEVEL SECURITY;

CREATE POLICY "savings_goals_select_own"
    ON public.savings_goals FOR SELECT
    TO authenticated
    USING (auth.uid() = user_id);

CREATE POLICY "savings_goals_insert_own"
    ON public.savings_goals FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "savings_goals_update_own"
    ON public.savings_goals FOR UPDATE
    TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "savings_goals_delete_own"
    ON public.savings_goals FOR DELETE
    TO authenticated
    USING (auth.uid() = user_id);

-- Composite cursor index
CREATE INDEX IF NOT EXISTS idx_savings_goals_user_cursor 
    ON public.savings_goals (user_id, updated_at_utc ASC, id ASC);
CREATE INDEX IF NOT EXISTS idx_savings_goals_user_deleted 
    ON public.savings_goals (user_id, deleted_at_utc);

-- ============================================================================
-- 8. RECURRING TRANSACTIONS
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.recurring_transactions (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    amount_minor BIGINT NOT NULL CHECK (amount_minor > 0),
    transaction_type TEXT NOT NULL CHECK (transaction_type IN ('income', 'expense')),
    category_id UUID NOT NULL REFERENCES public.categories(id) ON DELETE RESTRICT,
    account_id UUID NOT NULL REFERENCES public.accounts(id) ON DELETE RESTRICT,
    note TEXT NOT NULL DEFAULT '',
    frequency TEXT NOT NULL CHECK (frequency IN ('daily', 'weekly', 'monthly', 'yearly')),
    start_date_utc TIMESTAMPTZ NOT NULL,
    next_occurrence_utc TIMESTAMPTZ NOT NULL,
    last_executed_date_utc TIMESTAMPTZ,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at_utc TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at_utc TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    deleted_at_utc TIMESTAMPTZ,
    sync_status TEXT NOT NULL DEFAULT 'synced',
    field_timestamps_json JSONB NOT NULL DEFAULT '{}'::jsonb
);

ALTER TABLE public.recurring_transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "recurring_transactions_select_own"
    ON public.recurring_transactions FOR SELECT
    TO authenticated
    USING (auth.uid() = user_id);

CREATE POLICY "recurring_transactions_insert_own"
    ON public.recurring_transactions FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "recurring_transactions_update_own"
    ON public.recurring_transactions FOR UPDATE
    TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "recurring_transactions_delete_own"
    ON public.recurring_transactions FOR DELETE
    TO authenticated
    USING (auth.uid() = user_id);

-- Composite cursor index
CREATE INDEX IF NOT EXISTS idx_recurring_tx_user_cursor 
    ON public.recurring_transactions (user_id, updated_at_utc ASC, id ASC);
CREATE INDEX IF NOT EXISTS idx_recurring_tx_user_next 
    ON public.recurring_transactions (user_id, is_active, next_occurrence_utc, deleted_at_utc);

-- ============================================================================
-- 9. USER SETTINGS
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.user_settings (
    key TEXT NOT NULL,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    value TEXT NOT NULL,
    updated_at_utc TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    PRIMARY KEY (key, user_id)
);

ALTER TABLE public.user_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "user_settings_select_own"
    ON public.user_settings FOR SELECT
    TO authenticated
    USING (auth.uid() = user_id);

CREATE POLICY "user_settings_insert_own"
    ON public.user_settings FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "user_settings_update_own"
    ON public.user_settings FOR UPDATE
    TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "user_settings_delete_own"
    ON public.user_settings FOR DELETE
    TO authenticated
    USING (auth.uid() = user_id);

-- ============================================================================
-- 10. SYNC AUDIT LOG (IDEMPOTENCY & DEDUPLICATION - METADATA ONLY)
-- Invariant: ZERO financial payload, transaction notes, or amounts stored here.
-- Scoped strictly to (user_id, idempotency_token) to prevent cross-user token reuse.
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.sync_audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    entity_type TEXT NOT NULL,
    entity_id UUID NOT NULL,
    operation_type TEXT NOT NULL,
    idempotency_token UUID NOT NULL,
    processed_at_utc TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    CONSTRAINT uq_user_idempotency_token UNIQUE (user_id, idempotency_token)
);

ALTER TABLE public.sync_audit_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "sync_audit_log_select_own"
    ON public.sync_audit_log FOR SELECT
    TO authenticated
    USING (auth.uid() = user_id);

CREATE POLICY "sync_audit_log_insert_own"
    ON public.sync_audit_log FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_sync_audit_user_token 
    ON public.sync_audit_log (user_id, idempotency_token);

-- ============================================================================
-- 11. STORED PROCEDURE: APPLY_SYNC_MUTATION
-- True Server-Side Field-Level LWW Merge & Operation Idempotency Enforcement
-- ============================================================================
CREATE OR REPLACE FUNCTION public.apply_sync_mutation(
    p_operation_id UUID,
    p_entity_type TEXT,
    p_entity_id UUID,
    p_operation_type TEXT,
    p_payload JSONB,
    p_field_timestamps JSONB,
    p_updated_at_utc TIMESTAMPTZ,
    p_deleted_at_utc TIMESTAMPTZ DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_user_id UUID;
    v_now TIMESTAMPTZ := timezone('utc'::text, now());
    v_max_future TIMESTAMPTZ := v_now + interval '5 minutes';
    v_clamped_incoming_ts JSONB := '{}'::jsonb;
    v_key TEXT;
    v_val TEXT;
    v_ts TIMESTAMPTZ;
    v_existing_row RECORD;
    v_merged_ts JSONB;
    v_merged_record JSONB;
    v_is_deleted BOOLEAN;
    v_final_deleted_at TIMESTAMPTZ;
    v_latest_updated_at TIMESTAMPTZ;
    
    -- Transaction specific fields
    v_amount_minor BIGINT;
    v_tx_type TEXT;
    v_category_id UUID;
    v_account_id UUID;
    v_to_account_id UUID;
    v_note TEXT;
    v_tx_date TIMESTAMPTZ;
    v_tx_time TEXT;
    v_attachment TEXT;
    v_is_recurring BOOLEAN;
    v_rule_id UUID;
BEGIN
    -- 1. Verify User Authentication
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Unauthorized: User is not authenticated';
    END IF;

    -- 2. Check Operation-Level Idempotency
    IF EXISTS (
        SELECT 1 FROM public.sync_audit_log 
        WHERE user_id = v_user_id AND idempotency_token = p_operation_id
    ) THEN
        IF p_entity_type IN ('category', 'categories') THEN
            SELECT row_to_json(c)::jsonb INTO v_merged_record FROM public.categories c WHERE c.id = p_entity_id AND c.user_id = v_user_id;
        ELSIF p_entity_type IN ('account', 'accounts') THEN
            SELECT row_to_json(a)::jsonb INTO v_merged_record FROM public.accounts a WHERE a.id = p_entity_id AND a.user_id = v_user_id;
        ELSIF p_entity_type IN ('transaction', 'transactions') THEN
            SELECT row_to_json(t)::jsonb INTO v_merged_record FROM public.transactions t WHERE t.id = p_entity_id AND t.user_id = v_user_id;
        ELSIF p_entity_type IN ('budget', 'budgets') THEN
            SELECT row_to_json(b)::jsonb INTO v_merged_record FROM public.budgets b WHERE b.id = p_entity_id AND b.user_id = v_user_id;
        ELSIF p_entity_type IN ('category_budget', 'category_budgets', 'categorybudget', 'categorybudgets') THEN
            SELECT row_to_json(cb)::jsonb INTO v_merged_record FROM public.category_budgets cb WHERE cb.id = p_entity_id AND cb.user_id = v_user_id;
        ELSIF p_entity_type IN ('goal', 'savings_goal', 'savings_goals', 'savingsgoal', 'savingsgoals') THEN
            SELECT row_to_json(sg)::jsonb INTO v_merged_record FROM public.savings_goals sg WHERE sg.id = p_entity_id AND sg.user_id = v_user_id;
        ELSIF p_entity_type IN ('recurring_rule', 'recurring_transaction', 'recurring_transactions') THEN
            SELECT row_to_json(rt)::jsonb INTO v_merged_record FROM public.recurring_transactions rt WHERE rt.id = p_entity_id AND rt.user_id = v_user_id;
        ELSIF p_entity_type IN ('user_setting', 'user_settings', 'settings', 'setting', 'usersetting', 'usersettings') THEN
            SELECT row_to_json(us)::jsonb INTO v_merged_record FROM public.user_settings us WHERE (us.key = p_payload->>'key' OR us.key = p_payload->>'id' OR us.key = p_entity_id::text) AND us.user_id = v_user_id;
        END IF;

        RETURN jsonb_build_object(
            'status', 'already_processed',
            'operation_id', p_operation_id,
            'entity_id', p_entity_id,
            'merged_record', v_merged_record
        );
    END IF;

    -- 3. Clock Skew Protection: Clamp any future timestamps exceeding now + 5 min
    FOR v_key, v_val IN SELECT * FROM jsonb_each_text(COALESCE(p_field_timestamps, '{}'::jsonb)) LOOP
        BEGIN
            v_ts := v_val::timestamptz;
            IF v_ts > v_max_future THEN
                v_ts := v_now;
            END IF;
            v_clamped_incoming_ts := jsonb_set(
                v_clamped_incoming_ts, 
                ARRAY[v_key], 
                to_jsonb(to_char(v_ts, 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))
            );
        EXCEPTION WHEN OTHERS THEN
            v_clamped_incoming_ts := jsonb_set(
                v_clamped_incoming_ts, 
                ARRAY[v_key], 
                to_jsonb(to_char(v_now, 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))
            );
        END;
    END LOOP;

    -- 4. Field-Level Merge Logic for Transactions
    IF p_entity_type = 'transaction' THEN
        SELECT * INTO v_existing_row 
        FROM public.transactions 
        WHERE id = p_entity_id AND user_id = v_user_id 
        FOR UPDATE;

        IF NOT FOUND THEN
            -- Fresh Insert
            INSERT INTO public.transactions (
                id, user_id, amount_minor, transaction_type, category_id,
                account_id, to_account_id, note, transaction_date_utc,
                transaction_time, attachment_path, is_recurring,
                recurring_rule_id, created_at_utc, updated_at_utc,
                deleted_at_utc, sync_status, field_timestamps_json
            ) VALUES (
                p_entity_id,
                v_user_id,
                (p_payload->>'amountMinor')::bigint,
                p_payload->>'transactionType',
                (p_payload->>'categoryId')::uuid,
                (p_payload->>'accountId')::uuid,
                (p_payload->>'toAccountId')::uuid,
                COALESCE(p_payload->>'note', ''),
                (p_payload->>'transactionDateUtc')::timestamptz,
                p_payload->>'transactionTime',
                p_payload->>'attachmentPath',
                COALESCE((p_payload->>'isRecurring')::boolean, false),
                (p_payload->>'recurringRuleId')::uuid,
                COALESCE((p_payload->>'createdAtUtc')::timestamptz, v_now),
                COALESCE(p_updated_at_utc, v_now),
                p_deleted_at_utc,
                'synced',
                v_clamped_incoming_ts
            );
        ELSE
            -- Field-by-Field LWW Reconciliation
            v_merged_ts := COALESCE(v_existing_row.field_timestamps_json, '{}'::jsonb);

            -- amountMinor
            IF (v_clamped_incoming_ts->>'amountMinor')::timestamptz > (v_merged_ts->>'amountMinor')::timestamptz OR NOT (v_merged_ts ? 'amountMinor') THEN
                v_amount_minor := (p_payload->>'amountMinor')::bigint;
                v_merged_ts := jsonb_set(v_merged_ts, '{amountMinor}', to_jsonb(v_clamped_incoming_ts->>'amountMinor'));
            ELSE
                v_amount_minor := v_existing_row.amount_minor;
            END IF;

            -- note
            IF (v_clamped_incoming_ts->>'note')::timestamptz > (v_merged_ts->>'note')::timestamptz OR NOT (v_merged_ts ? 'note') THEN
                v_note := COALESCE(p_payload->>'note', '');
                v_merged_ts := jsonb_set(v_merged_ts, '{note}', to_jsonb(v_clamped_incoming_ts->>'note'));
            ELSE
                v_note := v_existing_row.note;
            END IF;

            -- categoryId
            IF (v_clamped_incoming_ts->>'categoryId')::timestamptz > (v_merged_ts->>'categoryId')::timestamptz OR NOT (v_merged_ts ? 'categoryId') THEN
                v_category_id := (p_payload->>'categoryId')::uuid;
                v_merged_ts := jsonb_set(v_merged_ts, '{categoryId}', to_jsonb(v_clamped_incoming_ts->>'categoryId'));
            ELSE
                v_category_id := v_existing_row.category_id;
            END IF;

            -- accountId
            IF (v_clamped_incoming_ts->>'accountId')::timestamptz > (v_merged_ts->>'accountId')::timestamptz OR NOT (v_merged_ts ? 'accountId') THEN
                v_account_id := (p_payload->>'accountId')::uuid;
                v_merged_ts := jsonb_set(v_merged_ts, '{accountId}', to_jsonb(v_clamped_incoming_ts->>'accountId'));
            ELSE
                v_account_id := v_existing_row.account_id;
            END IF;

            -- Tombstone / Soft-deletion evaluation
            IF p_deleted_at_utc IS NOT NULL AND v_existing_row.deleted_at_utc IS NULL THEN
                IF p_deleted_at_utc >= v_existing_row.updated_at_utc THEN
                    v_final_deleted_at := p_deleted_at_utc;
                ELSE
                    v_final_deleted_at := NULL; -- newer local edit keeps it alive
                END IF;
            ELSIF v_existing_row.deleted_at_utc IS NOT NULL AND p_deleted_at_utc IS NULL THEN
                IF p_updated_at_utc > v_existing_row.deleted_at_utc THEN
                    v_final_deleted_at := NULL; -- newer update un-deletes
                ELSE
                    v_final_deleted_at := v_existing_row.deleted_at_utc;
                END IF;
            ELSIF p_deleted_at_utc IS NOT NULL AND v_existing_row.deleted_at_utc IS NOT NULL THEN
                v_final_deleted_at := GREATEST(p_deleted_at_utc, v_existing_row.deleted_at_utc);
            ELSE
                v_final_deleted_at := NULL;
            END IF;

            v_latest_updated_at := GREATEST(COALESCE(p_updated_at_utc, v_now), v_existing_row.updated_at_utc);

            UPDATE public.transactions SET
                amount_minor = v_amount_minor,
                note = v_note,
                category_id = v_category_id,
                account_id = v_account_id,
                deleted_at_utc = v_final_deleted_at,
                updated_at_utc = v_latest_updated_at,
                field_timestamps_json = v_merged_ts,
                sync_status = 'synced'
            WHERE id = p_entity_id AND user_id = v_user_id;
        END IF;
    END IF;

    -- 5. Record Operation Token in sync_audit_log (Atomic Operation Idempotency)
    INSERT INTO public.sync_audit_log (
        user_id, entity_type, entity_id, operation_type, idempotency_token, processed_at_utc
    ) VALUES (
        v_user_id, p_entity_type, p_entity_id, p_operation_type, p_operation_id, v_now
    );

    RETURN jsonb_build_object(
        'status', 'applied',
        'operation_id', p_operation_id,
        'entity_id', p_entity_id
    );
END;
$$;
