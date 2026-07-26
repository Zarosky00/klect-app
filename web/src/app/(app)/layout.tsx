import type { ReactNode } from 'react';
import { AppNavBottomBar, AppNavRail, AppTopBar } from '@/components/chrome/AppNav';

/**
 * The signed-in shell. A left rail on desktop, a top bar plus bottom bar on
 * mobile. Public routes (`/u`, `/c`, `/s`, `/i`, `/surf`, `/search`) live here
 * too — an anonymous visitor gets the same chrome with a Sign in call to action.
 */
export default function AppLayout({ children }: { children: ReactNode }) {
  return (
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
  );
}
