export type UserRole = 'student' | 'staff';

export interface Profile {
  id: string;
  display_name: string;
  role: UserRole;
  telegram_chat_id: string | null;
}

export type BookingStatus =
  | 'reserved'
  | 'confirm_pending'
  | 'active'
  | 'completed'
  | 'released'
  | 'cancelled'
  | 'expired';

export type RoomDisplayStatus = 'available' | 'reserved' | 'confirm_pending' | 'occupied';

export interface RoomWithStatus {
  room_id: string;
  name: string;
  capacity: number;
  device_id: string | null;
  booking_id: string | null;
  current_booker_id: string | null;
  booking_status: BookingStatus | null;
  booking_start: string | null;
  booking_end: string | null;
  confirm_deadline: string | null;
  sensor_presence: boolean | null;
  sensor_recorded_at: string | null;
  sensor_source: 'device' | 'simulator' | null;
  moving_energy: number | null;
  static_energy: number | null;
  distance_cm: number | null;
  device_last_seen_at: string | null;
  is_sensor_offline: boolean;
  display_status: RoomDisplayStatus;
  next_free_slot: string | null;
}

export interface Booking {
  id: string;
  room_id: string;
  user_id: string;
  start_time: string;
  end_time: string;
  status: BookingStatus;
  confirm_deadline: string | null;
  extension_count: number;
  no_show_check_at: string;
  created_at: string;
}

export interface NotificationItem {
  id: string;
  user_id: string;
  booking_id: string | null;
  kind: string;
  message: string;
  created_at: string;
  read_at: string | null;
}

export interface AuditEvent {
  id: string;
  at: string;
  booking_id: string | null;
  room_id: string;
  kind: string;
  reason: string;
}

export interface SystemSettings {
  id: number;
  no_show_seconds: number;
  confirm_window_seconds: number;
  offline_threshold_seconds: number;
  max_extensions: number;
  presence_window_seconds: number;
  demo_mode: boolean;
}
