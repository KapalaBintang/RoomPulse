import React, { useState } from 'react';
import { supabase } from '../lib/supabase';
import { Radio, Play, StopCircle, RefreshCw, AlertTriangle, ShieldCheck } from 'lucide-react';

const EDGE_FUNCTIONS_URL = `${import.meta.env.VITE_SUPABASE_URL || 'http://127.0.0.1:54321'}/functions/v1`;

export const DevSimulatorPage: React.FC = () => {
  const [deviceId, setDeviceId] = useState('device-room-101');
  const [presence, setPresence] = useState(false);
  const [moving, setMoving] = useState(false);
  const [staticEnergy, setStaticEnergy] = useState(80);
  const [logs, setLogs] = useState<string[]>([]);
  const [sending, setSending] = useState(false);

  const addLog = (msg: string) => {
    const time = new Date().toLocaleTimeString('en-US', { hour12: false });
    setLogs((prev) => [`[${time}] ${msg}`, ...prev.slice(0, 30)]);
  };

  const sendSimulatedReading = async (isPresence: boolean) => {
    setSending(true);
    try {
      const res = await fetch(`${EDGE_FUNCTIONS_URL}/device-telemetry`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-device-key': 'sim_key_default_dev',
        },
        body: JSON.stringify({
          device_id: deviceId,
          presence: isPresence,
          moving: isPresence ? moving : false,
          stationary: isPresence,
          moving_energy: isPresence ? 35 : 0,
          static_energy: isPresence ? staticEnergy : 0,
          distance_cm: isPresence ? 130 : 0,
          source: 'simulator',
          label: isPresence ? 'dev_manual_presence' : 'dev_manual_empty',
        }),
      });

      const data = await res.json();
      if (res.ok) {
        setPresence(isPresence);
        addLog(`Sent [${isPresence ? 'PRESENCE ON' : 'PRESENCE OFF'}] -> HTTP 200 (source: simulator)`);
      } else {
        addLog(`Error: ${data.error || 'Failed to send reading'}`);
      }
    } catch (e: any) {
      addLog(`Fetch error: ${e.message}`);
    } finally {
      setSending(false);
    }
  };

  const triggerRuleEngine = async () => {
    addLog('Executing rule engine run_rules()...');
    const { data, error } = await supabase.rpc('run_rules');
    if (error) {
      addLog(`Rule engine error: ${error.message}`);
    } else {
      addLog(`Rule engine executed: ${JSON.stringify(data)}`);
    }
  };

  return (
    <div className="py-8 max-w-4xl mx-auto px-4 sm:px-6">
      {/* Dev Disclaimer */}
      <div className="p-4 bg-purple-100 border border-purple-300 rounded-2xl mb-6 flex items-start space-x-3 text-purple-900">
        <Radio className="w-5 h-5 flex-shrink-0 mt-0.5 text-purple-700" />
        <div>
          <h2 className="text-sm font-bold uppercase tracking-wider">DEV ONLY: In-Browser Sensor Simulator</h2>
          <p className="text-xs text-purple-800 mt-1">
            Provides simulated mmWave radar readings for no-hardware demonstration. Telemetry is saved with
            source <code className="font-mono bg-purple-200 px-1 rounded">simulator</code> and flagged visibly across the UI.
          </p>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        {/* Controls Card */}
        <div className="bg-white p-6 rounded-2xl border border-slate-200 shadow-sm space-y-5">
          <h3 className="text-sm font-bold text-slate-900">Device Configuration</h3>

          <div>
            <label className="block text-xs font-semibold text-slate-700 mb-1">Target Device</label>
            <select
              value={deviceId}
              onChange={(e) => setDeviceId(e.target.value)}
              className="w-full px-3 py-2 text-xs border border-slate-300 rounded-lg bg-white focus:outline-none"
            >
              <option value="device-room-101">device-room-101 (Room 101 Focus Pod)</option>
              <option value="device-room-102">device-room-102 (Room 102 Collab Studio)</option>
            </select>
          </div>

          <div className="pt-2 border-t border-slate-100 space-y-3">
            <span className="text-xs font-semibold text-slate-700 block">Simulate Presence State</span>
            <div className="grid grid-cols-2 gap-3">
              <button
                disabled={sending}
                onClick={() => sendSimulatedReading(true)}
                className={`py-3 px-4 rounded-xl text-xs font-bold transition-all flex items-center justify-center space-x-2 ${
                  presence
                    ? 'bg-emerald-600 text-white shadow-md'
                    : 'bg-emerald-50 text-emerald-700 border border-emerald-300 hover:bg-emerald-100'
                }`}
              >
                <Play className="w-4 h-4" />
                <span>Set Presence ON</span>
              </button>

              <button
                disabled={sending}
                onClick={() => sendSimulatedReading(false)}
                className={`py-3 px-4 rounded-xl text-xs font-bold transition-all flex items-center justify-center space-x-2 ${
                  !presence
                    ? 'bg-rose-600 text-white shadow-md'
                    : 'bg-rose-50 text-rose-700 border border-rose-300 hover:bg-rose-100'
                }`}
              >
                <StopCircle className="w-4 h-4" />
                <span>Set Presence OFF</span>
              </button>
            </div>
          </div>

          <div className="pt-2 border-t border-slate-100">
            <button
              onClick={triggerRuleEngine}
              className="w-full py-2.5 px-4 bg-slate-900 hover:bg-black text-white text-xs font-semibold rounded-xl transition-colors flex items-center justify-center space-x-2 shadow-sm"
            >
              <RefreshCw className="w-3.5 h-3.5" />
              <span>Trigger Rule Engine (run_rules)</span>
            </button>
          </div>
        </div>

        {/* Live Simulator Log */}
        <div className="bg-slate-900 text-slate-200 p-6 rounded-2xl shadow-sm flex flex-col">
          <div className="flex items-center justify-between pb-3 border-b border-slate-800 mb-3">
            <span className="text-xs font-bold text-slate-400 uppercase tracking-wider">Simulator Event Stream</span>
            <span className="text-[10px] text-slate-500">{logs.length} events logged</span>
          </div>
          <div className="flex-1 font-mono text-[11px] space-y-1.5 overflow-y-auto max-h-64">
            {logs.length === 0 ? (
              <span className="text-slate-600">Click a button to send simulated telemetry readings...</span>
            ) : (
              logs.map((log, i) => <div key={i}>{log}</div>)
            )}
          </div>
        </div>
      </div>
    </div>
  );
};
