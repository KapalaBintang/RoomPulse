-- Phase 1 Migration: Initial Schema, Constraints, RLS, and Extensions
-- STACK 2026 RoomPulse

CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 1. Devices Table
CREATE TABLE IF NOT EXISTS public.devices (
    id text PRIMARY KEY,
    api_key_hash text NOT NULL,
    last_seen_at timestamptz NULL
);

-- 2. Rooms Table
CREATE TABLE IF NOT EXISTS public.rooms (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL,
    capacity int NOT NULL CHECK (capacity > 0),
    device_id text UNIQUE REFERENCES public.devices(id) ON DELETE SET NULL
);

-- 3. Sensor Readings Table
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

-- 4. User Profiles Table
CREATE TABLE IF NOT EXISTS public.profiles (
    id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    display_name text NOT NULL,
    role text NOT NULL CHECK (role IN ('student', 'staff')) DEFAULT 'student',
    telegram_chat_id text NULL
);

-- 5. Bookings Table
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

-- 6. Events Audit Log Table
CREATE TABLE IF NOT EXISTS public.events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    at timestamptz NOT NULL DEFAULT now(),
    booking_id uuid REFERENCES public.bookings(id) ON DELETE SET NULL,
    room_id uuid NOT NULL REFERENCES public.rooms(id) ON DELETE CASCADE,
    kind text NOT NULL,
    reason text NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_events_at ON public.events(at DESC);

-- 7. Notifications Table
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

-- 8. Settings Table (Single-row configuration)
CREATE TABLE IF NOT EXISTS public.settings (
    id int PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    no_show_seconds int NOT NULL DEFAULT 600,
    confirm_window_seconds int NOT NULL DEFAULT 300,
    offline_threshold_seconds int NOT NULL DEFAULT 120,
    max_extensions int NOT NULL DEFAULT 1,
    presence_window_seconds int NOT NULL DEFAULT 60,
    demo_mode boolean NOT NULL DEFAULT false
);

-- Helper function to check if current user is staff
CREATE OR REPLACE FUNCTION public.is_staff()
RETURNS boolean AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.profiles
        WHERE id = auth.uid() AND role = 'staff'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- Enable Row Level Security (RLS) on all tables
ALTER TABLE public.rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sensor_readings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bookings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.settings ENABLE ROW LEVEL SECURITY;

-- RLS Policies: Rooms
CREATE POLICY "Anyone can view rooms"
ON public.rooms FOR SELECT
TO authenticated, anon
USING (true);

CREATE POLICY "Staff can modify rooms"
ON public.rooms FOR ALL
TO authenticated
USING (public.is_staff())
WITH CHECK (public.is_staff());

-- RLS Policies: Devices
CREATE POLICY "Staff can view devices"
ON public.devices FOR SELECT
TO authenticated
USING (public.is_staff());

CREATE POLICY "Staff can modify devices"
ON public.devices FOR ALL
TO authenticated
USING (public.is_staff())
WITH CHECK (public.is_staff());

-- RLS Policies: Sensor Readings
-- Authenticated users can read readings for room status / simulated badge display
CREATE POLICY "Authenticated users can view sensor readings"
ON public.sensor_readings FOR SELECT
TO authenticated
USING (true);

-- RLS Policies: Profiles
CREATE POLICY "Users can read own profile or staff can read all"
ON public.profiles FOR SELECT
TO authenticated
USING (id = auth.uid() OR public.is_staff());

CREATE POLICY "Users can update own profile"
ON public.profiles FOR UPDATE
TO authenticated
USING (id = auth.uid())
WITH CHECK (id = auth.uid());

-- RLS Policies: Bookings
-- Students read their own bookings; staff read all bookings
CREATE POLICY "Users read own bookings or staff read all"
ON public.bookings FOR SELECT
TO authenticated
USING (user_id = auth.uid() OR public.is_staff());

-- RLS Policies: Events
CREATE POLICY "Staff can view audit events"
ON public.events FOR SELECT
TO authenticated
USING (public.is_staff());

-- RLS Policies: Notifications
CREATE POLICY "Users view own notifications"
ON public.notifications FOR SELECT
TO authenticated
USING (user_id = auth.uid());

CREATE POLICY "Users update own notifications"
ON public.notifications FOR UPDATE
TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

-- RLS Policies: Settings
CREATE POLICY "Authenticated users can view settings"
ON public.settings FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "Staff can update settings"
ON public.settings FOR UPDATE
TO authenticated
USING (public.is_staff())
WITH CHECK (public.is_staff());

-- Realtime Setup
ALTER TABLE public.rooms REPLICA IDENTITY FULL;
ALTER TABLE public.bookings REPLICA IDENTITY FULL;
ALTER TABLE public.notifications REPLICA IDENTITY FULL;
ALTER TABLE public.sensor_readings REPLICA IDENTITY FULL;
ALTER TABLE public.events REPLICA IDENTITY FULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'rooms'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.rooms;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'bookings'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.bookings;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'notifications'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'sensor_readings'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.sensor_readings;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND tablename = 'events'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.events;
    END IF;
END $$;
