import React, { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { Booking, RoomWithStatus } from '../lib/types';
import { StatusBadge } from '../components/StatusBadge';
import { Clock, AlertTriangle, Check, X, Calendar, RefreshCw, AlertCircle } from 'lucide-react';
import { formatJakartaDateTime, getSecondsRemaining } from '../lib/format';

export const MyBookingsPage: React.FC = () => {
  const { user } = useAuth();
  const [bookings, setBookings] = useState<Booking[]>([]);
  const [roomsMap, setRoomsMap] = useState<Record<string, RoomWithStatus>>({});
  const [loading, setLoading] = useState(true);
  const [actionLoading, setActionLoading] = useState(false);
  const [actionError, setActionError] = useState<string | null>(null);

  const fetchBookings = async () => {
    if (!user) return;
    try {
      const { data: bData } = await supabase
        .from('bookings')
        .select('*')
        .eq('user_id', user.id)
        .order('created_at', { ascending: false });

      setBookings((bData as Booking[]) || []);

      const { data: rData } = await supabase.from('rooms_with_status').select('*');
      if (rData) {
        const map: Record<string, RoomWithStatus> = {};
        rData.forEach((r: RoomWithStatus) => {
          map[r.room_id] = r;
        });
        setRoomsMap(map);
      }
    } catch (_e) {
      // ignore
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchBookings();

    const channel = supabase
      .channel('my_bookings_realtime')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'bookings', filter: `user_id=eq.${user?.id}` },
        () => fetchBookings()
      )
      .subscribe();

    const timer = setInterval(() => {
      // re-render for countdown timers
      setBookings((prev) => [...prev]);
    }, 1000);

    return () => {
      supabase.removeChannel(channel);
      clearInterval(timer);
    };
  }, [user]);

  const handleRespond = async (bookingId: string, action: string) => {
    setActionLoading(true);
    setActionError(null);
    try {
      const { error } = await supabase.rpc('respond_booking', {
        p_booking_id: bookingId,
        p_action: action,
      });
      if (error) throw error;
      await fetchBookings();
    } catch (err: any) {
      setActionError(err.message || 'Action failed');
    } finally {
      setActionLoading(false);
    }
  };

  const handleCancel = async (bookingId: string) => {
    if (!confirm('Are you sure you want to cancel this booking?')) return;
    setActionLoading(true);
    setActionError(null);
    try {
      const { error } = await supabase.rpc('cancel_booking', {
        p_booking_id: bookingId,
      });
      if (error) throw error;
      await fetchBookings();
    } catch (err: any) {
      setActionError(err.message || 'Cancellation failed');
    } finally {
      setActionLoading(false);
    }
  };

  if (loading) {
    return <div className="py-20 text-center text-slate-500">Loading your bookings...</div>;
  }

  // Active / Confirm Pending booking
  const pendingBooking = bookings.find((b) => b.status === 'confirm_pending');

  return (
    <div className="py-8 max-w-4xl mx-auto px-4 sm:px-6">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-slate-900">My Study Bookings</h1>
          <p className="text-xs text-slate-500 mt-1">Review reservations and respond to check-in prompts.</p>
        </div>
        <button
          onClick={fetchBookings}
          className="p-2 text-slate-600 hover:bg-slate-100 rounded-lg border border-slate-200"
          title="Refresh"
        >
          <RefreshCw className="w-4 h-4" />
        </button>
      </div>

      {actionError && (
        <div className="mb-6 p-4 bg-red-50 border border-red-200 rounded-xl text-xs text-red-700 flex items-center space-x-2">
          <AlertCircle className="w-4 h-4 flex-shrink-0" />
          <span>{actionError}</span>
        </div>
      )}

      {/* Prominent Banner for Confirm Pending Booking */}
      {pendingBooking && (
        <div className="mb-8 p-6 bg-gradient-to-r from-orange-500 to-amber-500 text-white rounded-2xl shadow-lg animate-pulse border-2 border-orange-400">
          <div className="flex flex-col md:flex-row md:items-center md:justify-between gap-4">
            <div>
              <div className="inline-flex items-center space-x-1.5 px-2.5 py-1 rounded-full bg-white/20 text-xs font-bold uppercase tracking-wider mb-2">
                <AlertTriangle className="w-4 h-4" />
                <span>Attendance Confirmation Required</span>
              </div>
              <h2 className="text-xl font-bold">
                Are you at {roomsMap[pendingBooking.room_id]?.name || 'the Room'}?
              </h2>
              <p className="text-xs text-orange-100 mt-1">
                The mmWave sensor hasn't detected anyone yet. Please confirm your arrival or request an extension.
              </p>
              <div className="mt-3 flex items-center space-x-2 text-sm font-semibold bg-black/20 px-3 py-1.5 rounded-lg w-fit">
                <Clock className="w-4 h-4" />
                <span>
                  Releasing in: {getSecondsRemaining(pendingBooking.confirm_deadline)} seconds
                </span>
              </div>
            </div>

            {/* Action Buttons */}
            <div className="flex flex-wrap gap-2">
              <button
                disabled={actionLoading}
                onClick={() => handleRespond(pendingBooking.id, 'coming')}
                className="px-3.5 py-2 bg-white text-orange-700 hover:bg-orange-50 rounded-xl text-xs font-bold shadow transition-colors flex items-center space-x-1.5 disabled:opacity-50"
              >
                <Check className="w-4 h-4" />
                <span>I'm Coming (10m)</span>
              </button>
              <button
                disabled={actionLoading || pendingBooking.extension_count >= 1}
                onClick={() => handleRespond(pendingBooking.id, 'late_10')}
                className="px-3 py-2 bg-orange-600/80 hover:bg-orange-600 text-white border border-white/30 rounded-xl text-xs font-semibold transition-colors disabled:opacity-40"
              >
                Late 10 min
              </button>
              <button
                disabled={actionLoading || pendingBooking.extension_count >= 1}
                onClick={() => handleRespond(pendingBooking.id, 'late_20')}
                className="px-3 py-2 bg-orange-600/80 hover:bg-orange-600 text-white border border-white/30 rounded-xl text-xs font-semibold transition-colors disabled:opacity-40"
              >
                Late 20 min
              </button>
              <button
                disabled={actionLoading}
                onClick={() => handleRespond(pendingBooking.id, 'cancel')}
                className="px-3 py-2 bg-black/30 hover:bg-black/50 text-white rounded-xl text-xs font-semibold transition-colors"
              >
                <X className="w-4 h-4 inline mr-1" />
                Cancel
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Bookings List */}
      {bookings.length === 0 ? (
        <div className="py-16 text-center bg-white rounded-2xl border border-slate-200 p-8">
          <Calendar className="w-10 h-10 text-slate-300 mx-auto mb-3" />
          <h3 className="text-base font-semibold text-slate-700">No bookings yet</h3>
          <p className="text-xs text-slate-400 mt-1">Reserve a quiet focus pod or group study room.</p>
        </div>
      ) : (
        <div className="space-y-4">
          {bookings.map((b) => {
            const roomName = roomsMap[b.room_id]?.name || 'Study Room';
            const isActive = b.status === 'reserved' || b.status === 'confirm_pending' || b.status === 'active';

            return (
              <div
                key={b.id}
                className="bg-white p-5 rounded-2xl border border-slate-200 shadow-sm flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4"
              >
                <div className="space-y-1">
                  <div className="flex items-center space-x-3">
                    <h3 className="font-bold text-slate-900 text-base">{roomName}</h3>
                    <StatusBadge status={b.status} />
                  </div>
                  <div className="text-xs text-slate-500">
                    <span>
                      {formatJakartaDateTime(b.start_time)} — {formatJakartaDateTime(b.end_time)}
                    </span>
                  </div>
                  {b.extension_count > 0 && (
                    <div className="text-[11px] text-amber-700 font-medium">
                      Extended {b.extension_count} time(s)
                    </div>
                  )}
                </div>

                <div className="flex items-center space-x-2">
                  {isActive && (
                    <button
                      onClick={() => handleCancel(b.id)}
                      disabled={actionLoading}
                      className="px-3 py-1.5 text-xs font-semibold text-red-600 hover:bg-red-50 rounded-lg border border-red-200 transition-colors"
                    >
                      Cancel Booking
                    </button>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
};
