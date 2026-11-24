-- Seed data for RoomPulse (STACK 2026 Semifinal Prototype)

-- 1. Initialize Single Settings Row
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

-- 2. Seed Demo Devices
-- Raw Dev Keys:
-- device-room-101: "dev_key_room_101_secret" -> SHA256: 0e7cf2436d4f7a26fba65476d05da9336184a4cb1a5dd469dd1c107bf385b2ad
-- device-room-102: "dev_key_room_102_secret" -> SHA256: d8dcfd5eb773ce02be9635c91104e7609a63327d6d5ebbf117d9df4841fb00aa
-- simulator key:   "sim_key_default_dev"     -> SHA256: 7f0a996f019fa39cb0e1b6f0e4bfa0d8d73b2c2f7b64082269a8b1a20ef136fb
INSERT INTO public.devices (id, api_key_hash, last_seen_at) VALUES
('device-room-101', encode(digest('dev_key_room_101_secret', 'sha256'), 'hex'), now()),
('device-room-102', encode(digest('dev_key_room_102_secret', 'sha256'), 'hex'), now()),
('device-sim-001',  encode(digest('sim_key_default_dev', 'sha256'), 'hex'), now())
ON CONFLICT (id) DO UPDATE SET
    api_key_hash = EXCLUDED.api_key_hash,
    last_seen_at = EXCLUDED.last_seen_at;

-- 3. Seed Rooms
INSERT INTO public.rooms (id, name, capacity, device_id) VALUES
('11111111-1111-1111-1111-111111111111', 'Room 101 - Focus Pod', 4, 'device-room-101'),
('22222222-2222-2222-2222-222222222222', 'Room 102 - Collab Studio', 8, 'device-room-102')
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    capacity = EXCLUDED.capacity,
    device_id = EXCLUDED.device_id;

-- 4. Seed Auth Users (1 Staff, 2 Students)
-- We insert directly into auth.users with encrypted passwords ('password123')
DO $$
DECLARE
    staff_id uuid := 'a1111111-1111-1111-1111-111111111111';
    student1_id uuid := 'b2222222-2222-2222-2222-222222222222';
    student2_id uuid := 'c3333333-3333-3333-3333-333333333333';
    pw_hash text := crypt('password123', gen_salt('bf'));
BEGIN
    -- Staff
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

    -- Student 1
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

    -- Student 2
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

    -- Profiles
    INSERT INTO public.profiles (id, display_name, role) VALUES
    (staff_id, 'Library Staff Lead', 'staff'),
    (student1_id, 'Alice Pratama', 'student'),
    (student2_id, 'Bob Santoso', 'student')
    ON CONFLICT (id) DO UPDATE SET
        display_name = EXCLUDED.display_name,
        role = EXCLUDED.role;
END $$;
