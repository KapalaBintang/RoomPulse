import React, { useState } from 'react';
import { useAuth } from '../context/AuthContext';
import { Cpu, LogIn, UserPlus } from 'lucide-react';

interface LoginPageProps {
  onSuccess: () => void;
}

export const LoginPage: React.FC<LoginPageProps> = ({ onSuccess }) => {
  const { loginWithEmail, signUpWithEmail } = useAuth();
  const [isSignUp, setIsSignUp] = useState(false);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [displayName, setDisplayName] = useState('');
  const [role, setRole] = useState<'student' | 'staff'>('student');
  const [error, setError] = useState<string | null>(null);
  const [successMsg, setSuccessMsg] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setError(null);
    setSuccessMsg(null);

    if (isSignUp) {
      if (!displayName.trim()) {
        setError('Please enter your full name.');
        setLoading(false);
        return;
      }
      const res = await signUpWithEmail(email, password, displayName, role);
      setLoading(false);
      if (res.error) {
        setError(res.error);
      } else {
        setSuccessMsg('Account created successfully!');
        setTimeout(() => {
          onSuccess();
        }, 800);
      }
    } else {
      const res = await loginWithEmail(email, password);
      setLoading(false);
      if (res.error) {
        setError(res.error);
      } else {
        onSuccess();
      }
    }
  };

  return (
    <div className="min-h-[80vh] flex flex-col justify-center py-12 sm:px-6 lg:px-8">
      <div className="sm:mx-auto sm:w-full sm:max-w-md text-center">
        <div className="w-12 h-12 rounded-2xl bg-brand-600 flex items-center justify-center text-white mx-auto shadow-lg mb-3">
          <Cpu className="w-7 h-7" />
        </div>
        <h2 className="text-2xl font-bold tracking-tight text-slate-900">
          {isSignUp ? 'Create your RoomPulse account' : 'Sign in to RoomPulse'}
        </h2>
        <p className="mt-1 text-sm text-slate-500">
          Sensor-verified study room booking system
        </p>
      </div>

      <div className="mt-8 sm:mx-auto sm:w-full sm:max-w-md">
        <div className="bg-white py-8 px-6 shadow-sm border border-slate-200 rounded-2xl sm:px-10">
          {/* Mode Tabs */}
          <div className="flex border-b border-slate-200 mb-6">
            <button
              type="button"
              onClick={() => {
                setIsSignUp(false);
                setError(null);
                setSuccessMsg(null);
              }}
              className={`flex-1 py-2.5 text-xs font-semibold text-center border-b-2 transition-colors ${
                !isSignUp
                  ? 'border-brand-600 text-brand-600'
                  : 'border-transparent text-slate-400 hover:text-slate-600'
              }`}
            >
              Sign In
            </button>
            <button
              type="button"
              onClick={() => {
                setIsSignUp(true);
                setError(null);
                setSuccessMsg(null);
              }}
              className={`flex-1 py-2.5 text-xs font-semibold text-center border-b-2 transition-colors ${
                isSignUp
                  ? 'border-brand-600 text-brand-600'
                  : 'border-transparent text-slate-400 hover:text-slate-600'
              }`}
            >
              Register (New Account)
            </button>
          </div>

          {error && (
            <div className="mb-4 p-3 bg-red-50 border border-red-200 text-red-700 text-xs rounded-lg">
              {error}
            </div>
          )}

          {successMsg && (
            <div className="mb-4 p-3 bg-emerald-50 border border-emerald-200 text-emerald-700 text-xs rounded-lg">
              {successMsg}
            </div>
          )}

          <form className="space-y-4" onSubmit={handleSubmit}>
            {isSignUp && (
              <>
                <div>
                  <label className="block text-xs font-medium text-slate-700">Full Name</label>
                  <input
                    type="text"
                    required
                    value={displayName}
                    onChange={(e) => setDisplayName(e.target.value)}
                    className="mt-1 block w-full px-3 py-2 text-sm border border-slate-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500"
                    placeholder="Your Name"
                  />
                </div>

                <div>
                  <label className="block text-xs font-medium text-slate-700">Account Role</label>
                  <select
                    value={role}
                    onChange={(e) => setRole(e.target.value as 'student' | 'staff')}
                    className="mt-1 block w-full px-3 py-2 text-sm border border-slate-300 rounded-lg bg-white focus:outline-none focus:ring-2 focus:ring-brand-500"
                  >
                    <option value="student">Student</option>
                    <option value="staff">Library Staff</option>
                  </select>
                </div>
              </>
            )}

            <div>
              <label className="block text-xs font-medium text-slate-700">Email address</label>
              <input
                type="email"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                className="mt-1 block w-full px-3 py-2 text-sm border border-slate-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-brand-500"
                placeholder="you@example.com"
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
              {isSignUp ? (
                <>
                  <UserPlus className="w-4 h-4 mr-2" />
                  {loading ? 'Creating account...' : 'Create Account'}
                </>
              ) : (
                <>
                  <LogIn className="w-4 h-4 mr-2" />
                  {loading ? 'Signing in...' : 'Sign In'}
                </>
              )}
            </button>
          </form>
        </div>
      </div>
    </div>
  );
};
