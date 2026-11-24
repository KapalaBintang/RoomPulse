-- Phase 3 Migration: Rule Engine, RPCs, Views, and Trigger Automation
-- STACK 2026 RoomPulse

-- 1. View: rooms_with_status
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
    -- Determine if sensor is offline
    CASE
        WHEN dev.id IS NULL OR dev.last_seen_at IS NULL THEN true
        WHEN EXTRACT(EPOCH FROM (now() - dev.last_seen_at)) > (SELECT offline_threshold_seconds FROM public.settings WHERE id = 1) THEN true
        ELSE false
    END AS is_sensor_offline,
    -- Computed Display Status: available, reserved, confirm_pending, occupied
    CASE
        WHEN cb.booking_status = 'active' THEN 'occupied'
        WHEN cb.booking_status = 'confirm_pending' THEN 'confirm_pending'
        WHEN cb.booking_status = 'reserved' THEN 'reserved'
        WHEN lr.presence = true THEN 'occupied' -- unscheduled occupant / walk-in
        ELSE 'available'
    END AS display_status,
    -- Next free slot calculation hint
    CASE
        WHEN cb.end_time IS NOT NULL AND cb.end_time > now() THEN cb.end_time
        ELSE now()
    END AS next_free_slot
FROM public.rooms rm
LEFT JOIN public.devices dev ON rm.device_id = dev.id
LEFT JOIN current_bookings cb ON rm.id = cb.room_id
LEFT JOIN latest_readings lr ON rm.device_id = lr.device_id;

-- 2. View: admin_summary
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

-- 3. RPC: create_booking
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

    -- Duration validation
    IF p_duration_minutes <= 0 OR p_duration_minutes > 120 THEN
        RAISE EXCEPTION 'Booking duration must be between 1 and 120 minutes';
    END IF;

    -- Past-time validation (allow 5-minute clock drift margin)
    IF p_start_time < (now() - interval '5 minutes') THEN
        RAISE EXCEPTION 'Cannot book a room in the past';
    END IF;

    v_end_time := p_start_time + (p_duration_minutes || ' minutes')::interval;

    -- Get settings
    SELECT no_show_seconds INTO v_no_show_seconds FROM public.settings WHERE id = 1;
    IF v_no_show_seconds IS NULL THEN
        v_no_show_seconds := 600;
    END IF;

    v_no_show_check_at := p_start_time + (v_no_show_seconds || ' seconds')::interval;

    -- Insert booking (exclusion constraint catches overlaps)
    BEGIN
        INSERT INTO public.bookings (
            room_id,
            user_id,
            start_time,
            end_time,
            status,
            extension_count,
            no_show_check_at,
            created_at
        ) VALUES (
            p_room_id,
            v_user_id,
            p_start_time,
            v_end_time,
            'reserved',
            0,
            v_no_show_check_at,
            now()
        ) RETURNING * INTO v_new_booking;
    EXCEPTION
        WHEN exclusion_violation THEN
            RAISE EXCEPTION 'Selected room is already booked for this time window. Please choose another time or room.';
    END;

    -- Log audit event
    INSERT INTO public.events (room_id, booking_id, kind, reason)
    VALUES (
        p_room_id,
        v_new_booking.id,
        'booking_created',
        'Booked for ' || p_duration_minutes || 'm by student (' || v_user_id || ')'
    );

    RETURN to_jsonb(v_new_booking);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. RPC: respond_booking
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

    -- Validate action
    IF p_action NOT IN ('coming', 'late_10', 'late_20', 'cancel') THEN
        RAISE EXCEPTION 'Invalid action: must be coming, late_10, late_20, or cancel';
    END IF;

    -- Lock and retrieve booking
    SELECT * INTO v_booking
    FROM public.bookings
    WHERE id = p_booking_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Booking not found';
    END IF;

    -- Only the owner can respond
    IF v_booking.user_id <> v_user_id THEN
        RAISE EXCEPTION 'Only the booking owner can respond' USING ERRCODE = '42501';
    END IF;

    -- Only when confirm_pending
    IF v_booking.status <> 'confirm_pending' THEN
        RAISE EXCEPTION 'Booking is not pending confirmation (current status: %)', v_booking.status;
    END IF;

    SELECT * INTO v_settings FROM public.settings WHERE id = 1;

    IF p_action = 'cancel' THEN
        UPDATE public.bookings
        SET status = 'cancelled'
        WHERE id = p_booking_id
        RETURNING * INTO v_updated_booking;

        INSERT INTO public.events (room_id, booking_id, kind, reason)
        VALUES (v_booking.room_id, p_booking_id, 'booking_cancelled_by_user', 'User cancelled booking in response to confirmation request');

        RETURN to_jsonb(v_updated_booking);
    END IF;

    -- Handle extensions: coming / late_10 / late_20
    IF v_booking.extension_count >= v_settings.max_extensions THEN
        RAISE EXCEPTION 'Maximum allowed extensions (%) already reached for this booking', v_settings.max_extensions;
    END IF;

    IF p_action = 'coming' THEN
        v_extra_minutes := 10;
    ELSIF p_action = 'late_10' THEN
        v_extra_minutes := 10;
    ELSIF p_action = 'late_20' THEN
        v_extra_minutes := 20;
    END IF;

    UPDATE public.bookings
    SET status = 'reserved',
        extension_count = extension_count + 1,
        no_show_check_at = GREATEST(now(), no_show_check_at) + (v_extra_minutes || ' minutes')::interval,
        confirm_deadline = NULL
    WHERE id = p_booking_id
    RETURNING * INTO v_updated_booking;

    INSERT INTO public.events (room_id, booking_id, kind, reason)
    VALUES (
        v_booking.room_id,
        p_booking_id,
        'extension_granted',
        'Booker responded "' || p_action || '". Extended no-show check by ' || v_extra_minutes || 'm'
    );

    RETURN to_jsonb(v_updated_booking);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. RPC: cancel_booking
CREATE OR REPLACE FUNCTION public.cancel_booking(
    p_booking_id uuid
)
RETURNS jsonb AS $$
DECLARE
    v_user_id uuid;
    v_is_staff boolean;
    v_booking public.bookings%ROWTYPE;
    v_updated_booking public.bookings%ROWTYPE;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;

    v_is_staff := public.is_staff();

    SELECT * INTO v_booking
    FROM public.bookings
    WHERE id = p_booking_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Booking not found';
    END IF;

    IF v_booking.user_id <> v_user_id AND NOT v_is_staff THEN
        RAISE EXCEPTION 'Not authorized to cancel this booking' USING ERRCODE = '42501';
    END IF;

    IF v_booking.status IN ('completed', 'released', 'cancelled', 'expired') THEN
        RAISE EXCEPTION 'Booking is already % and cannot be cancelled', v_booking.status;
    END IF;

    UPDATE public.bookings
    SET status = 'cancelled'
    WHERE id = p_booking_id
    RETURNING * INTO v_updated_booking;

    INSERT INTO public.events (room_id, booking_id, kind, reason)
    VALUES (
        v_booking.room_id,
        p_booking_id,
        'booking_cancelled',
        'Booking cancelled by ' || CASE WHEN v_is_staff THEN 'staff' ELSE 'student' END
    );

    RETURN to_jsonb(v_updated_booking);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6. RPC: set_demo_preset (P0/P1 staff control)
CREATE OR REPLACE FUNCTION public.set_demo_preset(
    p_demo_mode boolean
)
RETURNS jsonb AS $$
DECLARE
    v_updated public.settings%ROWTYPE;
BEGIN
    IF NOT public.is_staff() THEN
        RAISE EXCEPTION 'Only staff can modify demo presets' USING ERRCODE = '42501';
    END IF;

    IF p_demo_mode THEN
        -- Demo preset: 60s no-show check, 30s confirmation window, 30s offline threshold, 15s presence window
        UPDATE public.settings
        SET demo_mode = true,
            no_show_seconds = 60,
            confirm_window_seconds = 30,
            offline_threshold_seconds = 30,
            presence_window_seconds = 15
        WHERE id = 1
        RETURNING * INTO v_updated;
    ELSE
        -- Normal preset: 600s no-show, 300s confirm window, 120s offline threshold, 60s presence window
        UPDATE public.settings
        SET demo_mode = false,
            no_show_seconds = 600,
            confirm_window_seconds = 300,
            offline_threshold_seconds = 120,
            presence_window_seconds = 60
        WHERE id = 1
        RETURNING * INTO v_updated;
    END IF;

    RETURN to_jsonb(v_updated);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 7. THE RULE ENGINE: run_rules()
-- Idempotent, uses SELECT ... FOR UPDATE SKIP LOCKED
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
    -- Read current settings
    SELECT * INTO v_settings FROM public.settings WHERE id = 1;
    IF v_settings IS NULL THEN
        RETURN jsonb_build_object('status', 'error', 'message', 'Settings not found');
    END IF;

    -- Iterate active-ish bookings with row locking
    FOR v_booking IN
        SELECT b.*
        FROM public.bookings b
        WHERE b.status IN ('reserved', 'confirm_pending', 'active')
        ORDER BY b.start_time ASC
        FOR UPDATE SKIP LOCKED
    LOOP
        -- Fetch room and device details
        SELECT * INTO v_room FROM public.rooms WHERE id = v_booking.room_id;
        SELECT * INTO v_device FROM public.devices WHERE id = v_room.device_id;

        -- Check sensor offline status
        -- Safety rule: if sensor offline, NEVER release bookings
        IF v_device.id IS NULL OR v_device.last_seen_at IS NULL THEN
            v_is_sensor_offline := true;
        ELSIF EXTRACT(EPOCH FROM (v_now - v_device.last_seen_at)) > v_settings.offline_threshold_seconds THEN
            v_is_sensor_offline := true;
        ELSE
            v_is_sensor_offline := false;
        END IF;

        -- Check presence readings since start_time within presence_window_seconds
        -- (or within confirmation window if confirm_pending)
        SELECT EXISTS (
            SELECT 1 FROM public.sensor_readings
            WHERE device_id = v_device.id
              AND presence = true
              AND recorded_at >= GREATEST(
                  v_booking.start_time,
                  v_now - (v_settings.presence_window_seconds || ' seconds')::interval
              )
        ) INTO v_has_presence;

        -- -------------------------------------------------------------
        -- RULE 1: reserved and now >= start_time
        -- -------------------------------------------------------------
        IF v_booking.status = 'reserved' AND v_now >= v_booking.start_time THEN
            IF v_is_sensor_offline THEN
                -- Check if skipped_sensor_offline already logged once in this offline period
                SELECT EXISTS (
                    SELECT 1 FROM public.events
                    WHERE room_id = v_booking.room_id
                      AND booking_id = v_booking.id
                      AND kind = 'skipped_sensor_offline'
                      AND at >= (v_now - (v_settings.offline_threshold_seconds || ' seconds')::interval)
                ) INTO v_already_logged_offline;

                IF NOT v_already_logged_offline THEN
                    INSERT INTO public.events (room_id, booking_id, kind, reason)
                    VALUES (
                        v_booking.room_id,
                        v_booking.id,
                        'skipped_sensor_offline',
                        'Sensor for ' || v_room.name || ' is offline (last seen ' || COALESCE(to_char(v_device.last_seen_at, 'YYYY-MM-DD HH24:MI:SS OF'), 'never') || '). Skipping release check for safety.'
                    );
                END IF;

            ELSIF v_has_presence THEN
                -- Presence detected within window -> status active
                UPDATE public.bookings
                SET status = 'active'
                WHERE id = v_booking.id;

                INSERT INTO public.events (room_id, booking_id, kind, reason)
                VALUES (
                    v_booking.room_id,
                    v_booking.id,
                    'checked_in_by_sensor',
                    'Presence confirmed by mmWave sensor in ' || v_room.name || '. Booking marked active.'
                );

                v_actions_taken := array_append(v_actions_taken, jsonb_build_object(
                    'booking_id', v_booking.id,
                    'action', 'checked_in_by_sensor',
                    'room', v_room.name
                ));

            ELSIF v_now >= v_booking.no_show_check_at THEN
                -- No presence detected and no_show_check_at reached -> confirm_pending
                UPDATE public.bookings
                SET status = 'confirm_pending',
                    confirm_deadline = v_now + (v_settings.confirm_window_seconds || ' seconds')::interval
                WHERE id = v_booking.id;

                INSERT INTO public.notifications (user_id, booking_id, kind, message)
                VALUES (
                    v_booking.user_id,
                    v_booking.id,
                    'confirm_attendance',
                    'Are you coming to ' || v_room.name || '? Please confirm within ' || (v_settings.confirm_window_seconds / 60) || ' minutes or your booking will be released.'
                );

                INSERT INTO public.events (room_id, booking_id, kind, reason)
                VALUES (
                    v_booking.room_id,
                    v_booking.id,
                    'confirmation_requested',
                    'No presence detected at ' || to_char(v_booking.no_show_check_at, 'HH24:MI:SS') || '. Confirmation requested from user with deadline ' || to_char(v_now + (v_settings.confirm_window_seconds || ' seconds')::interval, 'HH24:MI:SS')
                );

                v_actions_taken := array_append(v_actions_taken, jsonb_build_object(
                    'booking_id', v_booking.id,
                    'action', 'confirmation_requested',
                    'room', v_room.name
                ));
            END IF;

        -- -------------------------------------------------------------
        -- RULE 2: confirm_pending
        -- -------------------------------------------------------------
        ELSIF v_booking.status = 'confirm_pending' THEN
            IF v_has_presence THEN
                -- Presence arrived during confirmation period -> active
                UPDATE public.bookings
                SET status = 'active',
                    confirm_deadline = NULL
                WHERE id = v_booking.id;

                INSERT INTO public.events (room_id, booking_id, kind, reason)
                VALUES (
                    v_booking.room_id,
                    v_booking.id,
                    'presence_detected_during_confirmation',
                    'Presence detected by sensor during confirmation window in ' || v_room.name || '. Automatically promoted to active.'
                );

                v_actions_taken := array_append(v_actions_taken, jsonb_build_object(
                    'booking_id', v_booking.id,
                    'action', 'presence_detected_during_confirmation',
                    'room', v_room.name
                ));

            ELSIF v_now >= v_booking.confirm_deadline THEN
                -- Safety check: NEVER release if sensor is offline
                IF v_is_sensor_offline THEN
                    SELECT EXISTS (
                        SELECT 1 FROM public.events
                        WHERE room_id = v_booking.room_id
                          AND booking_id = v_booking.id
                          AND kind = 'skipped_sensor_offline'
                          AND at >= (v_now - (v_settings.offline_threshold_seconds || ' seconds')::interval)
                    ) INTO v_already_logged_offline;

                    IF NOT v_already_logged_offline THEN
                        INSERT INTO public.events (room_id, booking_id, kind, reason)
                        VALUES (
                            v_booking.room_id,
                            v_booking.id,
                            'skipped_sensor_offline',
                            'Deadline reached but sensor is offline. Skipped auto-release for safety.'
                        );
                    END IF;
                ELSE
                    -- Sensor online and no presence -> status released
                    UPDATE public.bookings
                    SET status = 'released'
                    WHERE id = v_booking.id;

                    v_action_summary := 'Auto-released at ' || to_char(v_now, 'YYYY-MM-DD HH24:MI:SS') || 
                                        ' because confirm deadline (' || to_char(v_booking.confirm_deadline, 'HH24:MI:SS') || 
                                        ') passed without confirmation or presence readings.';

                    INSERT INTO public.events (room_id, booking_id, kind, reason)
                    VALUES (
                        v_booking.room_id,
                        v_booking.id,
                        'released',
                        v_action_summary
                    );

                    INSERT INTO public.notifications (user_id, booking_id, kind, message)
                    VALUES (
                        v_booking.user_id,
                        v_booking.id,
                        'booking_released',
                        'Your booking for ' || v_room.name || ' was released due to no-show and no confirmation response.'
                    );

                    v_actions_taken := array_append(v_actions_taken, jsonb_build_object(
                        'booking_id', v_booking.id,
                        'action', 'released',
                        'room', v_room.name,
                        'reason', v_action_summary
                    ));
                END IF;
            END IF;

        -- -------------------------------------------------------------
        -- RULE 3: active and now >= end_time -> completed
        -- -------------------------------------------------------------
        ELSIF v_booking.status = 'active' AND v_now >= v_booking.end_time THEN
            UPDATE public.bookings
            SET status = 'completed'
            WHERE id = v_booking.id;

            INSERT INTO public.events (room_id, booking_id, kind, reason)
            VALUES (
                v_booking.room_id,
                v_booking.id,
                'completed',
                'Booking reached end time (' || to_char(v_booking.end_time, 'HH24:MI:SS') || ') and completed.'
            );

            v_actions_taken := array_append(v_actions_taken, jsonb_build_object(
                'booking_id', v_booking.id,
                'action', 'completed',
                'room', v_room.name
            ));

        -- -------------------------------------------------------------
        -- RULE 4: reserved and now >= end_time without ever being active -> expired
        -- -------------------------------------------------------------
        ELSIF v_booking.status = 'reserved' AND v_now >= v_booking.end_time THEN
            UPDATE public.bookings
            SET status = 'expired'
            WHERE id = v_booking.id;

            INSERT INTO public.events (room_id, booking_id, kind, reason)
            VALUES (
                v_booking.room_id,
                v_booking.id,
                'expired',
                'Booking expired at end time (' || to_char(v_booking.end_time, 'HH24:MI:SS') || ') without occupant.'
            );

            v_actions_taken := array_append(v_actions_taken, jsonb_build_object(
                'booking_id', v_booking.id,
                'action', 'expired',
                'room', v_room.name
            ));
        END IF;

    END LOOP;

    RETURN jsonb_build_object(
        'timestamp', v_now,
        'actions_count', array_length(v_actions_taken, 1),
        'actions', to_jsonb(v_actions_taken)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
