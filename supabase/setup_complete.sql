-- =====================================================================
-- RoomPulse (STACK 2026 Semifinal Prototype)
-- Complete Consolidated Setup Script: Extensions, Schema, RPCs, Rules & Seed Data
-- Run this in your Supabase SQL Editor (Dashboard > SQL Editor > New Query)
-- =====================================================================

-- 1. EXTENSIONS
CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 2. TABLES
-- Devices Table
CREATE TABLE IF NOT EXISTS public.devices (
    id text PRIMARY KEY,
    api_key_hash text NOT NULL,
    last_seen_at timestamptz NULL
);

-- Rooms Table
CREATE TABLE IF NOT EXISTS public.rooms (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL,
    capacity int NOT NULL CHECK (capacity > 0),
    device_id text UNIQUE REFERENCES public.devices(id) ON DELETE SET NULL
);

-- Sensor Readings Table
CREATE TABLE IF NOT EXISTS public.sensor_readings (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id text NOT NULL REFERENCES public.devices(id) ON DELETE CASCADE,
    recorded_at timestamptz NOT NULL DEFAULT now(),
    presence boolean NOT NULL,
    moving boolean NOT NULL,
    stationary boolean NOT NULL,
    moving_energy int NOT NULL,
    static_energy int NOT NULL,
    distance_cm int NOT NULL,
    source text NOT NULL CHECK (source IN ('device', 'simulator')),
    label text NULL
);

CREATE INDEX IF NOT EXISTS idx_sensor_readings_device_recorded 
ON public.sensor_readings(device_id, recorded_at DESC);

-- User Profiles Table
CREATE TABLE IF NOT EXISTS public.profiles (
    id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    display_name text NOT NULL,
    role text NOT NULL CHECK (role IN ('student', 'staff')) DEFAULT 'student',
    telegram_chat_id text NULL
);

-- Bookings Table
CREATE TABLE IF NOT EXISTS public.bookings (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    room_id uuid NOT NULL REFERENCES public.rooms(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    start_time timestamptz NOT NULL,
    end_time timestamptz NOT NULL,
    status text NOT NULL CHECK (
        status IN ('reserved', 'confirm_pending', 'active', 'completed', 'released', 'cancelled', 'expired')
    ) DEFAULT 'reserved',
    confirm_deadline timestamptz NULL,
    extension_count int NOT NULL DEFAULT 0,
    no_show_check_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT valid_booking_time_range CHECK (end_time > start_time)
);

-- Exclusion constraint preventing overlapping active bookings in the same room
ALTER TABLE public.bookings
DROP CONSTRAINT IF EXISTS no_overlapping_active_bookings;

ALTER TABLE public.bookings
ADD CONSTRAINT no_overlapping_active_bookings
EXCLUDE USING gist (
    room_id WITH =,
    tstzrange(start_time, end_time, '[)') WITH &&
)
WHERE (status IN ('reserved', 'confirm_pending', 'active'));

CREATE INDEX IF NOT EXISTS idx_bookings_user_status ON public.bookings(user_id, status);
CREATE INDEX IF NOT EXISTS idx_bookings_room_status ON public.bookings(room_id, status);

-- Events Audit Log Table
CREATE TABLE IF NOT EXISTS public.events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    at timestamptz NOT NULL DEFAULT now(),
    booking_id uuid REFERENCES public.bookings(id) ON DELETE SET NULL,
    room_id uuid NOT NULL REFERENCES public.rooms(id) ON DELETE CASCADE,
    kind text NOT NULL,
    reason text NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_events_at ON public.events(at DESC);

-- Notifications Table
CREATE TABLE IF NOT EXISTS public.notifications (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    booking_id uuid REFERENCES public.bookings(id) ON DELETE SET NULL,
    kind text NOT NULL,
    message text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    read_at timestamptz NULL
);

CREATE INDEX IF NOT EXISTS idx_notifications_user_unread ON public.notifications(user_id, read_at) WHERE read_at IS NULL;

-- Settings Table (Single-row configuration)
CREATE TABLE IF NOT EXISTS public.settings (
    id int PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    no_show_seconds int NOT NULL DEFAULT 600,
    confirm_window_seconds int NOT NULL DEFAULT 300,
    offline_threshold_seconds int NOT NULL DEFAULT 120,
    max_extensions int NOT NULL DEFAULT 1,
    presence_window_seconds int NOT NULL DEFAULT 60,
    demo_mode boolean NOT NULL DEFAULT false
);

-- 3. RLS AND SECURITY
CREATE OR REPLACE FUNCTION public.is_staff()
RETURNS boolean AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND role = 'staff'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

ALTER TABLE public.rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sensor_readings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bookings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.settings ENABLE ROW LEVEL SECURITY;

-- Clean existing policies before creating
DO $$
BEGIN
    DROP POLICY IF EXISTS "Anyone can view rooms" ON public.rooms;
    DROP POLICY IF EXISTS "Staff can modify rooms" ON public.rooms;
    DROP POLICY IF EXISTS "Staff can view devices" ON public.devices;
    DROP POLICY IF EXISTS "Staff can modify devices" ON public.devices;
    DROP POLICY IF EXISTS "Authenticated users can view sensor readings" ON public.sensor_readings;
    DROP POLICY IF EXISTS "Users can read own profile or staff can read all" ON public.profiles;
    DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
    DROP POLICY IF EXISTS "Users read own bookings or staff read all" ON public.bookings;
    DROP POLICY IF EXISTS "Staff can view audit events" ON public.events;
    DROP POLICY IF EXISTS "Users view own notifications" ON public.notifications;
    DROP POLICY IF EXISTS "Users update own notifications" ON public.notifications;
    DROP POLICY IF EXISTS "Authenticated users can view settings" ON public.settings;
    DROP POLICY IF EXISTS "Staff can update settings" ON public.settings;
END $$;

CREATE POLICY "Anyone can view rooms" ON public.rooms FOR SELECT TO authenticated, anon USING (true);
CREATE POLICY "Staff can modify rooms" ON public.rooms FOR ALL TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());
CREATE POLICY "Staff can view devices" ON public.devices FOR SELECT TO authenticated USING (public.is_staff());
CREATE POLICY "Staff can modify devices" ON public.devices FOR ALL TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());
CREATE POLICY "Authenticated users can view sensor readings" ON public.sensor_readings FOR SELECT TO authenticated USING (true);
CREATE POLICY "Users can read own profile or staff can read all" ON public.profiles FOR SELECT TO authenticated USING (id = auth.uid() OR public.is_staff());
CREATE POLICY "Users can update own profile" ON public.profiles FOR UPDATE TO authenticated USING (id = auth.uid()) WITH CHECK (id = auth.uid());
CREATE POLICY "Users read own bookings or staff read all" ON public.bookings FOR SELECT TO authenticated USING (user_id = auth.uid() OR public.is_staff());
CREATE POLICY "Staff can view audit events" ON public.events FOR SELECT TO authenticated USING (public.is_staff());
CREATE POLICY "Users view own notifications" ON public.notifications FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "Users update own notifications" ON public.notifications FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY "Authenticated users can view settings" ON public.settings FOR SELECT TO authenticated USING (true);
CREATE POLICY "Staff can update settings" ON public.settings FOR UPDATE TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());

-- 4. VIEWS
CREATE OR REPLACE VIEW public.rooms_with_status AS
WITH current_bookings AS (
    SELECT DISTINCT ON (room_id)
        b.id AS booking_id,
        b.room_id,
        b.user_id,
        b.status AS booking_status,
        b.start_time,
        b.end_time,
        b.confirm_deadline,
        b.extension_count,
        b.no_show_check_at
    FROM public.bookings b
    WHERE b.status IN ('reserved', 'confirm_pending', 'active')
      AND b.start_time <= now() + interval '10 minutes'
      AND b.end_time > now()
    ORDER BY b.room_id, b.start_time ASC
),
latest_readings AS (
    SELECT DISTINCT ON (device_id)
        r.device_id,
        r.recorded_at,
        r.presence,
        r.moving,
        r.stationary,
        r.moving_energy,
        r.static_energy,
        r.distance_cm,
        r.source,
        r.label
    FROM public.sensor_readings r
    ORDER BY r.device_id, r.recorded_at DESC
)
SELECT
    rm.id AS room_id,
    rm.name,
    rm.capacity,
    rm.device_id,
    cb.booking_id,
    cb.user_id AS current_booker_id,
    cb.booking_status,
    cb.start_time AS booking_start,
    cb.end_time AS booking_end,
    cb.confirm_deadline,
    lr.presence AS sensor_presence,
    lr.recorded_at AS sensor_recorded_at,
    lr.source AS sensor_source,
    lr.moving_energy,
    lr.static_energy,
    lr.distance_cm,
    dev.last_seen_at AS device_last_seen_at,
    CASE
        WHEN dev.id IS NULL OR dev.last_seen_at IS NULL THEN true
        WHEN EXTRACT(EPOCH FROM (now() - dev.last_seen_at)) > (SELECT offline_threshold_seconds FROM public.settings WHERE id = 1) THEN true
        ELSE false
    END AS is_sensor_offline,
    CASE
        WHEN cb.booking_status = 'active' THEN 'occupied'
        WHEN cb.booking_status = 'confirm_pending' THEN 'confirm_pending'
        WHEN cb.booking_status = 'reserved' THEN 'reserved'
        WHEN lr.presence = true THEN 'occupied'
        ELSE 'available'
    END AS display_status,
    CASE
        WHEN cb.end_time IS NOT NULL AND cb.end_time > now() THEN cb.end_time
        ELSE now()
    END AS next_free_slot
FROM public.rooms rm
LEFT JOIN public.devices dev ON rm.device_id = dev.id
LEFT JOIN current_bookings cb ON rm.id = cb.room_id
LEFT JOIN latest_readings lr ON rm.device_id = lr.device_id;

CREATE OR REPLACE VIEW public.admin_summary AS
WITH stats AS (
    SELECT
        count(*)::int AS total_bookings,
        count(*) FILTER (WHERE status = 'released')::int AS released_count,
        count(*) FILTER (WHERE status = 'completed')::int AS completed_count,
        count(*) FILTER (WHERE status = 'active')::int AS active_count,
        count(*) FILTER (WHERE status = 'cancelled')::int AS cancelled_count
    FROM public.bookings
)
SELECT
    s.total_bookings,
    s.released_count,
    s.completed_count,
    s.active_count,
    s.cancelled_count,
    CASE
        WHEN s.total_bookings > 0 THEN ROUND((s.released_count::numeric / s.total_bookings::numeric) * 100.0, 1)
        ELSE 0.0
    END AS no_show_rate_percent,
    (SELECT count(*)::int FROM public.rooms) AS total_rooms,
    (SELECT count(*)::int FROM public.events) AS total_audit_events
FROM stats s;

-- 5. RPCS
-- create_booking
CREATE OR REPLACE FUNCTION public.create_booking(
    p_room_id uuid,
    p_start_time timestamptz,
    p_duration_minutes int
)
RETURNS jsonb AS $$
DECLARE
    v_user_id uuid;
    v_end_time timestamptz;
    v_no_show_check_at timestamptz;
    v_no_show_seconds int;
    v_new_booking public.bookings%ROWTYPE;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;

    IF p_duration_minutes <= 0 OR p_duration_minutes > 120 THEN
        RAISE EXCEPTION 'Booking duration must be between 1 and 120 minutes';
    END IF;

    IF p_start_time < (now() - interval '5 minutes') THEN
        RAISE EXCEPTION 'Cannot book a room in the past';
    END IF;

    v_end_time := p_start_time + (p_duration_minutes || ' minutes')::interval;

    SELECT no_show_seconds INTO v_no_show_seconds FROM public.settings WHERE id = 1;
    IF v_no_show_seconds IS NULL THEN v_no_show_seconds := 600; END IF;
    v_no_show_check_at := p_start_time + (v_no_show_seconds || ' seconds')::interval;

    BEGIN
        INSERT INTO public.bookings (
            room_id, user_id, start_time, end_time, status, extension_count, no_show_check_at, created_at
        ) VALUES (
            p_room_id, v_user_id, p_start_time, v_end_time, 'reserved', 0, v_no_show_check_at, now()
        ) RETURNING * INTO v_new_booking;
    EXCEPTION
        WHEN exclusion_violation THEN
            RAISE EXCEPTION 'Selected room is already booked for this time window. Please choose another time or room.';
    END;

    INSERT INTO public.events (room_id, booking_id, kind, reason)
    VALUES (p_room_id, v_new_booking.id, 'booking_created', 'Booked for ' || p_duration_minutes || 'm by student (' || v_user_id || ')');

    RETURN to_jsonb(v_new_booking);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- respond_booking
CREATE OR REPLACE FUNCTION public.respond_booking(
    p_booking_id uuid,
    p_action text
)
RETURNS jsonb AS $$
DECLARE
    v_user_id uuid;
    v_booking public.bookings%ROWTYPE;
    v_settings public.settings%ROWTYPE;
    v_extra_minutes int := 0;
    v_updated_booking public.bookings%ROWTYPE;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;

    IF p_action NOT IN ('coming', 'late_10', 'late_20', 'cancel') THEN
        RAISE EXCEPTION 'Invalid action: must be coming, late_10, late_20, or cancel';
    END IF;

    SELECT * INTO v_booking FROM public.bookings WHERE id = p_booking_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Booking not found'; END IF;
    IF v_booking.user_id <> v_user_id THEN RAISE EXCEPTION 'Only the booking owner can respond' USING ERRCODE = '42501'; END IF;
    IF v_booking.status <> 'confirm_pending' THEN
        RAISE EXCEPTION 'Booking is not pending confirmation (current status: %)', v_booking.status;
    END IF;

    SELECT * INTO v_settings FROM public.settings WHERE id = 1;

    IF p_action = 'cancel' THEN
        UPDATE public.bookings SET status = 'cancelled' WHERE id = p_booking_id RETURNING * INTO v_updated_booking;
        INSERT INTO public.events (room_id, booking_id, kind, reason)
        VALUES (v_booking.room_id, p_booking_id, 'booking_cancelled_by_user', 'User cancelled booking in response to confirmation request');
        RETURN to_jsonb(v_updated_booking);
    END IF;

    IF v_booking.extension_count >= v_settings.max_extensions THEN
        RAISE EXCEPTION 'Maximum allowed extensions (%) already reached for this booking', v_settings.max_extensions;
    END IF;

    IF p_action = 'coming' THEN v_extra_minutes := 10;
    ELSIF p_action = 'late_10' THEN v_extra_minutes := 10;
    ELSIF p_action = 'late_20' THEN v_extra_minutes := 20;
    END IF;

    UPDATE public.bookings
    SET status = 'reserved',
        extension_count = extension_count + 1,
        no_show_check_at = GREATEST(now(), no_show_check_at) + (v_extra_minutes || ' minutes')::interval,
        confirm_deadline = NULL
    WHERE id = p_booking_id
    RETURNING * INTO v_updated_booking;

    INSERT INTO public.events (room_id, booking_id, kind, reason)
    VALUES (v_booking.room_id, p_booking_id, 'extension_granted', 'Booker responded "' || p_action || '". Extended no-show check by ' || v_extra_minutes || 'm');

    RETURN to_jsonb(v_updated_booking);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- cancel_booking
CREATE OR REPLACE FUNCTION public.cancel_booking(p_booking_id uuid)
RETURNS jsonb AS $$
DECLARE
    v_user_id uuid;
    v_is_staff boolean;
    v_booking public.bookings%ROWTYPE;
    v_updated_booking public.bookings%ROWTYPE;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501'; END IF;
    v_is_staff := public.is_staff();

    SELECT * INTO v_booking FROM public.bookings WHERE id = p_booking_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Booking not found'; END IF;
    IF v_booking.user_id <> v_user_id AND NOT v_is_staff THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501'; END IF;

    IF v_booking.status IN ('completed', 'released', 'cancelled', 'expired') THEN
        RAISE EXCEPTION 'Booking is already % and cannot be cancelled', v_booking.status;
    END IF;

    UPDATE public.bookings SET status = 'cancelled' WHERE id = p_booking_id RETURNING * INTO v_updated_booking;
    INSERT INTO public.events (room_id, booking_id, kind, reason)
    VALUES (v_booking.room_id, p_booking_id, 'booking_cancelled', 'Cancelled by ' || CASE WHEN v_is_staff THEN 'staff' ELSE 'student' END);

    RETURN to_jsonb(v_updated_booking);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- set_demo_preset
CREATE OR REPLACE FUNCTION public.set_demo_preset(p_demo_mode boolean)
RETURNS jsonb AS $$
DECLARE
    v_updated public.settings%ROWTYPE;
BEGIN
    IF NOT public.is_staff() THEN RAISE EXCEPTION 'Only staff can modify demo presets' USING ERRCODE = '42501'; END IF;

    IF p_demo_mode THEN
        UPDATE public.settings
        SET demo_mode = true, no_show_seconds = 60, confirm_window_seconds = 30, offline_threshold_seconds = 30, presence_window_seconds = 15
        WHERE id = 1 RETURNING * INTO v_updated;
    ELSE
        UPDATE public.settings
        SET demo_mode = false, no_show_seconds = 600, confirm_window_seconds = 300, offline_threshold_seconds = 120, presence_window_seconds = 60
        WHERE id = 1 RETURNING * INTO v_updated;
    END IF;

    RETURN to_jsonb(v_updated);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6. RULE ENGINE: run_rules()
CREATE OR REPLACE FUNCTION public.run_rules()
RETURNS jsonb AS $$
DECLARE
    v_settings public.settings%ROWTYPE;
    v_booking record;
    v_device record;
    v_room record;
    v_now timestamptz := now();
    v_is_sensor_offline boolean;
    v_has_presence boolean;
    v_already_logged_offline boolean;
    v_actions_taken jsonb[] := '{}';
    v_action_summary text;
BEGIN
    SELECT * INTO v_settings FROM public.settings WHERE id = 1;
    IF v_settings IS NULL THEN RETURN jsonb_build_object('status', 'error', 'message', 'Settings not found'); END IF;

    FOR v_booking IN
        SELECT b.* FROM public.bookings b
        WHERE b.status IN ('reserved', 'confirm_pending', 'active')
        ORDER BY b.start_time ASC
        FOR UPDATE SKIP LOCKED
    LOOP
        SELECT * INTO v_room FROM public.rooms WHERE id = v_booking.room_id;
        SELECT * INTO v_device FROM public.devices WHERE id = v_room.device_id;

        IF v_device.id IS NULL OR v_device.last_seen_at IS NULL THEN
            v_is_sensor_offline := true;
        ELSIF EXTRACT(EPOCH FROM (v_now - v_device.last_seen_at)) > v_settings.offline_threshold_seconds THEN
            v_is_sensor_offline := true;
        ELSE
            v_is_sensor_offline := false;
        END IF;

        SELECT EXISTS (
            SELECT 1 FROM public.sensor_readings
            WHERE device_id = v_device.id
              AND presence = true
              AND recorded_at >= GREATEST(v_booking.start_time, v_now - (v_settings.presence_window_seconds || ' seconds')::interval)
        ) INTO v_has_presence;

        -- RULE 1: reserved and now >= start_time
        IF v_booking.status = 'reserved' AND v_now >= v_booking.start_time THEN
            IF v_is_sensor_offline THEN
                SELECT EXISTS (
                    SELECT 1 FROM public.events
                    WHERE room_id = v_booking.room_id AND booking_id = v_booking.id
                      AND kind = 'skipped_sensor_offline'
                      AND at >= (v_now - (v_settings.offline_threshold_seconds || ' seconds')::interval)
                ) INTO v_already_logged_offline;

                IF NOT v_already_logged_offline THEN
                    INSERT INTO public.events (room_id, booking_id, kind, reason)
                    VALUES (v_booking.room_id, v_booking.id, 'skipped_sensor_offline',
                            'Sensor for ' || v_room.name || ' is offline. Skipping release check for safety.');
                END IF;

            ELSIF v_has_presence THEN
                UPDATE public.bookings SET status = 'active' WHERE id = v_booking.id;
                INSERT INTO public.events (room_id, booking_id, kind, reason)
                VALUES (v_booking.room_id, v_booking.id, 'checked_in_by_sensor',
                        'Presence confirmed by sensor in ' || v_room.name || '. Booking marked active.');
                v_actions_taken := array_append(v_actions_taken, jsonb_build_object('booking_id', v_booking.id, 'action', 'checked_in_by_sensor'));

            ELSIF v_now >= v_booking.no_show_check_at THEN
                UPDATE public.bookings
                SET status = 'confirm_pending',
                    confirm_deadline = v_now + (v_settings.confirm_window_seconds || ' seconds')::interval
                WHERE id = v_booking.id;

                INSERT INTO public.notifications (user_id, booking_id, kind, message)
                VALUES (v_booking.user_id, v_booking.id, 'confirm_attendance',
                        'Are you coming to ' || v_room.name || '? Please confirm within ' || (v_settings.confirm_window_seconds / 60) || ' minutes or your booking will be released.');

                INSERT INTO public.events (room_id, booking_id, kind, reason)
                VALUES (v_booking.room_id, v_booking.id, 'confirmation_requested',
                        'No presence detected at ' || to_char(v_booking.no_show_check_at, 'HH24:MI:SS') || '. Confirmation requested.');

                v_actions_taken := array_append(v_actions_taken, jsonb_build_object('booking_id', v_booking.id, 'action', 'confirmation_requested'));
            END IF;

        -- RULE 2: confirm_pending
        ELSIF v_booking.status = 'confirm_pending' THEN
            IF v_has_presence THEN
                UPDATE public.bookings SET status = 'active', confirm_deadline = NULL WHERE id = v_booking.id;
                INSERT INTO public.events (room_id, booking_id, kind, reason)
                VALUES (v_booking.room_id, v_booking.id, 'presence_detected_during_confirmation',
                        'Presence detected during confirmation window in ' || v_room.name || '. Promoted to active.');
                v_actions_taken := array_append(v_actions_taken, jsonb_build_object('booking_id', v_booking.id, 'action', 'presence_detected_during_confirmation'));

            ELSIF v_now >= v_booking.confirm_deadline THEN
                IF v_is_sensor_offline THEN
                    SELECT EXISTS (
                        SELECT 1 FROM public.events
                        WHERE room_id = v_booking.room_id AND booking_id = v_booking.id
                          AND kind = 'skipped_sensor_offline'
                          AND at >= (v_now - (v_settings.offline_threshold_seconds || ' seconds')::interval)
                    ) INTO v_already_logged_offline;

                    IF NOT v_already_logged_offline THEN
                        INSERT INTO public.events (room_id, booking_id, kind, reason)
                        VALUES (v_booking.room_id, v_booking.id, 'skipped_sensor_offline',
                                'Deadline reached but sensor is offline. Skipped auto-release for safety.');
                    END IF;
                ELSE
                    UPDATE public.bookings SET status = 'released' WHERE id = v_booking.id;
                    v_action_summary := 'Auto-released at ' || to_char(v_now, 'YYYY-MM-DD HH24:MI:SS') || 
                                        ' because confirm deadline (' || to_char(v_booking.confirm_deadline, 'HH24:MI:SS') || 
                                        ') passed without confirmation or presence readings.';

                    INSERT INTO public.events (room_id, booking_id, kind, reason)
                    VALUES (v_booking.room_id, v_booking.id, 'released', v_action_summary);

                    INSERT INTO public.notifications (user_id, booking_id, kind, message)
                    VALUES (v_booking.user_id, v_booking.id, 'booking_released',
                            'Your booking for ' || v_room.name || ' was released due to no-show.');

                    v_actions_taken := array_append(v_actions_taken, jsonb_build_object('booking_id', v_booking.id, 'action', 'released', 'reason', v_action_summary));
                END IF;
            END IF;

        -- RULE 3: active and now >= end_time -> completed
        ELSIF v_booking.status = 'active' AND v_now >= v_booking.end_time THEN
            UPDATE public.bookings SET status = 'completed' WHERE id = v_booking.id;
            INSERT INTO public.events (room_id, booking_id, kind, reason)
            VALUES (v_booking.room_id, v_booking.id, 'completed', 'Booking reached end time (' || to_char(v_booking.end_time, 'HH24:MI:SS') || ') and completed.');
            v_actions_taken := array_append(v_actions_taken, jsonb_build_object('booking_id', v_booking.id, 'action', 'completed'));

        -- RULE 4: reserved and now >= end_time without ever being active -> expired
        ELSIF v_booking.status = 'reserved' AND v_now >= v_booking.end_time THEN
            UPDATE public.bookings SET status = 'expired' WHERE id = v_booking.id;
            INSERT INTO public.events (room_id, booking_id, kind, reason)
            VALUES (v_booking.room_id, v_booking.id, 'expired', 'Booking expired without occupant.');
            v_actions_taken := array_append(v_actions_taken, jsonb_build_object('booking_id', v_booking.id, 'action', 'expired'));
        END IF;

    END LOOP;

    RETURN jsonb_build_object('timestamp', v_now, 'actions_count', array_length(v_actions_taken, 1), 'actions', to_jsonb(v_actions_taken));
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 7. SEED DATA
INSERT INTO public.settings (
    id, no_show_seconds, confirm_window_seconds, offline_threshold_seconds, max_extensions, presence_window_seconds, demo_mode
) VALUES (
    1, 600, 300, 120, 1, 60, false
) ON CONFLICT (id) DO UPDATE SET
    no_show_seconds = EXCLUDED.no_show_seconds,
    confirm_window_seconds = EXCLUDED.confirm_window_seconds,
    offline_threshold_seconds = EXCLUDED.offline_threshold_seconds,
    max_extensions = EXCLUDED.max_extensions,
    presence_window_seconds = EXCLUDED.presence_window_seconds,
    demo_mode = EXCLUDED.demo_mode;

-- Seed Devices (with hashed API keys)
INSERT INTO public.devices (id, api_key_hash, last_seen_at) VALUES
('device-room-101', encode(digest('dev_key_room_101_secret', 'sha256'), 'hex'), now()),
('device-room-102', encode(digest('dev_key_room_102_secret', 'sha256'), 'hex'), now()),
('device-sim-001',  encode(digest('sim_key_default_dev', 'sha256'), 'hex'), now())
ON CONFLICT (id) DO UPDATE SET api_key_hash = EXCLUDED.api_key_hash, last_seen_at = EXCLUDED.last_seen_at;

-- Seed Rooms
INSERT INTO public.rooms (id, name, capacity, device_id) VALUES
('11111111-1111-1111-1111-111111111111', 'Room 101 - Focus Pod', 4, 'device-room-101'),
('22222222-2222-2222-2222-222222222222', 'Room 102 - Collab Studio', 8, 'device-room-102')
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, capacity = EXCLUDED.capacity, device_id = EXCLUDED.device_id;

-- Seed Auth Users & Profiles (Alice, Bob, Staff)
DO $$
DECLARE
    staff_id uuid := 'a1111111-1111-1111-1111-111111111111';
    student1_id uuid := 'b2222222-2222-2222-2222-222222222222';
    student2_id uuid := 'c3333333-3333-3333-3333-333333333333';
    pw_hash text := crypt('password123', gen_salt('bf'));
BEGIN
    IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = staff_id) THEN
        INSERT INTO auth.users (
            instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
            raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token
        ) VALUES (
            '00000000-0000-0000-0000-000000000000', staff_id, 'authenticated', 'authenticated',
            'staff@roompulse.local', pw_hash, now(),
            '{"provider":"email","providers":["email"]}', '{"display_name":"Library Staff"}',
            now(), now(), ''
        );
    END IF;

    IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = student1_id) THEN
        INSERT INTO auth.users (
            instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
            raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token
        ) VALUES (
            '00000000-0000-0000-0000-000000000000', student1_id, 'authenticated', 'authenticated',
            'student1@roompulse.local', pw_hash, now(),
            '{"provider":"email","providers":["email"]}', '{"display_name":"Alice (Student)"}',
            now(), now(), ''
        );
    END IF;

    IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = student2_id) THEN
        INSERT INTO auth.users (
            instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
            raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token
        ) VALUES (
            '00000000-0000-0000-0000-000000000000', student2_id, 'authenticated', 'authenticated',
            'student2@roompulse.local', pw_hash, now(),
            '{"provider":"email","providers":["email"]}', '{"display_name":"Bob (Student)"}',
            now(), now(), ''
        );
    END IF;

    INSERT INTO public.profiles (id, display_name, role) VALUES
    (staff_id, 'Library Staff Lead', 'staff'),
    (student1_id, 'Alice Pratama', 'student'),
    (student2_id, 'Bob Santoso', 'student')
    ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name, role = EXCLUDED.role;
END $$;
