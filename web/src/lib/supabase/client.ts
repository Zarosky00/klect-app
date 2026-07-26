'use client';

import { createBrowserClient } from '@supabase/ssr';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '@/lib/database.types';
import { SUPABASE_PUBLISHABLE_KEY, SUPABASE_URL } from '@/lib/env';

export type KlectClient = SupabaseClient<Database>;

let browserClient: KlectClient | undefined;

/**
 * The browser Supabase client. `createBrowserClient` is already a singleton per
 * (url, key) pair, but we memoise the reference too so React identity checks in
 * effect dependency arrays stay stable across renders.
 *
 * Cookie handling is left to the library's `document.cookie` implementation,
 * which is the current, non-deprecated default and stays in lockstep with the
 * `getAll`/`setAll` server implementation.
 */
export function createClient(): KlectClient {
  if (!browserClient) {
    browserClient = createBrowserClient<Database>(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
  }
  return browserClient;
}
