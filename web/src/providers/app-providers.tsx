'use client';

import type { ReactNode } from 'react';
import type { User } from '@supabase/supabase-js';
import type { AppRole } from '@/lib/entities';
import { InteractionsProvider } from '@/providers/interactions-provider';
import { SessionProvider, type ViewerProfile } from '@/providers/session-provider';
import { ThemeProvider } from '@/providers/theme-provider';
import { ToastProvider } from '@/providers/toast-provider';

export interface AppProvidersProps {
  children: ReactNode;
  initialUser?: User | null;
  initialProfile?: ViewerProfile | null;
  initialRoles?: AppRole[];
}

/**
 * Provider order matters:
 *   Theme  → nothing depends on it, but it must own <html data-theme> first.
 *   Toast  → the interaction engine reports failures through it.
 *   Session→ owns the Supabase client the engine calls.
 *   Interactions → the optimistic engine.
 */
export function AppProviders({
  children,
  initialUser = null,
  initialProfile = null,
  initialRoles = [],
}: AppProvidersProps) {
  return (
    <ThemeProvider>
      <ToastProvider>
        <SessionProvider
          initialUser={initialUser}
          initialProfile={initialProfile}
          initialRoles={initialRoles}
        >
          <InteractionsProvider>{children}</InteractionsProvider>
        </SessionProvider>
      </ToastProvider>
    </ThemeProvider>
  );
}
