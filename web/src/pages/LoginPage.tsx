import React, { useState } from 'react';
import { useAuth } from '../context/AuthContext';
import { Cpu, LogIn, UserCheck, Shield } from 'lucide-react';

interface LoginPageProps {
  onSuccess: () => void;
}

export const LoginPage: React.FC<LoginPageProps> = ({ onSuccess }) => {
  const { loginWithEmail, switchUserQuick } = useAuth();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setError(null);

    const res = await loginWithEmail(email, password);
    setLoading(false);
    if (res.error) {
      setError(res.error);
    } else {
      onSuccess();
    }
  };

  const handleQuickLogin = async (targetEmail: string) => {
    setLoading(true);
    setError(null);
    try {
      await switchUserQuick(targetEmail);
      onSuccess();
    } catch (err: any) {
      setError(err.message || 'Login failed');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-[80vh] flex flex-col justify-center py-12 sm:px-6 lg:px-8">
      <div className="sm:mx-auto sm:w-full sm:max-w-md text-center">
        <div className="w-12 h-12 rounded-2xl bg-brand-600 flex items-center justify-center text-white mx-auto shadow-lg mb-3">
          <Cpu className="w-7 h-7" />
        </div>
        <h2 className="text-2xl font-bold tracking-tight text-slate-900">
          Sign in to RoomPulse
        </h2>
        <p className="mt-1 text-sm text-slate-500">
          Sensor-verified study room booking system
        </p>
      </div>

      <div className="mt-8 sm:mx-auto sm:w-full sm:max-w-md">
        <div className="bg-white py-8 px-6 shadow-sm border border-slate-200 rounded-2xl sm:px-10">
          {error && (
            <div className="mb-4 p-3 bg-red-50 border border-red-200 text-red-700 text-xs rounded-lg">
              {error}
            </div>
          )}

          <form className="space-y-4" onSubmit={handleSubmit}>
            <div>
              <label className="block text-xs font-medium text-slate-700">Email address</label>
              <input
                type="email"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                className="mt-1 block w-full px-3 py-2 text-sm border border-slate-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500"
                placeholder="alice@university.edu"
              />
            </div>

            <div>
              <label className="block text-xs font-medium text-slate-700">Password</label>
              <input
                type="password"
                required
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                className="mt-1 block w-full px-3 py-2 text-sm border border-slate-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500"
                placeholder="••••••••"
              />
            </div>

            <button
              type="submit"
              disabled={loading}
              className="w-full flex justify-center items-center py-2.5 px-4 border border-transparent rounded-lg shadow-sm text-sm font-semibold text-white bg-brand-600 hover:bg-brand-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-brand-500 transition-colors disabled:opacity-50"
            >
              <LogIn className="w-4 h-4 mr-2" />
              {loading ? 'Signing in...' : 'Sign In'}
            </button>
          </form>

          {/* Quick Demo Accounts Fill */}
          <div className="mt-6 pt-6 border-t border-slate-200">
            <span className="block text-xs font-semibold text-slate-500 uppercase tracking-wider mb-3 text-center">
              Demo Accounts (1-Click Login)
            </span>
            <div className="grid grid-cols-1 gap-2">
              <button
                type="button"
                onClick={() => handleQuickLogin('student1@roompulse.local')}
                className="w-full text-left px-3 py-2 border border-slate-200 hover:border-brand-300 hover:bg-brand-50 rounded-lg text-xs transition-colors flex items-center justify-between"
              >
                <div className="flex items-center space-x-2">
                  <UserCheck className="w-4 h-4 text-emerald-600" />
                  <div>
                    <span className="font-semibold text-slate-800">Alice Pratama</span>
                    <span className="text-slate-400 block text-[10px]">student1@roompulse.local</span>
                  </div>
                </div>
                <span className="text-[10px] font-bold uppercase text-emerald-700 bg-emerald-50 px-2 py-0.5 rounded border border-emerald-200">
                  Student
                </span>
              </button>

              <button
                type="button"
                onClick={() => handleQuickLogin('student2@roompulse.local')}
                className="w-full text-left px-3 py-2 border border-slate-200 hover:border-brand-300 hover:bg-brand-50 rounded-lg text-xs transition-colors flex items-center justify-between"
              >
                <div className="flex items-center space-x-2">
                  <UserCheck className="w-4 h-4 text-emerald-600" />
                  <div>
                    <span className="font-semibold text-slate-800">Bob Santoso</span>
                    <span className="text-slate-400 block text-[10px]">student2@roompulse.local</span>
                  </div>
                </div>
                <span className="text-[10px] font-bold uppercase text-emerald-700 bg-emerald-50 px-2 py-0.5 rounded border border-emerald-200">
                  Student
                </span>
              </button>

              <button
                type="button"
                onClick={() => handleQuickLogin('staff@roompulse.local')}
                className="w-full text-left px-3 py-2 border border-slate-200 hover:border-brand-300 hover:bg-brand-50 rounded-lg text-xs transition-colors flex items-center justify-between"
              >
                <div className="flex items-center space-x-2">
                  <Shield className="w-4 h-4 text-brand-600" />
                  <div>
                    <span className="font-semibold text-slate-800">Library Staff Lead</span>
                    <span className="text-slate-400 block text-[10px]">staff@roompulse.local</span>
                  </div>
                </div>
                <span className="text-[10px] font-bold uppercase text-brand-700 bg-brand-50 px-2 py-0.5 rounded border border-brand-200">
                  Staff
                </span>
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
