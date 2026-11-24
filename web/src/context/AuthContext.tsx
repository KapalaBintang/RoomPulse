import React, { createContext, useContext, useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { Profile } from '../lib/types';
import { User } from '@supabase/supabase-js';

interface AuthContextType {
  user: User | null;
  profile: Profile | null;
  loading: boolean;
  loginWithEmail: (email: string, pass: string) => Promise<{ error: string | null }>;
  signOut: () => Promise<void>;
  switchUserQuick: (email: string) => Promise<void>;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [user, setUser] = useState<User | null>(null);
  const [profile, setProfile] = useState<Profile | null>(null);
  const [loading, setLoading] = useState<boolean>(true);

  const fetchProfile = async (userId: string) => {
    try {
      const { data, error } = await supabase
        .from('profiles')
        .select('*')
        .eq('id', userId)
        .maybeSingle();

      if (!error && data) {
        setProfile(data as Profile);
      } else {
        // Fallback: auto-create or restore profile row
        const { data: userData } = await supabase.auth.getUser();
        const role = userData.user?.email?.startsWith('staff') ? 'staff' : 'student';
        const displayName =
          userData.user?.user_metadata?.display_name ||
          (userData.user?.email ? userData.user.email.split('@')[0] : 'Student User');

        await supabase.from('profiles').upsert({
          id: userId,
          display_name: displayName,
          role: role,
        });

        setProfile({
          id: userId,
          display_name: displayName,
          role: role,
          telegram_chat_id: null,
        });
      }
    } catch (_e) {
      // ignore
    }
  };

  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session } }) => {
      setUser(session?.user ?? null);
      if (session?.user) {
        fetchProfile(session.user.id);
      }
      setLoading(false);
    });

    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
      setUser(session?.user ?? null);
      if (session?.user) {
        fetchProfile(session.user.id);
      } else {
        setProfile(null);
      }
      setLoading(false);
    });

    return () => {
      subscription.unsubscribe();
    };
  }, []);

  const loginWithEmail = async (email: string, pass: string) => {
    let { data, error } = await supabase.auth.signInWithPassword({
      email,
      password: pass,
    });

    // If demo account doesn't exist in Supabase Auth yet, auto-register
    if (error && email.endsWith('@roompulse.local')) {
      const displayName = email.startsWith('staff')
        ? 'Library Staff Lead'
        : email.includes('student1')
        ? 'Alice Pratama'
        : 'Bob Santoso';

      const sup = await supabase.auth.signUp({
        email,
        password: pass,
        options: { data: { display_name: displayName } },
      });

      if (sup.error) {
        return { error: error.message };
      }

      data = sup.data as any;
      error = null;
    }

    if (error) {
      return { error: error.message };
    }

    if (data?.user) {
      setUser(data.user);
      await fetchProfile(data.user.id);
    }
    return { error: null };
  };

  const signOut = async () => {
    await supabase.auth.signOut();
    setUser(null);
    setProfile(null);
  };

  const switchUserQuick = async (email: string) => {
    setLoading(true);
    await supabase.auth.signOut();

    let { data, error } = await supabase.auth.signInWithPassword({
      email,
      password: 'password123',
    });

    // If demo account doesn't exist in Supabase Auth yet, auto-register
    if (error) {
      const displayName = email.startsWith('staff')
        ? 'Library Staff Lead'
        : email.includes('student1')
        ? 'Alice Pratama'
        : 'Bob Santoso';

      const sup = await supabase.auth.signUp({
        email,
        password: 'password123',
        options: { data: { display_name: displayName } },
      });

      if (sup.error) {
        setLoading(false);
        throw new Error(error.message || sup.error.message);
      }

      data = sup.data as any;
    }

    if (data?.user) {
      setUser(data.user);
      await fetchProfile(data.user.id);
    }
    setLoading(false);
  };

  return (
    <AuthContext.Provider
      value={{
        user,
        profile,
        loading,
        loginWithEmail,
        signOut,
        switchUserQuick,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
};

export const useAuth = () => {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used within an AuthProvider');
  return ctx;
};
