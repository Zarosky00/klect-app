import type { ReactNode } from 'react';
import { AppNavBottomBar, AppNavRail, AppTopBar } from '@/components/chrome/AppNav';
import { NotificationsProvider } from '@/providers/notifications-provider';

/**
 * The signed-in shell. A left rail on desktop, a top bar plus bottom bar on
 * mobile. Public routes (`/u`, `/c`, `/s`, `/i`, `/surf`, `/search`) live here
 * too — an anonymous visitor gets the same chrome with a Sign in call to action.
 *
 * `NotificationsProvider` lives here (not in the root providers) because it is
 * shell furniture: one realtime channel that feeds the Alerts badge and the
 * arrival banner from the moment any signed-in page paints.
 */
export default function AppLayout({ children }: { children: ReactNode }) {
  return (
    <NotificationsProvider>
      <div className="flex min-h-dvh">
        <AppNavRail />
        <div className="flex min-w-0 flex-1 flex-col">
          <AppTopBar />
          <main
            id="main"
            className="min-w-0 flex-1 pb-[calc(var(--k-bottombar-h)+env(safe-area-inset-bottom))] md:pb-0"
          >
            {children}
          </main>
          <AppNavBottomBar />
        </div>
      </div>
    </NotificationsProvider>
  );
}
