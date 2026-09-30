-- ==============================================================================
-- SKYLINE (aquagrief.space) - COMPREHENSIVE SECURITY HARDENING SCRIPT (fix_all.sql)
-- Run this script in Supabase Dashboard -> SQL Editor
-- ==============================================================================

-- 0. Required Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ==============================================================================
-- 1. Table: public.admins (Server-Enforced Administrator Registry)
-- ==============================================================================
CREATE TABLE IF NOT EXISTS public.admins (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.admins ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "admins_select_self" ON public.admins;
CREATE POLICY "admins_select_self" ON public.admins
    FOR SELECT
    TO authenticated
    USING (auth.uid() = user_id);

-- Seed master admins into public.admins based on verified emails
INSERT INTO public.admins (user_id)
SELECT id FROM auth.users
WHERE LOWER(email) IN ('gorwok.h@yandex.ru', 'fakeface52@mail.ru')
ON CONFLICT (user_id) DO NOTHING;

-- Also seed any profile currently marked with is_admin = true
INSERT INTO public.admins (user_id)
SELECT id FROM public.profiles
WHERE is_admin = TRUE
ON CONFLICT (user_id) DO NOTHING;

-- Helper Function: public.is_admin()
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.admins WHERE user_id = auth.uid()
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated, anon;


-- ==============================================================================
-- 2. Table: public.site_config (Global Public-Read Settings, Mutation via Server)
-- ==============================================================================
CREATE TABLE IF NOT EXISTS public.site_config (
    key TEXT PRIMARY KEY,
    value JSONB NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.site_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "site_config_read_all" ON public.site_config;
CREATE POLICY "site_config_read_all" ON public.site_config
    FOR SELECT
    TO anon, authenticated
    USING (true);

DROP POLICY IF EXISTS "site_config_admin_write" ON public.site_config;
CREATE POLICY "site_config_admin_write" ON public.site_config
    FOR ALL
    TO authenticated
    USING (public.is_admin())
    WITH CHECK (public.is_admin());


-- ==============================================================================
-- 3. Migration: Transfer SITE_SETTINGS to site_config & Purge Old Key
-- ==============================================================================
DO $$
DECLARE
    v_raw TEXT;
BEGIN
    SELECT used_by INTO v_raw FROM public.license_keys WHERE code = 'SITE_SETTINGS' LIMIT 1;
    IF v_raw IS NOT NULL AND v_raw <> '' THEN
        BEGIN
            INSERT INTO public.site_config (key, value, updated_at)
            VALUES ('main', v_raw::jsonb, NOW())
            ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW();
        EXCEPTION WHEN OTHERS THEN
            INSERT INTO public.site_config (key, value, updated_at)
            VALUES ('main', '{}'::jsonb, NOW())
            ON CONFLICT (key) DO NOTHING;
        END;
    ELSE
        INSERT INTO public.site_config (key, value, updated_at)
        VALUES ('main', '{}'::jsonb, NOW())
        ON CONFLICT (key) DO NOTHING;
    END IF;

    -- Delete dangerous SITE_SETTINGS row from license_keys
    DELETE FROM public.license_keys WHERE code = 'SITE_SETTINGS';
END;
$$;


-- ==============================================================================
-- 4. RLS & Column Protection on public.profiles
-- ==============================================================================
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Drop ALL existing/legacy policies on profiles to prevent permission leaks
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (SELECT policyname FROM pg_policies WHERE tablename = 'profiles' AND schemaname = 'public') LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.profiles;', r.policyname);
    END LOOP;
END;
$$;

CREATE POLICY "profiles_select_self" ON public.profiles
    FOR SELECT
    TO authenticated
    USING (auth.uid() = id);

CREATE POLICY "profiles_insert_self" ON public.profiles
    FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = id);

CREATE POLICY "profiles_update_self" ON public.profiles
    FOR UPDATE
    TO authenticated
    USING (auth.uid() = id)
    WITH CHECK (auth.uid() = id);

-- Prevent authenticated clients from modifying privileged columns
CREATE OR REPLACE FUNCTION public.protect_profile_privileged_fields()
RETURNS TRIGGER AS $$
BEGIN
    -- Check if any privileged field was modified
    IF (NEW.is_admin IS DISTINCT FROM OLD.is_admin) OR
       (NEW.subscription_active IS DISTINCT FROM OLD.subscription_active) OR
       (NEW.subscription_until IS DISTINCT FROM OLD.subscription_until) OR
       (NEW.hwid IS DISTINCT FROM OLD.hwid) OR
       (NEW.uid IS DISTINCT FROM OLD.uid) THEN

        -- Allow ONLY if explicitly authorized by internal RPC or service_role
        IF current_setting('app.allow_profile_admin_update', true) = 'true' THEN
            RETURN NEW;
        END IF;

        IF auth.role() = 'service_role' THEN
            RETURN NEW;
        END IF;

        -- Any client attempt to update these fields is strictly blocked!
        RAISE EXCEPTION 'Access denied: cannot modify privileged profile columns' USING errcode = '42501';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_protect_profile_fields ON public.profiles;
CREATE TRIGGER trg_protect_profile_fields
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION public.protect_profile_privileged_fields();


-- ==============================================================================
-- 5. RLS on public.license_keys
-- ==============================================================================
ALTER TABLE public.license_keys ENABLE ROW LEVEL SECURITY;

-- Drop ALL existing/legacy policies on license_keys to prevent permission leaks
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (SELECT policyname FROM pg_policies WHERE tablename = 'license_keys' AND schemaname = 'public') LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.license_keys;', r.policyname);
    END LOOP;
END;
$$;

CREATE POLICY "license_keys_select_unused" ON public.license_keys
    FOR SELECT
    TO authenticated, anon
    USING (is_used = FALSE);

-- Note: No INSERT, UPDATE, or DELETE policies exist for license_keys.
-- Clients cannot mutate license_keys directly; only service_role and RPC functions can.


-- ==============================================================================
-- 6. RPC Functions (All SECURITY DEFINER with strict validation)
-- ==============================================================================

-- 6.1 admin_ban_user(p_uid uuid)
CREATE OR REPLACE FUNCTION public.admin_ban_user(p_uid UUID)
RETURNS VOID AS $$
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access denied' USING errcode = '42501';
    END IF;

    -- Master Admin protection
    IF EXISTS (
        SELECT 1 FROM auth.users u
        WHERE u.id = p_uid AND LOWER(u.email) IN ('gorwok.h@yandex.ru', 'fakeface52@mail.ru')
    ) THEN
        RAISE EXCEPTION 'Cannot ban master admin' USING errcode = '42501';
    END IF;

    PERFORM set_config('app.allow_profile_admin_update', 'true', true);

    UPDATE public.profiles
    SET subscription_active = FALSE,
        subscription_until = 'BANNED',
        hwid = 'BANNED'
    WHERE id = p_uid;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 6.2 admin_unban_user(p_uid uuid)
CREATE OR REPLACE FUNCTION public.admin_unban_user(p_uid UUID)
RETURNS VOID AS $$
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access denied' USING errcode = '42501';
    END IF;

    PERFORM set_config('app.allow_profile_admin_update', 'true', true);

    UPDATE public.profiles
    SET subscription_active = FALSE,
        subscription_until = 'Не активна',
        hwid = NULL
    WHERE id = p_uid;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 6.3 admin_grant_subscription(p_uid uuid, p_days int)
CREATE OR REPLACE FUNCTION public.admin_grant_subscription(p_uid UUID, p_days INT)
RETURNS TEXT AS $$
DECLARE
    v_until TEXT;
    v_exp DATE;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access denied' USING errcode = '42501';
    END IF;

    IF p_days <= 0 OR p_days >= 9000 THEN
        v_until := 'Навсегда (Lifetime)';
    ELSE
        v_exp := (NOW() + (p_days || ' days')::INTERVAL)::DATE;
        v_until := 'до ' || to_char(v_exp, 'DD.MM.YYYY');
    END IF;

    PERFORM set_config('app.allow_profile_admin_update', 'true', true);

    UPDATE public.profiles
    SET subscription_active = TRUE,
        subscription_until = v_until
    WHERE id = p_uid;

    RETURN v_until;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 6.4 admin_revoke_subscription(p_uid uuid)
CREATE OR REPLACE FUNCTION public.admin_revoke_subscription(p_uid UUID)
RETURNS VOID AS $$
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access denied' USING errcode = '42501';
    END IF;

    -- Master Admin protection
    IF EXISTS (
        SELECT 1 FROM auth.users u
        WHERE u.id = p_uid AND LOWER(u.email) IN ('gorwok.h@yandex.ru', 'fakeface52@mail.ru')
    ) THEN
        RAISE EXCEPTION 'Cannot revoke subscription from master admin' USING errcode = '42501';
    END IF;

    PERFORM set_config('app.allow_profile_admin_update', 'true', true);

    UPDATE public.profiles
    SET subscription_active = FALSE,
        subscription_until = 'Не активна'
    WHERE id = p_uid;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 6.5 admin_reset_hwid(p_uid uuid)
CREATE OR REPLACE FUNCTION public.admin_reset_hwid(p_uid UUID)
RETURNS VOID AS $$
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access denied' USING errcode = '42501';
    END IF;

    PERFORM set_config('app.allow_profile_admin_update', 'true', true);

    UPDATE public.profiles
    SET hwid = NULL
    WHERE id = p_uid;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 6.6 admin_toggle_role(p_uid uuid, p_make_admin bool)
CREATE OR REPLACE FUNCTION public.admin_toggle_role(p_uid UUID, p_make_admin BOOLEAN)
RETURNS VOID AS $$
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access denied' USING errcode = '42501';
    END IF;

    -- Master Admin protection
    IF NOT p_make_admin AND EXISTS (
        SELECT 1 FROM auth.users u
        WHERE u.id = p_uid AND LOWER(u.email) IN ('gorwok.h@yandex.ru', 'fakeface52@mail.ru')
    ) THEN
        RAISE EXCEPTION 'Cannot revoke master admin role' USING errcode = '42501';
    END IF;

    PERFORM set_config('app.allow_profile_admin_update', 'true', true);

    IF p_make_admin THEN
        INSERT INTO public.admins (user_id) VALUES (p_uid) ON CONFLICT (user_id) DO NOTHING;
        UPDATE public.profiles SET is_admin = TRUE WHERE id = p_uid;
    ELSE
        DELETE FROM public.admins WHERE user_id = p_uid;
        UPDATE public.profiles SET is_admin = FALSE WHERE id = p_uid;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 6.7 admin_toggle_maintenance()
CREATE OR REPLACE FUNCTION public.admin_toggle_maintenance()
RETURNS BOOLEAN AS $$
DECLARE
    v_curr BOOLEAN := FALSE;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access denied' USING errcode = '42501';
    END IF;

    SELECT COALESCE((value->>'maintenance')::BOOLEAN, FALSE) INTO v_curr
    FROM public.site_config WHERE key = 'main';

    v_curr := NOT v_curr;

    INSERT INTO public.site_config (key, value, updated_at)
    VALUES ('main', jsonb_build_object('maintenance', v_curr), NOW())
    ON CONFLICT (key) DO UPDATE
    SET value = public.site_config.value || jsonb_build_object('maintenance', v_curr),
        updated_at = NOW();

    RETURN v_curr;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 6.8 admin_load_users()
DROP FUNCTION IF EXISTS public.admin_load_users();
CREATE OR REPLACE FUNCTION public.admin_load_users()
RETURNS TABLE (
    id UUID,
    email TEXT,
    mc_nickname TEXT,
    hwid TEXT,
    subscription_active BOOLEAN,
    subscription_until TEXT,
    is_admin BOOLEAN,
    uid BIGINT,
    created_at TIMESTAMPTZ
) AS $$
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access denied' USING errcode = '42501';
    END IF;

    RETURN QUERY
    SELECT
        p.id::UUID,
        COALESCE(p.email::TEXT, u.email::TEXT, '')::TEXT AS email,
        COALESCE(p.mc_nickname::TEXT, '')::TEXT AS mc_nickname,
        p.hwid::TEXT,
        COALESCE(p.subscription_active, FALSE)::BOOLEAN AS subscription_active,
        COALESCE(p.subscription_until, 'Не активна')::TEXT AS subscription_until,
        (EXISTS (SELECT 1 FROM public.admins a WHERE a.user_id = p.id) OR COALESCE(p.is_admin, FALSE))::BOOLEAN AS is_admin,
        p.uid::BIGINT AS uid,
        p.created_at::TIMESTAMPTZ AS created_at
    FROM public.profiles p
    LEFT JOIN auth.users u ON u.id = p.id
    ORDER BY p.created_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 6.9 admin_create_key(p_days int)
CREATE OR REPLACE FUNCTION public.admin_create_key(p_days INT)
RETURNS TEXT AS $$
DECLARE
    v_code TEXT;
    v_prefix TEXT;
    v_rand TEXT;
    v_hex TEXT;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access denied' USING errcode = '42501';
    END IF;

    IF p_days = 0 THEN
        v_prefix := 'SKYLINE-RESET';
    ELSIF p_days < 0 OR p_days >= 9000 THEN
        v_prefix := 'SKYLINE-LIFE';
    ELSE
        v_prefix := 'SKYLINE-' || p_days || 'D';
    END IF;

    -- Cryptographically secure random 12 hex characters in format XXXX-XXXX-XXXX
    -- Native PostgreSQL without requiring external extensions (works in every Postgres/Supabase instance)
    v_hex := UPPER(SUBSTR(MD5(RANDOM()::TEXT || CLOCK_TIMESTAMP()::TEXT || GEN_RANDOM_UUID()::TEXT), 1, 12));
    v_rand := SUBSTR(v_hex, 1, 4) || '-' ||
              SUBSTR(v_hex, 5, 4) || '-' ||
              SUBSTR(v_hex, 9, 4);

    v_code := v_prefix || '-' || v_rand;

    INSERT INTO public.license_keys (code, duration_days, is_used, created_at)
    VALUES (v_code, p_days, FALSE, NOW());

    RETURN v_code;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions;

-- 6.10 redeem_license_key(p_code text)
CREATE OR REPLACE FUNCTION public.redeem_license_key(p_code TEXT)
RETURNS JSONB AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_key RECORD;
    v_sub_text TEXT;
    v_exp DATE;
    v_user_ident TEXT;
BEGIN
    IF v_uid IS NULL THEN
        RETURN jsonb_build_object('ok', FALSE, 'error', 'unauthorized');
    END IF;

    p_code := TRIM(UPPER(p_code));

    -- Lock key row for atomic update
    SELECT * INTO v_key
    FROM public.license_keys
    WHERE UPPER(code) = p_code
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', FALSE, 'error', 'key_not_found');
    END IF;

    IF v_key.is_used THEN
        RETURN jsonb_build_object('ok', FALSE, 'error', 'key_already_used');
    END IF;

    -- Handle HWID reset key
    IF v_key.duration_days = 0 OR p_code LIKE '%-RESET-%' THEN
        UPDATE public.license_keys
        SET is_used = TRUE,
            used_by = v_uid::TEXT
        WHERE id = v_key.id;

        PERFORM set_config('app.allow_profile_admin_update', 'true', true);

        UPDATE public.profiles
        SET hwid = NULL
        WHERE id = v_uid;

        RETURN jsonb_build_object('ok', TRUE, 'type', 'reset', 'message', 'hwid_reset_success');
    END IF;

    -- Calculate subscription duration
    IF v_key.duration_days >= 9000 OR v_key.duration_days < 0 THEN
        v_sub_text := 'Навсегда (Lifetime)';
    ELSE
        v_exp := (NOW() + (v_key.duration_days || ' days')::INTERVAL)::DATE;
        v_sub_text := 'до ' || to_char(v_exp, 'DD.MM.YYYY');
    END IF;

    -- Get user nickname or email for audit trail
    SELECT COALESCE(mc_nickname, email, v_uid::TEXT) INTO v_user_ident
    FROM public.profiles WHERE id = v_uid;

    -- Mark key as used
    UPDATE public.license_keys
    SET is_used = TRUE,
        used_by = COALESCE(v_user_ident, v_uid::TEXT)
    WHERE id = v_key.id;

    -- Update subscription atomically
    PERFORM set_config('app.allow_profile_admin_update', 'true', true);

    UPDATE public.profiles
    SET subscription_active = TRUE,
        subscription_until = v_sub_text
    WHERE id = v_uid;

    RETURN jsonb_build_object('ok', TRUE, 'type', 'subscription', 'until', v_sub_text);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 6.11 reset_hwid_with_key(p_code text)
CREATE OR REPLACE FUNCTION public.reset_hwid_with_key(p_code TEXT)
RETURNS JSONB AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_key RECORD;
BEGIN
    IF v_uid IS NULL THEN
        RETURN jsonb_build_object('ok', FALSE, 'error', 'unauthorized');
    END IF;

    p_code := TRIM(UPPER(p_code));

    SELECT * INTO v_key
    FROM public.license_keys
    WHERE UPPER(code) = p_code
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', FALSE, 'error', 'key_not_found');
    END IF;

    IF v_key.is_used THEN
        RETURN jsonb_build_object('ok', FALSE, 'error', 'key_already_used');
    END IF;

    UPDATE public.license_keys
    SET is_used = TRUE,
        used_by = v_uid::TEXT
    WHERE id = v_key.id;

    PERFORM set_config('app.allow_profile_admin_update', 'true', true);

    UPDATE public.profiles
    SET hwid = NULL
    WHERE id = v_uid;

    RETURN jsonb_build_object('ok', TRUE);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 6.12 check_license_key(p_code text)
CREATE OR REPLACE FUNCTION public.check_license_key(p_code TEXT)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.license_keys
        WHERE UPPER(code) = TRIM(UPPER(p_code)) AND is_used = FALSE
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.admin_ban_user(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_unban_user(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_grant_subscription(UUID, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_revoke_subscription(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_reset_hwid(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_toggle_role(UUID, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_toggle_maintenance() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_load_users() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_create_key(INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.redeem_license_key(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reset_hwid_with_key(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.check_license_key(TEXT) TO authenticated, anon;


-- ==============================================================================
-- 7. Trigger on auth.users: Automatic Server-Side Profile Creation
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
    v_max_uid INT;
    v_nick TEXT;
BEGIN
    SELECT COALESCE(MAX(uid), 0) + 1 INTO v_max_uid FROM public.profiles;
    v_nick := COALESCE(NEW.raw_user_meta_data->>'mc_nickname', SPLIT_PART(NEW.email, '@', 1));

    INSERT INTO public.profiles (
        id,
        email,
        mc_nickname,
        hwid,
        subscription_active,
        subscription_until,
        is_admin,
        uid,
        created_at
    )
    VALUES (
        NEW.id,
        NEW.email,
        v_nick,
        NULL,
        FALSE,
        'Не активна',
        FALSE,
        v_max_uid,
        NOW()
    )
    ON CONFLICT (id) DO UPDATE SET
        email = EXCLUDED.email,
        mc_nickname = COALESCE(public.profiles.mc_nickname, EXCLUDED.mc_nickname);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- ==============================================================================
-- 8. pg_cron Job: Purge Unconfirmed Accounts Older Than 24h
-- ==============================================================================
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        BEGIN
            PERFORM cron.unschedule('cleanup_unconfirmed_users');
        EXCEPTION WHEN OTHERS THEN
            NULL;
        END;

        PERFORM cron.schedule(
            'cleanup_unconfirmed_users',
            '0 3 * * *',
            $cron$DELETE FROM auth.users WHERE email_confirmed_at IS NULL AND created_at < NOW() - INTERVAL '24 hours'$cron$
        );
    END IF;
EXCEPTION WHEN OTHERS THEN
    -- In case pg_cron is disabled on standard free tier
    NULL;
END;
$$;
