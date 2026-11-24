import React, { useState, useEffect } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { RoomWithStatus, Booking } from '../lib/types';
import { StatusBadge } from '../components/StatusBadge';
import { SimulatedBadge } from '../components/SimulatedBadge';
import { ArrowLeft, Calendar, Clock, AlertCircle, CheckCircle, Users } from 'lucide-react';
import { formatJakartaTime, formatJakartaDate } from '../lib/format';

interface RoomDetailPageProps {
  roomId: string;
  onBack: () => void;
  onBookingSuccess: () => void;
}

export const RoomDetailPage: React.FC<RoomDetailPageProps> = ({ roomId, onBack, onBookingSuccess }) => {
  const { user } = useAuth();
  const [room, setRoom] = useState<RoomWithStatus | null>(null);
  const [dayBookings, setDayBookings] = useState<Booking[]>([]);
  const [loading, setLoading] = useState(true);

  // Form states
  const [startTimeLocal, setStartTimeLocal] = useState('');
  const [durationMinutes, setDurationMinutes] = useState(60);
  const [submitting, setSubmitting] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);
  const [formSuccess, setFormSuccess] = useState<string | null>(null);

  const fetchRoomData = async () => {
    try {
      const { data: roomData } = await supabase
        .from('rooms_with_status')
        .select('*')
        .eq('room_id', roomId)
        .single();
      setRoom(roomData as RoomWithStatus);

      // Fetch bookings for today
      const todayStart = new Date();
      todayStart.setHours(0, 0, 0, 0);
      const todayEnd = new Date();
      todayEnd.setHours(23, 59, 59, 999);

      const { data: bData } = await supabase
        .from('bookings')
        .select('*')
        .eq('room_id', roomId)
        .gte('start_time', todayStart.toISOString())
        .lte('start_time', todayEnd.toISOString())
        .order('start_time', { ascending: true });

      setDayBookings((bData as Booking[]) || []);
    } catch (e: any) {
      setFormError(e.message || 'Error fetching room data');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchRoomData();

    // Default start time: rounded to next 5 minutes
    const now = new Date();
    const rounded = new Date(Math.ceil(now.getTime() / (5 * 60 * 1000)) * (5 * 60 * 1000));
    // Format YYYY-MM-DDTHH:mm for datetime-local
    const offsetMs = rounded.getTimezoneOffset() * 60 * 1000;
    const localIso = new Date(rounded.getTime() - offsetMs).toISOString().slice(0, 16);
    setStartTimeLocal(localIso);

    const channel = supabase
      .channel(`room_detail_${roomId}`)
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'bookings', filter: `room_id=eq.${roomId}` },
        () => fetchRoomData()
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [roomId]);

  const handleCreateBooking = async (e: React.FormEvent) => {
    e.preventDefault();

    let currentUser = user;
    if (!currentUser) {
      const { data: userData } = await supabase.auth.getUser();
      currentUser = userData.user;
    }

    if (!currentUser) {
      setFormError('Please sign in to reserve this room.');
      return;
    }

    setSubmitting(true);
    setFormError(null);
    setFormSuccess(null);

    try {
      const selectedDate = new Date(startTimeLocal);
      const now = new Date();
      if (selectedDate.getTime() < now.getTime() - 5 * 60 * 1000) {
        throw new Error('You cannot book a room in the past. Please select an upcoming time.');
      }
      if (durationMinutes <= 0 || durationMinutes > 120) {
        throw new Error('Duration must be between 1 and 120 minutes.');
      }

      const { error: rpcErr } = await supabase.rpc('create_booking', {
        p_room_id: roomId,
        p_start_time: selectedDate.toISOString(),
        p_duration_minutes: durationMinutes,
      });

      if (rpcErr) throw rpcErr;

      setFormSuccess('Room successfully booked! Please ensure you check in on time.');
      setTimeout(() => {
        onBookingSuccess();
      }, 1200);
    } catch (err: any) {
      setFormError(err.message || 'Booking creation failed');
    } finally {
      setSubmitting(false);
    }
  };

  if (loading || !room) {
    return <div className="py-20 text-center text-slate-500">Loading room details...</div>;
  }

  return (
    <div className="py-8 max-w-4xl mx-auto px-4 sm:px-6">
      <button
        onClick={onBack}
        className="inline-flex items-center text-xs font-semibold text-slate-600 hover:text-slate-900 mb-6 group"
      >
        <ArrowLeft className="w-4 h-4 mr-1 group-hover:-translate-x-0.5 transition-transform" />
        Back to Rooms
      </button>

      <div className="bg-white rounded-2xl border border-slate-200 shadow-sm overflow-hidden mb-8">
        <div className="p-6 border-b border-slate-100 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
          <div>
            <div className="flex items-center space-x-3">
              <h1 className="text-2xl font-bold text-slate-900">{room.name}</h1>
              <StatusBadge status={room.display_status} />
            </div>
            <div className="flex items-center space-x-4 text-xs text-slate-500 mt-2">
              <span className="flex items-center">
                <Users className="w-4 h-4 mr-1 text-slate-400" />
                Capacity: {room.capacity} students
              </span>
              <span>•</span>
              <SimulatedBadge source={room.sensor_source} />
            </div>
          </div>
        </div>

        {/* Day Schedule Timeline */}
        <div className="p-6 border-b border-slate-100">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-sm font-bold text-slate-900 flex items-center">
              <Calendar className="w-4 h-4 mr-2 text-brand-600" />
              Today's Schedule ({formatJakartaDate(new Date().toISOString())})
            </h2>
            <span className="text-xs text-slate-400">Asia/Jakarta (WIB)</span>
          </div>

          {dayBookings.length === 0 ? (
            <div className="p-4 bg-slate-50 border border-slate-200 rounded-xl text-center text-xs text-slate-500">
              No reservations scheduled for today yet.
            </div>
          ) : (
            <div className="space-y-2">
              {dayBookings.map((b) => (
                <div
                  key={b.id}
                  className="flex items-center justify-between p-3 bg-slate-50 rounded-xl border border-slate-200 text-xs"
                >
                  <div className="flex items-center space-x-3">
                    <Clock className="w-4 h-4 text-slate-400" />
                    <div>
                      <span className="font-semibold text-slate-800">
                        {formatJakartaTime(b.start_time)} - {formatJakartaTime(b.end_time)}
                      </span>
                      {b.user_id === user?.id && (
                        <span className="ml-2 text-[10px] font-bold text-brand-600 bg-brand-50 px-2 py-0.5 rounded border border-brand-200">
                          My Booking
                        </span>
                      )}
                    </div>
                  </div>
                  <StatusBadge status={b.status} size="sm" />
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Booking Form */}
        <div className="p-6 bg-slate-50/50">
          <h2 className="text-sm font-bold text-slate-900 mb-3">Reserve a Study Slot</h2>

          {formError && (
            <div className="mb-4 p-3 bg-red-50 border border-red-200 rounded-xl text-xs text-red-700 flex items-start space-x-2">
              <AlertCircle className="w-4 h-4 flex-shrink-0 mt-0.5" />
              <span>{formError}</span>
            </div>
          )}

          {formSuccess && (
            <div className="mb-4 p-3 bg-emerald-50 border border-emerald-200 rounded-xl text-xs text-emerald-700 flex items-center space-x-2">
              <CheckCircle className="w-4 h-4 flex-shrink-0" />
              <span>{formSuccess}</span>
            </div>
          )}

          <form onSubmit={handleCreateBooking} className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div>
              <label className="block text-xs font-semibold text-slate-700 mb-1">
                Start Time (Asia/Jakarta)
              </label>
              <input
                type="datetime-local"
                required
                value={startTimeLocal}
                onChange={(e) => setStartTimeLocal(e.target.value)}
                className="w-full px-3 py-2 text-xs border border-slate-300 rounded-lg bg-white focus:outline-none focus:ring-2 focus:ring-brand-500"
              />
            </div>

            <div>
              <label className="block text-xs font-semibold text-slate-700 mb-1">
                Duration (Max 120 mins)
              </label>
              <select
                value={durationMinutes}
                onChange={(e) => setDurationMinutes(Number(e.target.value))}
                className="w-full px-3 py-2 text-xs border border-slate-300 rounded-lg bg-white focus:outline-none focus:ring-2 focus:ring-brand-500"
              >
                <option value={15}>15 minutes</option>
                <option value={30}>30 minutes</option>
                <option value={45}>45 minutes</option>
                <option value={60}>1 hour (60 mins)</option>
                <option value={90}>1.5 hours (90 mins)</option>
                <option value={120}>2 hours (120 mins - Max)</option>
              </select>
            </div>

            <div className="sm:col-span-2 pt-2">
              <button
                type="submit"
                disabled={submitting}
                className="w-full py-2.5 px-4 bg-brand-600 hover:bg-brand-700 text-white rounded-xl text-sm font-semibold shadow-sm transition-colors disabled:opacity-50"
              >
                {submitting ? 'Confirming Reservation...' : 'Confirm Room Booking'}
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
  );
};
