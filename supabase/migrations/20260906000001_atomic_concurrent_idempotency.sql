-- ============================================================================
-- OFFLINE-FIRST EXPENSE TRACKER: SUPABASE CLOUD SCHEMA MIGRATION
-- Migration Version: 20260906000001_atomic_concurrent_idempotency.sql
-- Purpose:
--   1. Enforce TRUE concurrent operation-level idempotency via PostgreSQL transaction-level advisory locking (pg_advisory_xact_lock).
--   2. Implement exact cross-layer canonical JSON total ordering in PostgreSQL (public.canonical_json, public.deterministic_field_winner)
--      guaranteeing: mergeClient(A, B) == mergeClient(B, A) == mergeServer(A, B) == mergeServer(B, A).
--   3. Expand apply_sync_mutation field-level LWW merge coverage across all entity types.
-- ============================================================================

-- ============================================================================
-- 1. CANONICAL JSON RECURSIVE SERIALIZATION (EXACT EQUIVALENT OF CLIENT DART)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.canonical_json(p_val JSONB)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_type TEXT;
    v_key TEXT;
    v_elem JSONB;
    v_first BOOLEAN := true;
    v_res TEXT;
BEGIN
    IF p_val IS NULL THEN
        RETURN 'null';
    END IF;

    v_type := jsonb_typeof(p_val);

    IF v_type = 'null' THEN
        RETURN 'null';
    ELSIF v_type = 'boolean' THEN
        RETURN p_val::text;
    ELSIF v_type = 'number' THEN
        RETURN p_val::text;
    ELSIF v_type = 'string' THEN
        RETURN to_json(p_val #>> '{}')::text;
    ELSIF v_type = 'array' THEN
        v_res := '[';
        FOR v_elem IN SELECT jsonb_array_elements(p_val) LOOP
            IF NOT v_first THEN
                v_res := v_res || ',';
            END IF;
            v_res := v_res || public.canonical_json(v_elem);
            v_first := false;
        END LOOP;
        RETURN v_res || ']';
    ELSIF v_type = 'object' THEN
        v_res := '{';
        FOR v_key IN SELECT key FROM jsonb_each(p_val) ORDER BY key COLLATE "C" ASC LOOP
            IF NOT v_first THEN
                v_res := v_res || ',';
            END IF;
            v_res := v_res || to_json(v_key)::text || ':' || public.canonical_json(p_val -> v_key);
            v_first := false;
        END LOOP;
        RETURN v_res || '}';
    ELSE
        RETURN p_val::text;
    END IF;
END;
$$;

-- ============================================================================
-- 2. DETERMINISTIC FIELD-LEVEL WINNER EVALUATION (TOTAL ORDER OVER VALID STATES)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.deterministic_field_winner(
    p_incoming_val JSONB,
    p_incoming_ts TIMESTAMPTZ,
    p_existing_val JSONB,
    p_existing_ts TIMESTAMPTZ
)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_incoming_canon TEXT;
    v_existing_canon TEXT;
    v_incoming_is_null BOOLEAN;
    v_existing_is_null BOOLEAN;
BEGIN
    -- 1. If existing record has no timestamp for this field, incoming strictly wins
    IF p_existing_ts IS NULL THEN
        RETURN TRUE;
    END IF;

    -- 2. If incoming payload has no timestamp for this field, existing is retained
    IF p_incoming_ts IS NULL THEN
        RETURN FALSE;
    END IF;

    -- 3. Differing timestamps: newer strictly wins (Field-Level LWW)
    IF p_incoming_ts > p_existing_ts THEN
        RETURN TRUE;
    ELSIF p_existing_ts > p_incoming_ts THEN
        RETURN FALSE;
    END IF;

    -- 4. Equal timestamps: Deterministic intrinsic tie-break (Cross-layer identical total order)
    v_incoming_canon := public.canonical_json(p_incoming_val);
    v_existing_canon := public.canonical_json(p_existing_val);

    -- Identical canonical representation -> clean no-op (keep existing)
    IF v_incoming_canon = v_existing_canon THEN
        RETURN FALSE;
    END IF;

    v_incoming_is_null := (p_incoming_val IS NULL OR jsonb_typeof(p_incoming_val) = 'null');
    v_existing_is_null := (p_existing_val IS NULL OR jsonb_typeof(p_existing_val) = 'null');

    -- Deterministic intrinsic tie-break: Non-null takes precedence over null
    IF NOT v_incoming_is_null AND v_existing_is_null THEN
        RETURN TRUE;
    ELSIF v_incoming_is_null AND NOT v_existing_is_null THEN
        RETURN FALSE;
    END IF;

    -- Both are non-null and distinct: Lexicographical comparison under COLLATE "C"
    -- Incoming wins if and only if incoming canonical string > existing canonical string
    IF (v_incoming_canon COLLATE "C") > (v_existing_canon COLLATE "C") THEN
        RETURN TRUE;
    ELSE
        RETURN FALSE;
    END IF;
END;
$$;

-- ============================================================================
-- 3. APPLY_SYNC_MUTATION STORED PROCEDURE
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
    v_final_deleted_at TIMESTAMPTZ;
    v_latest_updated_at TIMESTAMPTZ;
    v_lock_key BIGINT;
    v_merged_record JSONB := NULL;
    
    -- Transaction entity fields
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

    -- Category entity fields
    v_name TEXT;
    v_cat_type TEXT;
    v_icon_code_point INTEGER;
    v_color_value INTEGER;
    v_is_system BOOLEAN;
    v_is_archived BOOLEAN;

    -- Account entity fields
    v_account_type TEXT;
    v_currency TEXT;
    v_initial_balance_minor BIGINT;

    -- Budget entity fields
    v_month_year TEXT;
    v_budget_id UUID;
    v_target_amount_minor BIGINT;

    -- Savings goal entity fields
    v_current_amount_minor BIGINT;
    v_target_date_utc TIMESTAMPTZ;

    -- Recurring transaction entity fields
    v_frequency TEXT;
    v_start_date_utc TIMESTAMPTZ;
    v_next_occurrence_utc TIMESTAMPTZ;
    v_last_executed_date_utc TIMESTAMPTZ;
    v_is_active BOOLEAN;
BEGIN
    -- 1. Verify User Authentication
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Unauthorized: User is not authenticated';
    END IF;

    -- 2. Concurrency Control: Acquire Transaction-Level Advisory Lock Scoped to (user_id, operation_id)
    v_lock_key := hashtext(v_user_id::text || ':' || p_operation_id::text);
    PERFORM pg_advisory_xact_lock(v_lock_key);

    -- 3. Check Operation-Level Idempotency (Safe under exclusive advisory lock)
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

    -- 4. Clock Skew Protection: Clamp any future timestamps exceeding now + 5 min
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

    -- 5. Field-Level Merge by Entity Type with Deterministic Cross-Layer Tie-Breaking
    IF p_entity_type IN ('transaction', 'transactions') THEN
        SELECT * INTO v_existing_row 
        FROM public.transactions 
        WHERE id = p_entity_id AND user_id = v_user_id 
        FOR UPDATE;

        IF NOT FOUND THEN
            INSERT INTO public.transactions (
                id, user_id, amount_minor, transaction_type, category_id,
                account_id, to_account_id, note, transaction_date_utc,
                transaction_time, attachment_path, is_recurring,
                recurring_rule_id, created_at_utc, updated_at_utc,
                deleted_at_utc, sync_status, field_timestamps_json
            ) VALUES (
                p_entity_id,
                v_user_id,
                COALESCE((p_payload->>'amountMinor')::bigint, (p_payload->>'amount_minor')::bigint, 0),
                COALESCE(p_payload->>'transactionType', p_payload->>'transaction_type', 'expense'),
                COALESCE((p_payload->>'categoryId')::uuid, (p_payload->>'category_id')::uuid),
                COALESCE((p_payload->>'accountId')::uuid, (p_payload->>'account_id')::uuid),
                COALESCE((p_payload->>'toAccountId')::uuid, (p_payload->>'to_account_id')::uuid),
                COALESCE(p_payload->>'note', ''),
                COALESCE((p_payload->>'transactionDateUtc')::timestamptz, (p_payload->>'transaction_date_utc')::timestamptz, v_now),
                COALESCE(p_payload->>'transactionTime', p_payload->>'transaction_time'),
                COALESCE(p_payload->>'attachmentPath', p_payload->>'attachment_path'),
                COALESCE((p_payload->>'isRecurring')::boolean, (p_payload->>'is_recurring')::boolean, false),
                COALESCE((p_payload->>'recurringRuleId')::uuid, (p_payload->>'recurring_rule_id')::uuid),
                COALESCE((p_payload->>'createdAtUtc')::timestamptz, (p_payload->>'created_at_utc')::timestamptz, v_now),
                COALESCE(p_updated_at_utc, v_now),
                p_deleted_at_utc,
                'synced',
                v_clamped_incoming_ts
            );
        ELSE
            v_merged_ts := COALESCE(v_existing_row.field_timestamps_json, '{}'::jsonb);

            -- amountMinor
            IF public.deterministic_field_winner(
                COALESCE(p_payload->'amountMinor', p_payload->'amount_minor', 'null'::jsonb),
                (v_clamped_incoming_ts->>'amountMinor')::timestamptz,
                to_jsonb(v_existing_row.amount_minor),
                (v_merged_ts->>'amountMinor')::timestamptz
            ) THEN
                v_amount_minor := COALESCE((p_payload->>'amountMinor')::bigint, (p_payload->>'amount_minor')::bigint, v_existing_row.amount_minor);
                v_merged_ts := jsonb_set(v_merged_ts, '{amountMinor}', to_jsonb(v_clamped_incoming_ts->>'amountMinor'));
            ELSE
                v_amount_minor := v_existing_row.amount_minor;
            END IF;

            -- transactionType
            IF public.deterministic_field_winner(
                COALESCE(p_payload->'transactionType', p_payload->'transaction_type', 'null'::jsonb),
                (v_clamped_incoming_ts->>'transactionType')::timestamptz,
                to_jsonb(v_existing_row.transaction_type),
                (v_merged_ts->>'transactionType')::timestamptz
            ) THEN
                v_tx_type := COALESCE(p_payload->>'transactionType', p_payload->>'transaction_type', v_existing_row.transaction_type);
                v_merged_ts := jsonb_set(v_merged_ts, '{transactionType}', to_jsonb(v_clamped_incoming_ts->>'transactionType'));
            ELSE
                v_tx_type := v_existing_row.transaction_type;
            END IF;

            -- note
            IF public.deterministic_field_winner(
                COALESCE(p_payload->'note', 'null'::jsonb),
                (v_clamped_incoming_ts->>'note')::timestamptz,
                to_jsonb(v_existing_row.note),
                (v_merged_ts->>'note')::timestamptz
            ) THEN
                v_note := COALESCE(p_payload->>'note', v_existing_row.note);
                v_merged_ts := jsonb_set(v_merged_ts, '{note}', to_jsonb(v_clamped_incoming_ts->>'note'));
            ELSE
                v_note := v_existing_row.note;
            END IF;

            -- categoryId
            IF public.deterministic_field_winner(
                COALESCE(p_payload->'categoryId', p_payload->'category_id', 'null'::jsonb),
                (v_clamped_incoming_ts->>'categoryId')::timestamptz,
                to_jsonb(v_existing_row.category_id),
                (v_merged_ts->>'categoryId')::timestamptz
            ) THEN
                v_category_id := COALESCE((p_payload->>'categoryId')::uuid, (p_payload->>'category_id')::uuid, v_existing_row.category_id);
                v_merged_ts := jsonb_set(v_merged_ts, '{categoryId}', to_jsonb(v_clamped_incoming_ts->>'categoryId'));
            ELSE
                v_category_id := v_existing_row.category_id;
            END IF;

            -- accountId
            IF public.deterministic_field_winner(
                COALESCE(p_payload->'accountId', p_payload->'account_id', 'null'::jsonb),
                (v_clamped_incoming_ts->>'accountId')::timestamptz,
                to_jsonb(v_existing_row.account_id),
                (v_merged_ts->>'accountId')::timestamptz
            ) THEN
                v_account_id := COALESCE((p_payload->>'accountId')::uuid, (p_payload->>'account_id')::uuid, v_existing_row.account_id);
                v_merged_ts := jsonb_set(v_merged_ts, '{accountId}', to_jsonb(v_clamped_incoming_ts->>'accountId'));
            ELSE
                v_account_id := v_existing_row.account_id;
            END IF;

            -- toAccountId
            IF public.deterministic_field_winner(
                COALESCE(p_payload->'toAccountId', p_payload->'to_account_id', 'null'::jsonb),
                (v_clamped_incoming_ts->>'toAccountId')::timestamptz,
                to_jsonb(v_existing_row.to_account_id),
                (v_merged_ts->>'toAccountId')::timestamptz
            ) THEN
                v_to_account_id := COALESCE((p_payload->>'toAccountId')::uuid, (p_payload->>'to_account_id')::uuid, v_existing_row.to_account_id);
                v_merged_ts := jsonb_set(v_merged_ts, '{toAccountId}', to_jsonb(v_clamped_incoming_ts->>'toAccountId'));
            ELSE
                v_to_account_id := v_existing_row.to_account_id;
            END IF;

            -- Tombstone evaluation (Delete strictly prevails on equal timestamp)
            IF p_deleted_at_utc IS NOT NULL AND v_existing_row.deleted_at_utc IS NULL THEN
                IF p_deleted_at_utc >= v_existing_row.updated_at_utc THEN
                    v_final_deleted_at := p_deleted_at_utc;
                ELSE
                    v_final_deleted_at := NULL;
                END IF;
            ELSIF v_existing_row.deleted_at_utc IS NOT NULL AND p_deleted_at_utc IS NULL THEN
                IF p_updated_at_utc > v_existing_row.deleted_at_utc THEN
                    v_final_deleted_at := NULL;
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
                transaction_type = v_tx_type,
                note = v_note,
                category_id = v_category_id,
                account_id = v_account_id,
                to_account_id = v_to_account_id,
                deleted_at_utc = v_final_deleted_at,
                updated_at_utc = v_latest_updated_at,
                field_timestamps_json = v_merged_ts,
                sync_status = 'synced'
            WHERE id = p_entity_id AND user_id = v_user_id;
        END IF;

        SELECT row_to_json(t)::jsonb INTO v_merged_record 
        FROM public.transactions t 
        WHERE t.id = p_entity_id AND t.user_id = v_user_id;

    ELSIF p_entity_type IN ('category', 'categories') THEN
        SELECT * INTO v_existing_row 
        FROM public.categories 
        WHERE id = p_entity_id AND user_id = v_user_id 
        FOR UPDATE;

        IF NOT FOUND THEN
            INSERT INTO public.categories (
                id, user_id, name, type, icon_code_point, color_value,
                is_system, is_archived, created_at_utc, updated_at_utc,
                deleted_at_utc, sync_status, field_timestamps_json
            ) VALUES (
                p_entity_id,
                v_user_id,
                COALESCE(p_payload->>'name', 'General'),
                COALESCE(p_payload->>'type', 'expense'),
                COALESCE((p_payload->>'iconCodePoint')::integer, (p_payload->>'icon_code_point')::integer, 58988),
                COALESCE((p_payload->>'colorValue')::integer, (p_payload->>'color_value')::integer, 4279548070),
                COALESCE((p_payload->>'isSystem')::boolean, (p_payload->>'is_system')::boolean, false),
                COALESCE((p_payload->>'isArchived')::boolean, (p_payload->>'is_archived')::boolean, false),
                COALESCE((p_payload->>'createdAtUtc')::timestamptz, (p_payload->>'created_at_utc')::timestamptz, v_now),
                COALESCE(p_updated_at_utc, v_now),
                p_deleted_at_utc,
                'synced',
                v_clamped_incoming_ts
            );
        ELSE
            v_merged_ts := COALESCE(v_existing_row.field_timestamps_json, '{}'::jsonb);

            -- name
            IF public.deterministic_field_winner(
                COALESCE(p_payload->'name', 'null'::jsonb),
                (v_clamped_incoming_ts->>'name')::timestamptz,
                to_jsonb(v_existing_row.name),
                (v_merged_ts->>'name')::timestamptz
            ) THEN
                v_name := COALESCE(p_payload->>'name', v_existing_row.name);
                v_merged_ts := jsonb_set(v_merged_ts, '{name}', to_jsonb(v_clamped_incoming_ts->>'name'));
            ELSE
                v_name := v_existing_row.name;
            END IF;

            -- type
            IF public.deterministic_field_winner(
                COALESCE(p_payload->'type', 'null'::jsonb),
                (v_clamped_incoming_ts->>'type')::timestamptz,
                to_jsonb(v_existing_row.type),
                (v_merged_ts->>'type')::timestamptz
            ) THEN
                v_cat_type := COALESCE(p_payload->>'type', v_existing_row.type);
                v_merged_ts := jsonb_set(v_merged_ts, '{type}', to_jsonb(v_clamped_incoming_ts->>'type'));
            ELSE
                v_cat_type := v_existing_row.type;
            END IF;

            -- iconCodePoint
            IF public.deterministic_field_winner(
                COALESCE(p_payload->'iconCodePoint', p_payload->'icon_code_point', 'null'::jsonb),
                (v_clamped_incoming_ts->>'iconCodePoint')::timestamptz,
                to_jsonb(v_existing_row.icon_code_point),
                (v_merged_ts->>'iconCodePoint')::timestamptz
            ) THEN
                v_icon_code_point := COALESCE((p_payload->>'iconCodePoint')::integer, (p_payload->>'icon_code_point')::integer, v_existing_row.icon_code_point);
                v_merged_ts := jsonb_set(v_merged_ts, '{iconCodePoint}', to_jsonb(v_clamped_incoming_ts->>'iconCodePoint'));
            ELSE
                v_icon_code_point := v_existing_row.icon_code_point;
            END IF;

            -- colorValue
            IF public.deterministic_field_winner(
                COALESCE(p_payload->'colorValue', p_payload->'color_value', 'null'::jsonb),
                (v_clamped_incoming_ts->>'colorValue')::timestamptz,
                to_jsonb(v_existing_row.color_value),
                (v_merged_ts->>'colorValue')::timestamptz
            ) THEN
                v_color_value := COALESCE((p_payload->>'colorValue')::integer, (p_payload->>'color_value')::integer, v_existing_row.color_value);
                v_merged_ts := jsonb_set(v_merged_ts, '{colorValue}', to_jsonb(v_clamped_incoming_ts->>'colorValue'));
            ELSE
                v_color_value := v_existing_row.color_value;
            END IF;

            -- Tombstone evaluation
            IF p_deleted_at_utc IS NOT NULL AND v_existing_row.deleted_at_utc IS NULL THEN
                IF p_deleted_at_utc >= v_existing_row.updated_at_utc THEN
                    v_final_deleted_at := p_deleted_at_utc;
                ELSE
                    v_final_deleted_at := NULL;
                END IF;
            ELSIF v_existing_row.deleted_at_utc IS NOT NULL AND p_deleted_at_utc IS NULL THEN
                IF p_updated_at_utc > v_existing_row.deleted_at_utc THEN
                    v_final_deleted_at := NULL;
                ELSE
                    v_final_deleted_at := v_existing_row.deleted_at_utc;
                END IF;
            ELSIF p_deleted_at_utc IS NOT NULL AND v_existing_row.deleted_at_utc IS NOT NULL THEN
                v_final_deleted_at := GREATEST(p_deleted_at_utc, v_existing_row.deleted_at_utc);
            ELSE
                v_final_deleted_at := NULL;
            END IF;

            v_latest_updated_at := GREATEST(COALESCE(p_updated_at_utc, v_now), v_existing_row.updated_at_utc);

            UPDATE public.categories SET
                name = v_name,
                type = v_cat_type,
                icon_code_point = v_icon_code_point,
                color_value = v_color_value,
                deleted_at_utc = v_final_deleted_at,
                updated_at_utc = v_latest_updated_at,
                field_timestamps_json = v_merged_ts,
                sync_status = 'synced'
            WHERE id = p_entity_id AND user_id = v_user_id;
        END IF;

        SELECT row_to_json(c)::jsonb INTO v_merged_record 
        FROM public.categories c 
        WHERE c.id = p_entity_id AND c.user_id = v_user_id;

    ELSIF p_entity_type IN ('account', 'accounts') THEN
        SELECT * INTO v_existing_row 
        FROM public.accounts 
        WHERE id = p_entity_id AND user_id = v_user_id 
        FOR UPDATE;

        IF NOT FOUND THEN
            INSERT INTO public.accounts (
                id, user_id, name, account_type, currency, initial_balance_minor,
                color_value, icon_code_point, created_at_utc, updated_at_utc,
                deleted_at_utc, sync_status, field_timestamps_json
            ) VALUES (
                p_entity_id,
                v_user_id,
                COALESCE(p_payload->>'name', 'Account'),
                COALESCE(p_payload->>'accountType', p_payload->>'account_type', 'cash'),
                COALESCE(p_payload->>'currency', 'INR'),
                COALESCE((p_payload->>'initialBalanceMinor')::bigint, (p_payload->>'initial_balance_minor')::bigint, 0),
                COALESCE((p_payload->>'colorValue')::integer, (p_payload->>'color_value')::integer, 4279548070),
                COALESCE((p_payload->>'iconCodePoint')::integer, (p_payload->>'icon_code_point')::integer, 57408),
                COALESCE((p_payload->>'createdAtUtc')::timestamptz, (p_payload->>'created_at_utc')::timestamptz, v_now),
                COALESCE(p_updated_at_utc, v_now),
                p_deleted_at_utc,
                'synced',
                v_clamped_incoming_ts
            );
        ELSE
            v_merged_ts := COALESCE(v_existing_row.field_timestamps_json, '{}'::jsonb);

            -- name
            IF public.deterministic_field_winner(
                COALESCE(p_payload->'name', 'null'::jsonb),
                (v_clamped_incoming_ts->>'name')::timestamptz,
                to_jsonb(v_existing_row.name),
                (v_merged_ts->>'name')::timestamptz
            ) THEN
                v_name := COALESCE(p_payload->>'name', v_existing_row.name);
                v_merged_ts := jsonb_set(v_merged_ts, '{name}', to_jsonb(v_clamped_incoming_ts->>'name'));
            ELSE
                v_name := v_existing_row.name;
            END IF;

            -- accountType
            IF public.deterministic_field_winner(
                COALESCE(p_payload->'accountType', p_payload->'account_type', 'null'::jsonb),
                (v_clamped_incoming_ts->>'accountType')::timestamptz,
                to_jsonb(v_existing_row.account_type),
                (v_merged_ts->>'accountType')::timestamptz
            ) THEN
                v_account_type := COALESCE(p_payload->>'accountType', p_payload->>'account_type', v_existing_row.account_type);
                v_merged_ts := jsonb_set(v_merged_ts, '{accountType}', to_jsonb(v_clamped_incoming_ts->>'accountType'));
            ELSE
                v_account_type := v_existing_row.account_type;
            END IF;

            -- currency
            IF public.deterministic_field_winner(
                COALESCE(p_payload->'currency', 'null'::jsonb),
                (v_clamped_incoming_ts->>'currency')::timestamptz,
                to_jsonb(v_existing_row.currency),
                (v_merged_ts->>'currency')::timestamptz
            ) THEN
                v_currency := COALESCE(p_payload->>'currency', v_existing_row.currency);
                v_merged_ts := jsonb_set(v_merged_ts, '{currency}', to_jsonb(v_clamped_incoming_ts->>'currency'));
            ELSE
                v_currency := v_existing_row.currency;
            END IF;

            -- initialBalanceMinor
            IF public.deterministic_field_winner(
                COALESCE(p_payload->'initialBalanceMinor', p_payload->'initial_balance_minor', 'null'::jsonb),
                (v_clamped_incoming_ts->>'initialBalanceMinor')::timestamptz,
                to_jsonb(v_existing_row.initial_balance_minor),
                (v_merged_ts->>'initialBalanceMinor')::timestamptz
            ) THEN
                v_initial_balance_minor := COALESCE((p_payload->>'initialBalanceMinor')::bigint, (p_payload->>'initial_balance_minor')::bigint, v_existing_row.initial_balance_minor);
                v_merged_ts := jsonb_set(v_merged_ts, '{initialBalanceMinor}', to_jsonb(v_clamped_incoming_ts->>'initialBalanceMinor'));
            ELSE
                v_initial_balance_minor := v_existing_row.initial_balance_minor;
            END IF;

            -- Tombstone evaluation
            IF p_deleted_at_utc IS NOT NULL AND v_existing_row.deleted_at_utc IS NULL THEN
                IF p_deleted_at_utc >= v_existing_row.updated_at_utc THEN
                    v_final_deleted_at := p_deleted_at_utc;
                ELSE
                    v_final_deleted_at := NULL;
                END IF;
            ELSIF v_existing_row.deleted_at_utc IS NOT NULL AND p_deleted_at_utc IS NULL THEN
                IF p_updated_at_utc > v_existing_row.deleted_at_utc THEN
                    v_final_deleted_at := NULL;
                ELSE
                    v_final_deleted_at := v_existing_row.deleted_at_utc;
                END IF;
            ELSIF p_deleted_at_utc IS NOT NULL AND v_existing_row.deleted_at_utc IS NOT NULL THEN
                v_final_deleted_at := GREATEST(p_deleted_at_utc, v_existing_row.deleted_at_utc);
            ELSE
                v_final_deleted_at := NULL;
            END IF;

            v_latest_updated_at := GREATEST(COALESCE(p_updated_at_utc, v_now), v_existing_row.updated_at_utc);

            UPDATE public.accounts SET
                name = v_name,
                account_type = v_account_type,
                currency = v_currency,
                initial_balance_minor = v_initial_balance_minor,
                deleted_at_utc = v_final_deleted_at,
                updated_at_utc = v_latest_updated_at,
                field_timestamps_json = v_merged_ts,
                sync_status = 'synced'
            WHERE id = p_entity_id AND user_id = v_user_id;
        END IF;

        SELECT row_to_json(a)::jsonb INTO v_merged_record 
        FROM public.accounts a 
        WHERE a.id = p_entity_id AND a.user_id = v_user_id;

    ELSIF p_entity_type IN ('budget', 'budgets') THEN
        SELECT * INTO v_existing_row 
        FROM public.budgets 
        WHERE id = p_entity_id AND user_id = v_user_id 
        FOR UPDATE;

        IF NOT FOUND THEN
            INSERT INTO public.budgets (
                id, user_id, month_year, amount_minor, created_at_utc,
                updated_at_utc, deleted_at_utc, sync_status, field_timestamps_json
            ) VALUES (
                p_entity_id,
                v_user_id,
                COALESCE(p_payload->>'monthYear', p_payload->>'month_year', to_char(v_now, 'YYYY-MM')),
                COALESCE((p_payload->>'amountMinor')::bigint, (p_payload->>'amount_minor')::bigint, 0),
                COALESCE((p_payload->>'createdAtUtc')::timestamptz, (p_payload->>'created_at_utc')::timestamptz, v_now),
                COALESCE(p_updated_at_utc, v_now),
                p_deleted_at_utc,
                'synced',
                v_clamped_incoming_ts
            );
        ELSE
            v_merged_ts := COALESCE(v_existing_row.field_timestamps_json, '{}'::jsonb);

            -- amountMinor
            IF public.deterministic_field_winner(
                COALESCE(p_payload->'amountMinor', p_payload->'amount_minor', 'null'::jsonb),
                (v_clamped_incoming_ts->>'amountMinor')::timestamptz,
                to_jsonb(v_existing_row.amount_minor),
                (v_merged_ts->>'amountMinor')::timestamptz
            ) THEN
                v_target_amount_minor := COALESCE((p_payload->>'amountMinor')::bigint, (p_payload->>'amount_minor')::bigint, v_existing_row.amount_minor);
                v_merged_ts := jsonb_set(v_merged_ts, '{amountMinor}', to_jsonb(v_clamped_incoming_ts->>'amountMinor'));
            ELSE
                v_target_amount_minor := v_existing_row.amount_minor;
            END IF;

            -- monthYear
            IF public.deterministic_field_winner(
                COALESCE(p_payload->'monthYear', p_payload->'month_year', 'null'::jsonb),
                (v_clamped_incoming_ts->>'monthYear')::timestamptz,
                to_jsonb(v_existing_row.month_year),
                (v_merged_ts->>'monthYear')::timestamptz
            ) THEN
                v_month_year := COALESCE(p_payload->>'monthYear', p_payload->>'month_year', v_existing_row.month_year);
                v_merged_ts := jsonb_set(v_merged_ts, '{monthYear}', to_jsonb(v_clamped_incoming_ts->>'monthYear'));
            ELSE
                v_month_year := v_existing_row.month_year;
            END IF;

            -- Tombstone evaluation
            IF p_deleted_at_utc IS NOT NULL AND v_existing_row.deleted_at_utc IS NULL THEN
                IF p_deleted_at_utc >= v_existing_row.updated_at_utc THEN
                    v_final_deleted_at := p_deleted_at_utc;
                ELSE
                    v_final_deleted_at := NULL;
                END IF;
            ELSIF v_existing_row.deleted_at_utc IS NOT NULL AND p_deleted_at_utc IS NULL THEN
                IF p_updated_at_utc > v_existing_row.deleted_at_utc THEN
                    v_final_deleted_at := NULL;
                ELSE
                    v_final_deleted_at := v_existing_row.deleted_at_utc;
                END IF;
            ELSIF p_deleted_at_utc IS NOT NULL AND v_existing_row.deleted_at_utc IS NOT NULL THEN
                v_final_deleted_at := GREATEST(p_deleted_at_utc, v_existing_row.deleted_at_utc);
            ELSE
                v_final_deleted_at := NULL;
            END IF;

            v_latest_updated_at := GREATEST(COALESCE(p_updated_at_utc, v_now), v_existing_row.updated_at_utc);

            UPDATE public.budgets SET
                amount_minor = v_target_amount_minor,
                month_year = v_month_year,
                deleted_at_utc = v_final_deleted_at,
                updated_at_utc = v_latest_updated_at,
                field_timestamps_json = v_merged_ts,
                sync_status = 'synced'
            WHERE id = p_entity_id AND user_id = v_user_id;
        END IF;

        SELECT row_to_json(b)::jsonb INTO v_merged_record 
        FROM public.budgets b 
        WHERE b.id = p_entity_id AND b.user_id = v_user_id;

    ELSIF p_entity_type IN ('category_budget', 'category_budgets', 'categorybudget', 'categorybudgets') THEN
        SELECT * INTO v_existing_row 
        FROM public.category_budgets 
        WHERE id = p_entity_id AND user_id = v_user_id 
        FOR UPDATE;

        IF NOT FOUND THEN
            INSERT INTO public.category_budgets (
                id, user_id, budget_id, category_id, amount_minor,
                created_at_utc, updated_at_utc, deleted_at_utc,
                sync_status, field_timestamps_json
            ) VALUES (
                p_entity_id,
                v_user_id,
                COALESCE((p_payload->>'budgetId')::uuid, (p_payload->>'budget_id')::uuid),
                COALESCE((p_payload->>'categoryId')::uuid, (p_payload->>'category_id')::uuid),
                COALESCE((p_payload->>'amountMinor')::bigint, (p_payload->>'amount_minor')::bigint, 0),
                COALESCE((p_payload->>'createdAtUtc')::timestamptz, (p_payload->>'created_at_utc')::timestamptz, v_now),
                COALESCE(p_updated_at_utc, v_now),
                p_deleted_at_utc,
                'synced',
                v_clamped_incoming_ts
            );
        ELSE
            v_merged_ts := COALESCE(v_existing_row.field_timestamps_json, '{}'::jsonb);

            -- amountMinor
            IF public.deterministic_field_winner(
                COALESCE(p_payload->'amountMinor', p_payload->'amount_minor', 'null'::jsonb),
                (v_clamped_incoming_ts->>'amountMinor')::timestamptz,
                to_jsonb(v_existing_row.amount_minor),
                (v_merged_ts->>'amountMinor')::timestamptz
            ) THEN
                v_target_amount_minor := COALESCE((p_payload->>'amountMinor')::bigint, (p_payload->>'amount_minor')::bigint, v_existing_row.amount_minor);
                v_merged_ts := jsonb_set(v_merged_ts, '{amountMinor}', to_jsonb(v_clamped_incoming_ts->>'amountMinor'));
            ELSE
                v_target_amount_minor := v_existing_row.amount_minor;
            END IF;

            -- Tombstone evaluation
            IF p_deleted_at_utc IS NOT NULL AND v_existing_row.deleted_at_utc IS NULL THEN
                IF p_deleted_at_utc >= v_existing_row.updated_at_utc THEN
                    v_final_deleted_at := p_deleted_at_utc;
                ELSE
                    v_final_deleted_at := NULL;
                END IF;
            ELSIF v_existing_row.deleted_at_utc IS NOT NULL AND p_deleted_at_utc IS NULL THEN
                IF p_updated_at_utc > v_existing_row.deleted_at_utc THEN
                    v_final_deleted_at := NULL;
                ELSE
                    v_final_deleted_at := v_existing_row.deleted_at_utc;
                END IF;
            ELSIF p_deleted_at_utc IS NOT NULL AND v_existing_row.deleted_at_utc IS NOT NULL THEN
                v_final_deleted_at := GREATEST(p_deleted_at_utc, v_existing_row.deleted_at_utc);
            ELSE
                v_final_deleted_at := NULL;
            END IF;

            v_latest_updated_at := GREATEST(COALESCE(p_updated_at_utc, v_now), v_existing_row.updated_at_utc);

            UPDATE public.category_budgets SET
                amount_minor = v_target_amount_minor,
                deleted_at_utc = v_final_deleted_at,
                updated_at_utc = v_latest_updated_at,
                field_timestamps_json = v_merged_ts,
                sync_status = 'synced'
            WHERE id = p_entity_id AND user_id = v_user_id;
        END IF;

        SELECT row_to_json(cb)::jsonb INTO v_merged_record 
        FROM public.category_budgets cb 
        WHERE cb.id = p_entity_id AND cb.user_id = v_user_id;

    ELSIF p_entity_type IN ('savings_goal', 'savings_goals', 'goal', 'goals', 'savingsgoal', 'savingsgoals') THEN
        SELECT * INTO v_existing_row 
        FROM public.savings_goals 
        WHERE id = p_entity_id AND user_id = v_user_id 
        FOR UPDATE;

        IF NOT FOUND THEN
            INSERT INTO public.savings_goals (
                id, user_id, name, target_amount_minor, current_amount_minor,
                target_date_utc, icon_code_point, color_value, created_at_utc,
                updated_at_utc, deleted_at_utc, sync_status, field_timestamps_json
            ) VALUES (
                p_entity_id,
                v_user_id,
                COALESCE(p_payload->>'name', 'Goal'),
                COALESCE((p_payload->>'targetAmountMinor')::bigint, (p_payload->>'target_amount_minor')::bigint, 10000),
                COALESCE((p_payload->>'currentAmountMinor')::bigint, (p_payload->>'current_amount_minor')::bigint, 0),
                COALESCE((p_payload->>'targetDateUtc')::timestamptz, (p_payload->>'target_date_utc')::timestamptz, v_now + interval '30 days'),
                COALESCE((p_payload->>'iconCodePoint')::integer, (p_payload->>'icon_code_point')::integer, 58988),
                COALESCE((p_payload->>'colorValue')::integer, (p_payload->>'color_value')::integer, 4279310721),
                COALESCE((p_payload->>'createdAtUtc')::timestamptz, (p_payload->>'created_at_utc')::timestamptz, v_now),
                COALESCE(p_updated_at_utc, v_now),
                p_deleted_at_utc,
                'synced',
                v_clamped_incoming_ts
            );
        ELSE
            v_merged_ts := COALESCE(v_existing_row.field_timestamps_json, '{}'::jsonb);

            -- name
            IF public.deterministic_field_winner(
                COALESCE(p_payload->'name', 'null'::jsonb),
                (v_clamped_incoming_ts->>'name')::timestamptz,
                to_jsonb(v_existing_row.name),
                (v_merged_ts->>'name')::timestamptz
            ) THEN
                v_name := COALESCE(p_payload->>'name', v_existing_row.name);
                v_merged_ts := jsonb_set(v_merged_ts, '{name}', to_jsonb(v_clamped_incoming_ts->>'name'));
            ELSE
                v_name := v_existing_row.name;
            END IF;

            -- currentAmountMinor
            IF public.deterministic_field_winner(
                COALESCE(p_payload->'currentAmountMinor', p_payload->'current_amount_minor', 'null'::jsonb),
                (v_clamped_incoming_ts->>'currentAmountMinor')::timestamptz,
                to_jsonb(v_existing_row.current_amount_minor),
                (v_merged_ts->>'currentAmountMinor')::timestamptz
            ) THEN
                v_current_amount_minor := COALESCE((p_payload->>'currentAmountMinor')::bigint, (p_payload->>'current_amount_minor')::bigint, v_existing_row.current_amount_minor);
                v_merged_ts := jsonb_set(v_merged_ts, '{currentAmountMinor}', to_jsonb(v_clamped_incoming_ts->>'currentAmountMinor'));
            ELSE
                v_current_amount_minor := v_existing_row.current_amount_minor;
            END IF;

            -- targetAmountMinor
            IF public.deterministic_field_winner(
                COALESCE(p_payload->'targetAmountMinor', p_payload->'target_amount_minor', 'null'::jsonb),
                (v_clamped_incoming_ts->>'targetAmountMinor')::timestamptz,
                to_jsonb(v_existing_row.target_amount_minor),
                (v_merged_ts->>'targetAmountMinor')::timestamptz
            ) THEN
                v_target_amount_minor := COALESCE((p_payload->>'targetAmountMinor')::bigint, (p_payload->>'target_amount_minor')::bigint, v_existing_row.target_amount_minor);
                v_merged_ts := jsonb_set(v_merged_ts, '{targetAmountMinor}', to_jsonb(v_clamped_incoming_ts->>'targetAmountMinor'));
            ELSE
                v_target_amount_minor := v_existing_row.target_amount_minor;
            END IF;

            -- Tombstone evaluation
            IF p_deleted_at_utc IS NOT NULL AND v_existing_row.deleted_at_utc IS NULL THEN
                IF p_deleted_at_utc >= v_existing_row.updated_at_utc THEN
                    v_final_deleted_at := p_deleted_at_utc;
                ELSE
                    v_final_deleted_at := NULL;
                END IF;
            ELSIF v_existing_row.deleted_at_utc IS NOT NULL AND p_deleted_at_utc IS NULL THEN
                IF p_updated_at_utc > v_existing_row.deleted_at_utc THEN
                    v_final_deleted_at := NULL;
                ELSE
                    v_final_deleted_at := v_existing_row.deleted_at_utc;
                END IF;
            ELSIF p_deleted_at_utc IS NOT NULL AND v_existing_row.deleted_at_utc IS NOT NULL THEN
                v_final_deleted_at := GREATEST(p_deleted_at_utc, v_existing_row.deleted_at_utc);
            ELSE
                v_final_deleted_at := NULL;
            END IF;

            v_latest_updated_at := GREATEST(COALESCE(p_updated_at_utc, v_now), v_existing_row.updated_at_utc);

            UPDATE public.savings_goals SET
                name = v_name,
                current_amount_minor = v_current_amount_minor,
                target_amount_minor = v_target_amount_minor,
                deleted_at_utc = v_final_deleted_at,
                updated_at_utc = v_latest_updated_at,
                field_timestamps_json = v_merged_ts,
                sync_status = 'synced'
            WHERE id = p_entity_id AND user_id = v_user_id;
        END IF;

        SELECT row_to_json(sg)::jsonb INTO v_merged_record 
        FROM public.savings_goals sg 
        WHERE sg.id = p_entity_id AND sg.user_id = v_user_id;

    ELSIF p_entity_type IN ('recurring_transaction', 'recurring_transactions', 'recurring_rule', 'recurring_rules', 'recurringrule', 'recurringtransaction') THEN
        SELECT * INTO v_existing_row 
        FROM public.recurring_transactions 
        WHERE id = p_entity_id AND user_id = v_user_id 
        FOR UPDATE;

        IF NOT FOUND THEN
            INSERT INTO public.recurring_transactions (
                id, user_id, amount_minor, transaction_type, category_id,
                account_id, note, frequency, start_date_utc, next_occurrence_utc,
                last_executed_date_utc, is_active, created_at_utc, updated_at_utc,
                deleted_at_utc, sync_status, field_timestamps_json
            ) VALUES (
                p_entity_id,
                v_user_id,
                COALESCE((p_payload->>'amountMinor')::bigint, (p_payload->>'amount_minor')::bigint, 0),
                COALESCE(p_payload->>'transactionType', p_payload->>'transaction_type', 'expense'),
                COALESCE((p_payload->>'categoryId')::uuid, (p_payload->>'category_id')::uuid),
                COALESCE((p_payload->>'accountId')::uuid, (p_payload->>'account_id')::uuid),
                COALESCE(p_payload->>'note', ''),
                COALESCE(p_payload->>'frequency', 'monthly'),
                COALESCE((p_payload->>'startDateUtc')::timestamptz, (p_payload->>'start_date_utc')::timestamptz, v_now),
                COALESCE((p_payload->>'nextOccurrenceUtc')::timestamptz, (p_payload->>'next_occurrence_utc')::timestamptz, v_now),
                (p_payload->>'lastExecutedDateUtc')::timestamptz,
                COALESCE((p_payload->>'isActive')::boolean, (p_payload->>'is_active')::boolean, true),
                COALESCE((p_payload->>'createdAtUtc')::timestamptz, (p_payload->>'created_at_utc')::timestamptz, v_now),
                COALESCE(p_updated_at_utc, v_now),
                p_deleted_at_utc,
                'synced',
                v_clamped_incoming_ts
            );
        ELSE
            v_merged_ts := COALESCE(v_existing_row.field_timestamps_json, '{}'::jsonb);

            -- amountMinor
            IF public.deterministic_field_winner(
                COALESCE(p_payload->'amountMinor', p_payload->'amount_minor', 'null'::jsonb),
                (v_clamped_incoming_ts->>'amountMinor')::timestamptz,
                to_jsonb(v_existing_row.amount_minor),
                (v_merged_ts->>'amountMinor')::timestamptz
            ) THEN
                v_amount_minor := COALESCE((p_payload->>'amountMinor')::bigint, (p_payload->>'amount_minor')::bigint, v_existing_row.amount_minor);
                v_merged_ts := jsonb_set(v_merged_ts, '{amountMinor}', to_jsonb(v_clamped_incoming_ts->>'amountMinor'));
            ELSE
                v_amount_minor := v_existing_row.amount_minor;
            END IF;

            -- isActive
            IF public.deterministic_field_winner(
                COALESCE(p_payload->'isActive', p_payload->'is_active', 'null'::jsonb),
                (v_clamped_incoming_ts->>'isActive')::timestamptz,
                to_jsonb(v_existing_row.is_active),
                (v_merged_ts->>'isActive')::timestamptz
            ) THEN
                v_is_active := COALESCE((p_payload->>'isActive')::boolean, (p_payload->>'is_active')::boolean, v_existing_row.is_active);
                v_merged_ts := jsonb_set(v_merged_ts, '{isActive}', to_jsonb(v_clamped_incoming_ts->>'isActive'));
            ELSE
                v_is_active := v_existing_row.is_active;
            END IF;

            -- Tombstone evaluation
            IF p_deleted_at_utc IS NOT NULL AND v_existing_row.deleted_at_utc IS NULL THEN
                IF p_deleted_at_utc >= v_existing_row.updated_at_utc THEN
                    v_final_deleted_at := p_deleted_at_utc;
                ELSE
                    v_final_deleted_at := NULL;
                END IF;
            ELSIF v_existing_row.deleted_at_utc IS NOT NULL AND p_deleted_at_utc IS NULL THEN
                IF p_updated_at_utc > v_existing_row.deleted_at_utc THEN
                    v_final_deleted_at := NULL;
                ELSE
                    v_final_deleted_at := v_existing_row.deleted_at_utc;
                END IF;
            ELSIF p_deleted_at_utc IS NOT NULL AND v_existing_row.deleted_at_utc IS NOT NULL THEN
                v_final_deleted_at := GREATEST(p_deleted_at_utc, v_existing_row.deleted_at_utc);
            ELSE
                v_final_deleted_at := NULL;
            END IF;

            v_latest_updated_at := GREATEST(COALESCE(p_updated_at_utc, v_now), v_existing_row.updated_at_utc);

            UPDATE public.recurring_transactions SET
                amount_minor = v_amount_minor,
                is_active = v_is_active,
                deleted_at_utc = v_final_deleted_at,
                updated_at_utc = v_latest_updated_at,
                field_timestamps_json = v_merged_ts,
                sync_status = 'synced'
            WHERE id = p_entity_id AND user_id = v_user_id;
        END IF;

        SELECT row_to_json(rt)::jsonb INTO v_merged_record 
        FROM public.recurring_transactions rt 
        WHERE rt.id = p_entity_id AND rt.user_id = v_user_id;

    ELSIF p_entity_type IN ('user_setting', 'user_settings', 'settings', 'setting', 'usersetting', 'usersettings') THEN
        v_key := COALESCE(p_payload->>'key', p_payload->>'id', p_entity_id::text);
        v_val := COALESCE(p_payload->>'value', '');

        INSERT INTO public.user_settings (key, user_id, value, updated_at_utc)
        VALUES (v_key, v_user_id, v_val, COALESCE(p_updated_at_utc, v_now))
        ON CONFLICT (key, user_id) DO UPDATE SET
            value = EXCLUDED.value,
            updated_at_utc = EXCLUDED.updated_at_utc
        WHERE EXCLUDED.updated_at_utc > public.user_settings.updated_at_utc
           OR (EXCLUDED.updated_at_utc = public.user_settings.updated_at_utc
               AND (public.canonical_json(to_jsonb(EXCLUDED.value)) COLLATE "C") > (public.canonical_json(to_jsonb(public.user_settings.value)) COLLATE "C"));

        SELECT row_to_json(us)::jsonb INTO v_merged_record 
        FROM public.user_settings us 
        WHERE us.key = v_key AND us.user_id = v_user_id;
    END IF;

    -- 6. Atomically Insert into sync_audit_log (Guaranteed Idempotency Record)
    INSERT INTO public.sync_audit_log (
        user_id, entity_type, entity_id, operation_type, idempotency_token, processed_at_utc
    ) VALUES (
        v_user_id, p_entity_type, p_entity_id, p_operation_type, p_operation_id, v_now
    )
    ON CONFLICT (user_id, idempotency_token) DO NOTHING;

    RETURN jsonb_build_object(
        'status', 'applied',
        'operation_id', p_operation_id,
        'entity_id', p_entity_id,
        'merged_record', v_merged_record
    );
END;
$$;
