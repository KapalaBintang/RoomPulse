import React, { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { AuditEvent, SystemSettings } from '../lib/types';
import { Shield, Settings, Sliders, Check, RefreshCw, BarChart3, Radio } from 'lucide-react';
import { formatJakartaTime, formatJakartaDate } from '../lib/format';

export const AdminPage: React.FC = () => {
  const [summary, setSummary] = useState<any>(null);
  const [events, setEvents] = useState<AuditEvent[]>([]);
  const [settings, setSettings] = useState<SystemSettings | null>(null);
  const [loading, setLoading] = useState(true);
  const [savingPreset, setSavingPreset] = useState(false);

  // Sensor Test Logger states (P1 requirement)
  const [testScenario, setTestScenario] = useState('seated_reading');
  const [testLoggingActive, setTestLoggingActive] = useState(false);
  const [testLogs, setTestLogs] = useState<any[]>([]);

  const fetchAdminData = async () => {
    try {
      const { data: sumData } = await supabase.from('admin_summary').select('*').single();
      setSummary(sumData);

      const { data: evData } = await supabase
        .from('events')
        .select('*')
        .order('at', { ascending: false })
        .limit(25);
      setEvents((evData as AuditEvent[]) || []);

      const { data: setts } = await supabase.from('settings').select('*').eq('id', 1).single();
      setSettings(setts as SystemSettings);
    } catch (_e) {
      // ignore
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchAdminData();
    const interval = setInterval(fetchAdminData, 5000);
    return () => clearInterval(interval);
  }, []);

  const handleToggleDemoPreset = async (demo: boolean) => {
    setSavingPreset(true);
    try {
      const { error } = await supabase.rpc('set_demo_preset', { p_demo_mode: demo });
      if (error) throw error;
      await fetchAdminData();
    } catch (e: any) {
      alert(e.message || 'Failed to update preset');
    } finally {
      setSavingPreset(false);
    }
  };

  if (loading) {
    return <div className="py-20 text-center text-slate-500">Loading admin analytics...</div>;
  }

  return (
    <div className="py-8 max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 space-y-8">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold tracking-tight text-slate-900 flex items-center">
          <Shield className="w-6 h-6 mr-2 text-brand-600" />
          Staff Control & Analytics
        </h1>
        <p className="text-xs text-slate-500 mt-1">
          Monitor no-show auto-releases, adjust timer presets, and view audit events.
        </p>
      </div>

      {/* Analytics Summary Cards */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <div className="bg-white p-5 rounded-2xl border border-slate-200 shadow-sm">
          <span className="text-xs text-slate-500">Total Bookings</span>
          <div className="text-2xl font-bold text-slate-900 mt-1">{summary?.total_bookings ?? 0}</div>
        </div>

        <div className="bg-white p-5 rounded-2xl border border-slate-200 shadow-sm">
          <span className="text-xs text-slate-500">Auto-Released (No-Shows)</span>
          <div className="text-2xl font-bold text-orange-600 mt-1">{summary?.released_count ?? 0}</div>
        </div>

        <div className="bg-white p-5 rounded-2xl border border-slate-200 shadow-sm">
          <span className="text-xs text-slate-500">No-Show Rate</span>
          <div className="text-2xl font-bold text-slate-900 mt-1">{summary?.no_show_rate_percent ?? 0}%</div>
        </div>

        <div className="bg-white p-5 rounded-2xl border border-slate-200 shadow-sm">
          <span className="text-xs text-slate-500">Audit Events</span>
          <div className="text-2xl font-bold text-slate-900 mt-1">{summary?.total_audit_events ?? 0}</div>
        </div>
      </div>

      {/* Preset Switcher Card */}
      <div className="bg-white p-6 rounded-2xl border border-slate-200 shadow-sm">
        <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
          <div>
            <h2 className="text-sm font-bold text-slate-900 flex items-center">
              <Sliders className="w-4 h-4 mr-2 text-brand-600" />
              Timer Preset Mode
            </h2>
            <p className="text-xs text-slate-500 mt-1">
              Switch between production timers (600s/300s) and fast hackathon evaluation demo timers (60s/30s).
            </p>
          </div>

          <div className="flex items-center space-x-2">
            <button
              disabled={savingPreset}
              onClick={() => handleToggleDemoPreset(false)}
              className={`px-3.5 py-2 rounded-xl text-xs font-semibold transition-all ${
                !settings?.demo_mode
                  ? 'bg-slate-900 text-white shadow'
                  : 'bg-slate-100 hover:bg-slate-200 text-slate-700'
              }`}
            >
              Normal (600s / 300s)
            </button>
            <button
              disabled={savingPreset}
              onClick={() => handleToggleDemoPreset(true)}
              className={`px-3.5 py-2 rounded-xl text-xs font-semibold transition-all ${
                settings?.demo_mode
                  ? 'bg-amber-600 text-white shadow'
                  : 'bg-amber-50 hover:bg-amber-100 text-amber-800 border border-amber-200'
              }`}
            >
              Demo (60s / 30s)
            </button>
          </div>
        </div>
      </div>

      {/* Sensor Test Logger (P1) */}
      <div className="bg-white p-6 rounded-2xl border border-slate-200 shadow-sm space-y-4">
        <div>
          <h2 className="text-sm font-bold text-slate-900 flex items-center">
            <Radio className="w-4 h-4 mr-2 text-brand-600" />
            Sensor Accuracy Test Logger (P1)
          </h2>
          <p className="text-xs text-slate-500 mt-1">
            Tag mmWave readings with ground-truth test scenarios (e.g. seated reading vs empty room).
          </p>
        </div>

        <div className="flex items-center space-x-3">
          <select
            value={testScenario}
            onChange={(e) => setTestScenario(e.target.value)}
            className="px-3 py-2 text-xs border border-slate-300 rounded-lg bg-white"
          >
            <option value="seated_reading">Seated Reading (Ground Truth: Present)</option>
            <option value="empty_room">Empty Room (Ground Truth: Empty)</option>
            <option value="typing_motion">Typing on Laptop (Ground Truth: Present)</option>
          </select>

          <button
            onClick={() => setTestLoggingActive(!testLoggingActive)}
            className={`px-4 py-2 rounded-xl text-xs font-bold transition-colors ${
              testLoggingActive
                ? 'bg-rose-600 hover:bg-rose-700 text-white'
                : 'bg-brand-600 hover:bg-brand-700 text-white shadow'
            }`}
          >
            {testLoggingActive ? 'Stop Scenario' : 'Start Scenario'}
          </button>
        </div>
      </div>

      {/* Audit Log Table */}
      <div className="bg-white rounded-2xl border border-slate-200 shadow-sm overflow-hidden">
        <div className="p-5 border-b border-slate-100 flex items-center justify-between">
          <h2 className="text-sm font-bold text-slate-900">System Audit Events Log</h2>
          <span className="text-xs text-slate-400">Latest 25 events</span>
        </div>

        <div className="overflow-x-auto">
          <table className="w-full text-left text-xs">
            <thead className="bg-slate-50 text-slate-500 border-b border-slate-100 font-semibold uppercase tracking-wider text-[10px]">
              <tr>
                <th className="p-3.5">Time (WIB)</th>
                <th className="p-3.5">Event Kind</th>
                <th className="p-3.5">Reason & Details</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {events.map((ev) => (
                <tr key={ev.id} className="hover:bg-slate-50/50">
                  <td className="p-3.5 text-slate-500 font-mono text-[11px] whitespace-nowrap">
                    {formatJakartaTime(ev.at)}
                  </td>
                  <td className="p-3.5 font-semibold text-slate-800 whitespace-nowrap">
                    <span className="px-2 py-0.5 rounded bg-slate-100 text-slate-700 font-mono text-[10px]">
                      {ev.kind}
                    </span>
                  </td>
                  <td className="p-3.5 text-slate-600 max-w-md">{ev.reason}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
};
