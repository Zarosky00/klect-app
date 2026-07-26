'use client';

import { useRouter } from 'next/navigation';
import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react';
import type { Session, User } from '@supabase/supabase-js';
import type { AppRole } from '@/lib/entities';
import { createClient, type KlectClient } from '@/lib/supabase/client';

export interface ViewerProfile {
  id: string;
  username: string;
  display_name: string;
  avatar_path: string | null;
  is_verified: boolean;
  onboarded_at: string | null;
  is_suspended: boolean;
}

interface SessionContextValue {
  supabase: KlectClient;
  user: User | null;
  profile: ViewerProfile | null;
  roles: AppRole[];
  isStaff: boolean;
  loading: boolean;
  signOut: () => Promise<void>;
}

const SessionContext = createContext<SessionContextValue | null>(null);

const STAFF_ROLES: readonly AppRole[] = ['moderator', 'admin', 'superadmin'];

export interface SessionProviderProps {
  children: ReactNode;
  /** Server-rendered values so the first paint already knows who you are. */
  initialUser?: User | null;
  initialProfile?: ViewerProfile | null;
  initialRoles?: AppRole[];
}

export function SessionProvider({
  children,
  initialUser = null,
  initialProfile = null,
  initialRoles = [],
}: SessionProviderProps) {
  const supabase = useMemo(() => createClient(), []);
  const router = useRouter();

  const [user, setUser] = useState<User | null>(initialUser);
  const [profile, setProfile] = useState<ViewerProfile | null>(initialProfile);
  const [roles, setRoles] = useState<AppRole[]>(initialRoles);
  const [loading, setLoading] = useState(initialUser === null);

  useEffect(() => {
    let active = true;

    const hydrate = async (session: Session | null) => {
      const nextUser = session?.user ?? null;
      if (!active) return;
      setUser(nextUser);

      if (!nextUser) {
        setProfile(null);
        setRoles([]);
        setLoading(false);
        return;
      }

      const [profileResult, rolesResult] = await Promise.all([
        supabase
          .from('profiles')
          .select('id, username, display_name, avatar_path, is_verified, onboarded_at, is_suspended')
          .eq('id', nextUser.id)
          .maybeSingle(),
        supabase.from('user_roles').select('role').eq('user_id', nextUser.id),
      ]);

      if (!active) return;
      setProfile(profileResult.data ?? null);
      setRoles((rolesResult.data ?? []).map((row) => row.role));
      setLoading(false);
    };

    void supabase.auth.getSession().then(({ data }) => hydrate(data.session));

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((event, session) => {
      void hydrate(session);
      if (event === 'SIGNED_IN' || event === 'SIGNED_OUT' || event === 'USER_UPDATED') {
        // Server Components hold the authoritative render; make them re-run.
        router.refresh();
      }
    });

    return () => {
      active = false;
      subscription.unsubscribe();
    };
  }, [router, supabase]);

  const value = useMemo<SessionContextValue>(
    () => ({
      supabase,
      user,
      profile,
      roles,
      isStaff: roles.some((role) => STAFF_ROLES.includes(role)),
      loading,
      signOut: async () => {
        await supabase.auth.signOut();
        router.push('/');
        router.refresh();
      },
    }),
    [loading, profile, roles, router, supabase, user],
  );

  return <SessionContext.Provider value={value}>{children}</SessionContext.Provider>;
}

export function useSession(): SessionContextValue {
  const context = useContext(SessionContext);
  if (!context) throw new Error('useSession must be used inside <SessionProvider/>.');
  return context;
}

/** The browser Supabase client, already bound to the session. */
export function useSupabase(): KlectClient {
  return useSession().supabase;
}

/** `null` when signed out — every caller must handle that. */
export function useViewer(): { user: User | null; profile: ViewerProfile | null } {
  const { user, profile } = useSession();
  return { user, profile };
}
