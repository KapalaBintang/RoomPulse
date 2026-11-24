import React from 'react';
import { RoomDisplayStatus, BookingStatus } from '../lib/types';
import { CheckCircle2, Clock, AlertTriangle, UserCheck, XCircle } from 'lucide-react';

interface StatusBadgeProps {
  status: RoomDisplayStatus | BookingStatus | string;
  size?: 'sm' | 'md' | 'lg';
}

export const StatusBadge: React.FC<StatusBadgeProps> = ({ status, size = 'md' }) => {
  const sizeClasses = {
    sm: 'px-2 py-0.5 text-xs gap-1',
    md: 'px-2.5 py-1 text-xs gap-1.5 font-medium',
    lg: 'px-3 py-1.5 text-sm gap-2 font-semibold',
  }[size];

  switch (status) {
    case 'available':
      return (
        <span
          className={`inline-flex items-center rounded-full bg-emerald-50 text-emerald-700 border border-emerald-200 ${sizeClasses}`}
        >
          <CheckCircle2 className="w-3.5 h-3.5 text-emerald-600" />
          <span>Available</span>
        </span>
      );

    case 'reserved':
      return (
        <span
          className={`inline-flex items-center rounded-full bg-amber-50 text-amber-700 border border-amber-200 ${sizeClasses}`}
        >
          <Clock className="w-3.5 h-3.5 text-amber-600" />
          <span>Reserved</span>
        </span>
      );

    case 'confirm_pending':
      return (
        <span
          className={`inline-flex items-center rounded-full bg-orange-100 text-orange-800 border border-orange-300 animate-pulse ${sizeClasses}`}
        >
          <AlertTriangle className="w-3.5 h-3.5 text-orange-600" />
          <span>Confirmation Pending</span>
        </span>
      );

    case 'occupied':
    case 'active':
      return (
        <span
          className={`inline-flex items-center rounded-full bg-rose-50 text-rose-700 border border-rose-200 ${sizeClasses}`}
        >
          <UserCheck className="w-3.5 h-3.5 text-rose-600" />
          <span>Occupied</span>
        </span>
      );

    case 'released':
      return (
        <span
          className={`inline-flex items-center rounded-full bg-slate-100 text-slate-700 border border-slate-200 ${sizeClasses}`}
        >
          <XCircle className="w-3.5 h-3.5 text-slate-500" />
          <span>Released (No-Show)</span>
        </span>
      );

    case 'completed':
      return (
        <span
          className={`inline-flex items-center rounded-full bg-blue-50 text-blue-700 border border-blue-200 ${sizeClasses}`}
        >
          <CheckCircle2 className="w-3.5 h-3.5 text-blue-500" />
          <span>Completed</span>
        </span>
      );

    case 'cancelled':
      return (
        <span
          className={`inline-flex items-center rounded-full bg-slate-100 text-slate-600 border border-slate-200 ${sizeClasses}`}
        >
          <XCircle className="w-3.5 h-3.5 text-slate-400" />
          <span>Cancelled</span>
        </span>
      );

    default:
      return (
        <span
          className={`inline-flex items-center rounded-full bg-slate-100 text-slate-700 border border-slate-200 ${sizeClasses}`}
        >
          <span>{status}</span>
        </span>
      );
  }
};
