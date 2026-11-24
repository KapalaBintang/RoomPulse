import React, { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { RoomWithStatus } from '../lib/types';
import { StatusBadge } from '../components/StatusBadge';
import { SimulatedBadge } from '../components/SimulatedBadge';
import { Users, Clock, ArrowRight, Radio, RefreshCw, AlertCircle } from 'lucide-react';
import { formatJakartaTime } from '../lib/format';

interface RoomsPageProps {
  onSelectRoom: (roomId: string) => void;
}

export const RoomsPage: React.FC<RoomsPageProps> = ({ onSelectRoom }) => {
  const [rooms, setRooms] = useState<RoomWithStatus[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchRooms = async () => {
    try {
      const { data, error: err } = await supabase
        .from('rooms_with_status')
        .select('*')
        .order('name');

      if (err) throw err;
      setRooms((data as RoomWithStatus[]) || []);
    } catch (e: any) {
      setError(e.message || 'Failed to fetch rooms');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchRooms();

    // Supabase Realtime subscriptions for room updates
    const channel = supabase
      .channel('rooms_live_updates')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'bookings' },
        () => fetchRooms()
      )
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'sensor_readings' },
        () => fetchRooms()
      )
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'rooms' },
        () => fetchRooms()
      )
      .subscribe();

    const interval = setInterval(fetchRooms, 4000);

    return () => {
      supabase.removeChannel(channel);
      clearInterval(interval);
    };
  }, []);

  if (loading) {
    return (
      <div className="py-20 text-center">
        <RefreshCw className="w-8 h-8 text-brand-600 animate-spin mx-auto mb-3" />
        <p className="text-sm text-slate-500">Loading campus rooms & sensor status...</p>
      </div>
    );
  }

  if (error) {
    return (
      <div className="py-12 max-w-lg mx-auto">
        <div className="p-4 bg-red-50 border border-red-200 rounded-xl flex items-center space-x-3 text-red-700">
          <AlertCircle className="w-5 h-5 flex-shrink-0" />
          <p className="text-sm">{error}</p>
        </div>
      </div>
    );
  }

  return (
    <div className="py-8 max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
      {/* Hero Header */}
      <div className="mb-8 flex flex-col md:flex-row md:items-center md:justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-slate-900">
            Study Rooms & Focus Pods
          </h1>
          <p className="text-sm text-slate-500 mt-1">
            Real-time mmWave radar verification preventing ghost bookings.
          </p>
        </div>
        <button
          onClick={fetchRooms}
          className="self-start md:self-auto inline-flex items-center space-x-1.5 px-3 py-1.5 text-xs font-medium text-slate-600 bg-white border border-slate-200 rounded-lg hover:bg-slate-50 shadow-sm"
        >
          <RefreshCw className="w-3.5 h-3.5" />
          <span>Refresh Status</span>
        </button>
      </div>

      {/* Room Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        {rooms.map((room) => {
          const isFree = room.display_status === 'available';

          return (
            <div
              key={room.room_id}
              className="bg-white rounded-2xl border border-slate-200 shadow-sm hover:shadow-md transition-shadow overflow-hidden flex flex-col"
            >
              {/* Card Header */}
              <div className="p-5 border-b border-slate-100 flex items-start justify-between">
                <div>
                  <h3 className="font-bold text-slate-900 text-lg leading-tight">{room.name}</h3>
                  <div className="flex items-center text-xs text-slate-500 mt-1 space-x-3">
                    <span className="flex items-center">
                      <Users className="w-3.5 h-3.5 mr-1 text-slate-400" />
                      Up to {room.capacity} people
                    </span>
                    <span className="flex items-center">
                      <Radio className="w-3.5 h-3.5 mr-1 text-slate-400" />
                      {room.is_sensor_offline ? (
                        <span className="text-amber-600 font-medium">Sensor Offline</span>
                      ) : (
                        <span className="text-emerald-600 font-medium">Sensor Online</span>
                      )}
                    </span>
                  </div>
                </div>

                {/* Door LED Color Indicator */}
                <div className="flex flex-col items-end">
                  <div className="flex items-center space-x-1.5 px-2 py-1 rounded-full bg-slate-100 border border-slate-200">
                    <span
                      className={`w-2.5 h-2.5 rounded-full ${
                        room.is_sensor_offline
                          ? 'bg-amber-400 animate-pulse'
                          : room.display_status === 'occupied'
                          ? 'bg-red-500'
                          : room.display_status === 'reserved' || room.display_status === 'confirm_pending'
                          ? 'bg-amber-400'
                          : 'bg-emerald-500'
                      }`}
                    />
                    <span className="text-[10px] font-bold text-slate-600 uppercase">
                      LED
                    </span>
                  </div>
                </div>
              </div>

              {/* Status & Telemetry Details */}
              <div className="p-5 flex-1 flex flex-col justify-between space-y-4">
                <div className="space-y-3">
                  <div className="flex items-center justify-between">
                    <span className="text-xs text-slate-500">Live Status</span>
                    <StatusBadge status={room.display_status} />
                  </div>

                  {/* Honesty Disclosure: Simulated Sensor Data Badge */}
                  <SimulatedBadge source={room.sensor_source} />

                  {/* Sensor reading details */}
                  <div className="bg-slate-50 p-3 rounded-xl border border-slate-100 text-xs text-slate-600 space-y-1">
                    <div className="flex justify-between">
                      <span className="text-slate-400">Radar Presence:</span>
                      <span className="font-semibold">
                        {room.sensor_presence ? 'Occupant Detected' : 'Empty'}
                      </span>
                    </div>
                    {room.sensor_presence && (
                      <div className="flex justify-between text-[11px] text-slate-500">
                        <span>Energy (Moving / Static):</span>
                        <span>{room.moving_energy ?? 0} / {room.static_energy ?? 0}</span>
                      </div>
                    )}
                    <div className="flex justify-between text-[11px]">
                      <span className="text-slate-400">Next Free Slot:</span>
                      <span className="font-medium text-slate-700">
                        {isFree ? 'Now' : formatJakartaTime(room.next_free_slot)}
                      </span>
                    </div>
                  </div>
                </div>

                {/* Action Button */}
                <button
                  onClick={() => onSelectRoom(room.room_id)}
                  className={`w-full py-2.5 px-4 rounded-xl text-sm font-semibold transition-colors flex items-center justify-center space-x-2 ${
                    isFree
                      ? 'bg-brand-600 hover:bg-brand-700 text-white shadow-sm'
                      : 'bg-slate-100 hover:bg-slate-200 text-slate-700'
                  }`}
                >
                  <span>{isFree ? 'Book This Room' : 'View Schedule & Book'}</span>
                  <ArrowRight className="w-4 h-4" />
                </button>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
};
