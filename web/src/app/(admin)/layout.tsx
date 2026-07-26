import { redirect } from 'next/navigation';
import type { ReactNode } from 'react';
import { AdminNav } from '@/components/chrome/AdminNav';
import { Wordmark } from '@/components/chrome/Wordmark';
import { ThemeToggle } from '@/components/chrome/ThemeToggle';
import { DEFAULT_SIGNED_IN_ROUTE, routes } from '@/lib/routes';
import { getViewerBootstrap } from '@/lib/viewer';

/**
 * Admin guard, layer two.
 *
 * Layer one is `src/middleware.ts`, which bounces non-staff before the page is
 * ever rendered. Layer three — the only one that actually matters for security —
 * is the database: every `admin_*` RPC re-checks `is_staff()` / `is_admin()`
 * server-side, so a leaked route exposes nothing at all.
 */
export default async function AdminLayout({ children }: { children: ReactNode }) {
  const { user, isStaff, roles } = await getViewerBootstrap();

  if (!user) redirect(routes.signIn);
  if (!isStaff) redirect(DEFAULT_SIGNED_IN_ROUTE);

  return (
    <div className="flex min-h-dvh flex-col">
      <header className="glass sticky top-0 z-sticky flex items-center gap-4 border-b border-line-subtle px-4 py-3 sm:px-6">
        <Wordmark href={routes.admin} size="sm" />
        <span className="rounded-full border border-line bg-surface-2 px-2 py-0.5 text-micro uppercase tracking-widest text-ink-2">
          Console
        </span>
        <div className="flex-1" />
        <span className="hidden text-caption text-ink-3 sm:inline">
          {roles.join(' · ')}
        </span>
        <ThemeToggle />
      </header>

      <div className="content-max flex w-full flex-1 flex-col gap-6 px-4 py-6 sm:px-6 lg:flex-row">
        <AdminNav />
        <main id="main" className="min-w-0 flex-1">
          {children}
        </main>
      </div>
    </div>
  );
}
