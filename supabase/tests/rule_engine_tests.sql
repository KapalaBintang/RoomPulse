-- Comprehensive SQL Acceptance Tests for RoomPulse Rule Engine & RPCs
-- STACK 2026 Semifinal Prototype

BEGIN;

-- Create temporary test helper function
CREATE OR REPLACE FUNCTION pg_temp.assert(condition boolean, message text) RETURNS void AS $$
BEGIN
    IF NOT condition THEN
        RAISE EXCEPTION 'ASSERTION FAILED: %', message;
    ELSE
        RAISE NOTICE 'PASSED: %', message;
    END IF;
END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE
    v_room_id uuid := '11111111-1111-1111-1111-111111111111';
    v_device_id text := 'device-room-101';
    v_student1_id uuid := 'b2222222-2222-2222-2222-222222222222';
    v_student2_id uuid := 'c3333333-3333-3333-3333-333333333333';
    v_booking_id uuid;
    v_b public.bookings%ROWTYPE;
    v_rules_res jsonb;
    v_err_caught boolean;
BEGIN
    RAISE NOTICE '==================================================';
    RAISE NOTICE 'STARTING TEST SUITE: RoomPulse Rules & RPCs';
    RAISE NOTICE '==================================================';

    -- Set demo preset: 60s no-show, 30s confirm window, 30s offline threshold, 15s presence
    UPDATE public.settings
    SET demo_mode = true,
        no_show_seconds = 60,
        confirm_window_seconds = 30,
        offline_threshold_seconds = 30,
        presence_window_seconds = 15,
        max_extensions = 1
    WHERE id = 1;

    -- Clean up test records
    DELETE FROM public.sensor_readings WHERE device_id = v_device_id;
    DELETE FROM public.bookings WHERE room_id = v_room_id;
    DELETE FROM public.events WHERE room_id = v_room_id;
    DELETE FROM public.notifications WHERE user_id = v_student1_id;

    -- -------------------------------------------------------------
    -- TEST 1: Normal Check-In via Sensor Presence
    -- -------------------------------------------------------------
    RAISE NOTICE '--- TEST 1: Normal Check-In via Sensor Presence ---';
    -- Insert a booking starting now
    INSERT INTO public.bookings (
        room_id, user_id, start_time, end_time, status, no_show_check_at, created_at
    ) VALUES (
        v_room_id, v_student1_id, now(), now() + interval '60 minutes', 'reserved', now() + interval '60 seconds', now()
    ) RETURNING id INTO v_booking_id;

    -- Device is online and sends presence
    UPDATE public.devices SET last_seen_at = now() WHERE id = v_device_id;
    INSERT INTO public.sensor_readings (
        device_id, recorded_at, presence, moving, stationary, moving_energy, static_energy, distance_cm, source
    ) VALUES (
        v_device_id, now(), true, true, true, 40, 80, 120, 'device'
    );

    -- Run rules
    PERFORM public.run_rules();

    -- Verify booking became active
    SELECT * INTO v_b FROM public.bookings WHERE id = v_booking_id;
    PERFORM pg_temp.assert(v_b.status = 'active', 'Booking status should transition to active on presence');
    PERFORM pg_temp.assert(EXISTS (
        SELECT 1 FROM public.events WHERE booking_id = v_booking_id AND kind = 'checked_in_by_sensor'
    ), 'Event checked_in_by_sensor should be logged');

    -- Clean up test 1 booking
    DELETE FROM public.bookings WHERE id = v_booking_id;


    -- -------------------------------------------------------------
    -- TEST 2: No-Show Confirmation and Automatic Release
    -- -------------------------------------------------------------
    RAISE NOTICE '--- TEST 2: No-Show Confirmation and Automatic Release ---';
    -- Insert a booking whose no_show_check_at has passed and room is empty
    INSERT INTO public.bookings (
        room_id, user_id, start_time, end_time, status, no_show_check_at, created_at
    ) VALUES (
        v_room_id, v_student1_id, now() - interval '70 seconds', now() + interval '50 minutes',
        'reserved', now() - interval '10 seconds', now() - interval '70 seconds'
    ) RETURNING id INTO v_booking_id;

    -- Device is online, empty readings
    UPDATE public.devices SET last_seen_at = now() WHERE id = v_device_id;
    INSERT INTO public.sensor_readings (
        device_id, recorded_at, presence, moving, stationary, moving_energy, static_energy, distance_cm, source
    ) VALUES (
        v_device_id, now(), false, false, false, 0, 0, 0, 'device'
    );

    -- Run rules -> should transition to confirm_pending
    PERFORM public.run_rules();

    SELECT * INTO v_b FROM public.bookings WHERE id = v_booking_id;
    PERFORM pg_temp.assert(v_b.status = 'confirm_pending', 'Booking should become confirm_pending when no-show check arrives');
    PERFORM pg_temp.assert(v_b.confirm_deadline IS NOT NULL, 'Confirm deadline must be set');
    PERFORM pg_temp.assert(EXISTS (
        SELECT 1 FROM public.notifications WHERE booking_id = v_booking_id AND kind = 'confirm_attendance'
    ), 'Notification should be generated for user');

    -- Now simulate confirm_deadline expiration without reply or presence
    UPDATE public.bookings
    SET confirm_deadline = now() - interval '5 seconds'
    WHERE id = v_booking_id;

    -- Run rules again -> should release booking
    PERFORM public.run_rules();

    SELECT * INTO v_b FROM public.bookings WHERE id = v_booking_id;
    PERFORM pg_temp.assert(v_b.status = 'released', 'Booking should be released after confirm deadline expires');
    PERFORM pg_temp.assert(EXISTS (
        SELECT 1 FROM public.events WHERE booking_id = v_booking_id AND kind = 'released'
    ), 'Event released should be logged');

    DELETE FROM public.bookings WHERE id = v_booking_id;


    -- -------------------------------------------------------------
    -- TEST 3: Late Extension - Allowed Once, Refused on Second Attempt
    -- -------------------------------------------------------------
    RAISE NOTICE '--- TEST 3: Late Extension (Max Extensions Enforcement) ---';
    -- Create a confirm_pending booking
    INSERT INTO public.bookings (
        room_id, user_id, start_time, end_time, status, confirm_deadline, extension_count, no_show_check_at, created_at
    ) VALUES (
        v_room_id, v_student1_id, now() - interval '30 minutes', now() + interval '30 minutes',
        'confirm_pending', now() + interval '5 minutes', 0, now(), now()
    ) RETURNING id INTO v_booking_id;

    -- Mock auth context as student1
    PERFORM set_config('request.jwt.claim.sub', v_student1_id::text, true);

    -- First extension ('late_10') -> should succeed
    PERFORM public.respond_booking(v_booking_id, 'late_10');
    SELECT * INTO v_b FROM public.bookings WHERE id = v_booking_id;
    PERFORM pg_temp.assert(v_b.extension_count = 1, 'Extension count should be 1');
    PERFORM pg_temp.assert(v_b.status = 'reserved', 'Status should return to reserved with extended time');

    -- Put it back to confirm_pending for second test
    UPDATE public.bookings SET status = 'confirm_pending' WHERE id = v_booking_id;

    -- Second extension attempt -> should be refused with exception
    v_err_caught := false;
    BEGIN
        PERFORM public.respond_booking(v_booking_id, 'late_10');
    EXCEPTION WHEN OTHERS THEN
        v_err_caught := true;
        RAISE NOTICE 'Expected refusal caught: %', SQLERRM;
    END;
    PERFORM pg_temp.assert(v_err_caught, 'Second extension must be rejected');

    DELETE FROM public.bookings WHERE id = v_booking_id;


    -- -------------------------------------------------------------
    -- TEST 4: Sensor Offline Safety Rule - NEVER Release
    -- -------------------------------------------------------------
    RAISE NOTICE '--- TEST 4: Sensor Offline Safety (No Release When Sensor Offline) ---';
    -- Sensor last seen 200 seconds ago (threshold is 30s in demo)
    UPDATE public.devices
    SET last_seen_at = now() - interval '200 seconds'
    WHERE id = v_device_id;

    -- Insert confirm_pending booking whose deadline has expired
    INSERT INTO public.bookings (
        room_id, user_id, start_time, end_time, status, confirm_deadline, extension_count, no_show_check_at, created_at
    ) VALUES (
        v_room_id, v_student1_id, now() - interval '40 minutes', now() + interval '20 minutes',
        'confirm_pending', now() - interval '10 seconds', 0, now() - interval '20 minutes', now()
    ) RETURNING id INTO v_booking_id;

    -- Run rules -> Must NOT release!
    PERFORM public.run_rules();

    SELECT * INTO v_b FROM public.bookings WHERE id = v_booking_id;
    PERFORM pg_temp.assert(v_b.status = 'confirm_pending', 'Booking must remain confirm_pending when sensor is offline (safety rule)');
    PERFORM pg_temp.assert(EXISTS (
        SELECT 1 FROM public.events WHERE booking_id = v_booking_id AND kind = 'skipped_sensor_offline'
    ), 'Audit event skipped_sensor_offline must be logged');

    DELETE FROM public.bookings WHERE id = v_booking_id;


    -- -------------------------------------------------------------
    -- TEST 5: Overlapping Booking Rejection (Exclusion Constraint)
    -- -------------------------------------------------------------
    RAISE NOTICE '--- TEST 5: Overlapping Booking Rejection ---';
    -- Create active booking from T to T+60m
    INSERT INTO public.bookings (
        room_id, user_id, start_time, end_time, status, no_show_check_at, created_at
    ) VALUES (
        v_room_id, v_student1_id, now() + interval '10 minutes', now() + interval '70 minutes',
        'reserved', now() + interval '20 minutes', now()
    ) RETURNING id INTO v_booking_id;

    -- Attempt overlapping booking (T+30m to T+90m)
    v_err_caught := false;
    BEGIN
        INSERT INTO public.bookings (
            room_id, user_id, start_time, end_time, status, no_show_check_at, created_at
        ) VALUES (
            v_room_id, v_student2_id, now() + interval '30 minutes', now() + interval '90 minutes',
            'reserved', now() + interval '40 minutes', now()
        );
    EXCEPTION WHEN exclusion_violation THEN
        v_err_caught := true;
        RAISE NOTICE 'Exclusion violation correctly caught: double booking blocked';
    END;
    PERFORM pg_temp.assert(v_err_caught, 'Exclusion constraint must reject overlapping active booking');

    DELETE FROM public.bookings WHERE id = v_booking_id;


    -- -------------------------------------------------------------
    -- TEST 6: Presence Arriving During Confirmation Window
    -- -------------------------------------------------------------
    RAISE NOTICE '--- TEST 6: Presence Arriving During Confirmation Window ---';
    UPDATE public.devices SET last_seen_at = now() WHERE id = v_device_id;

    -- Insert confirm_pending booking
    INSERT INTO public.bookings (
        room_id, user_id, start_time, end_time, status, confirm_deadline, extension_count, no_show_check_at, created_at
    ) VALUES (
        v_room_id, v_student1_id, now() - interval '20 minutes', now() + interval '40 minutes',
        'confirm_pending', now() + interval '3 minutes', 0, now() - interval '5 minutes', now()
    ) RETURNING id INTO v_booking_id;

    -- Student walks into the room -> sensor detects presence!
    INSERT INTO public.sensor_readings (
        device_id, recorded_at, presence, moving, stationary, moving_energy, static_energy, distance_cm, source
    ) VALUES (
        v_device_id, now(), true, true, true, 50, 85, 130, 'device'
    );

    -- Run rules -> should immediately activate booking!
    PERFORM public.run_rules();

    SELECT * INTO v_b FROM public.bookings WHERE id = v_booking_id;
    PERFORM pg_temp.assert(v_b.status = 'active', 'Booking should automatically become active when presence detected during confirmation');
    PERFORM pg_temp.assert(v_b.confirm_deadline IS NULL, 'Confirm deadline should be cleared upon presence');
    PERFORM pg_temp.assert(EXISTS (
        SELECT 1 FROM public.events WHERE booking_id = v_booking_id AND kind = 'presence_detected_during_confirmation'
    ), 'Event presence_detected_during_confirmation must be logged');

    DELETE FROM public.bookings WHERE id = v_booking_id;

    RAISE NOTICE '==================================================';
    RAISE NOTICE 'ALL 6 ACCEPTANCE TESTS PASSED SUCCESSFULLY!';
    RAISE NOTICE '==================================================';
END $$;

ROLLBACK;
