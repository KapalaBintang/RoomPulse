import React from 'react';
import { Radio } from 'lucide-react';

interface SimulatedBadgeProps {
  source: 'device' | 'simulator' | null | undefined;
}

export const SimulatedBadge: React.FC<SimulatedBadgeProps> = ({ source }) => {
  if (source !== 'simulator') return null;

  return (
    <div
      className="inline-flex items-center gap-1.5 px-2 py-0.5 rounded text-[11px] font-bold bg-amber-100 text-amber-900 border border-amber-300 uppercase tracking-wider"
      title="This room's latest telemetry reading was produced by the simulated sensor tool."
    >
      <Radio className="w-3 h-3 text-amber-700 animate-pulse" />
      <span>SIMULATED SENSOR DATA</span>
    </div>
  );
};
