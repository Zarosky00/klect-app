import 'server-only';

import { cookies } from 'next/headers';
import { createServerClient } from '@supabase/ssr';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '@/lib/database.types';
import { SUPABASE_PUBLISHABLE_KEY, SUPABASE_URL } from '@/lib/env';

export type KlectServerClient = SupabaseClient<Database>;

/**
 * Per-request Supabase client for Server Components, Route Handlers and Server
 * Actions.
 *
 * Uses the current `getAll` / `setAll` cookie API — never the deprecated
 * `get`/`set`/`remove` triple. `setAll` throws inside a Server Component
 * (React forbids mutating cookies during render); that is expected and safe to
 * swallow because `src/middleware.ts` refreshes the session on every request
 * and writes the cookies back there.
 *
 * NEVER create a module-level singleton from this — one client per request.
 */
export async function createClient(): Promise<KlectServerClient> {
  const cookieStore = await cookies();

  return createServerClient<Database>(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
    cookies: {
      getAll() {
        return cookieStore.getAll();
      },
      setAll(cookiesToSet) {
        try {
          for (const { name, value, options } of cookiesToSet) {
            cookieStore.set(name, value, options);
          }
        } catch {
          // Called from a Server Component: middleware owns the refresh.
        }
      },
    },
  });
}

/** The signed-in user, or `null`. Revalidated against the auth server. */
export async function getSessionUser() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  return user;
}
