import 'server-only';

import { cache } from 'react';
import type { User } from '@supabase/supabase-js';
import type { AppRole } from '@/lib/entities';
import { createClient } from '@/lib/supabase/server';
import type { ViewerProfile } from '@/providers/session-provider';

const STAFF_ROLES: readonly AppRole[] = ['moderator', 'admin', 'superadmin'];

export interface ViewerBootstrap {
  user: User | null;
  profile: ViewerProfile | null;
  roles: AppRole[];
  isStaff: boolean;
}

/**
 * Everything the shell needs about the current viewer, resolved once per
 * request. `cache()` dedupes it across the layout and every page that asks.
 */
export const getViewerBootstrap = cache(async (): Promise<ViewerBootstrap> => {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) return { user: null, profile: null, roles: [], isStaff: false };

  const [profileResult, rolesResult] = await Promise.all([
    supabase
      .from('profiles')
      .select(
        'id, username, display_name, avatar_path, is_verified, onboarded_at, is_suspended',
      )
      .eq('id', user.id)
      .maybeSingle(),
    supabase.from('user_roles').select('role').eq('user_id', user.id),
  ]);

  const roles = (rolesResult.data ?? []).map((row) => row.role);

  return {
    user,
    profile: profileResult.data ?? null,
    roles,
    isStaff: roles.some((role) => STAFF_ROLES.includes(role)),
  };
});

/** Convenience for pages that only need to know whether anyone is signed in. */
export async function requireViewer(): Promise<ViewerBootstrap & { user: User }> {
  const viewer = await getViewerBootstrap();
  if (!viewer.user) {
    throw new Error('[klect] requireViewer called on a route middleware should have gated.');
  }
  return viewer as ViewerBootstrap & { user: User };
}
