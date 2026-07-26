import Link from 'next/link';
import type { ReactNode } from 'react';
import { ButtonLink } from '@/components/ui/Button';
import { ThemeToggle } from '@/components/chrome/ThemeToggle';
import { Wordmark } from '@/components/chrome/Wordmark';
import { routes } from '@/lib/routes';
import { SITE_NAME } from '@/lib/env';
import { getViewerBootstrap } from '@/lib/viewer';

export default async function MarketingLayout({ children }: { children: ReactNode }) {
  const { user } = await getViewerBootstrap();

  return (
    <div className="flex min-h-dvh flex-col">
      <header className="glass sticky top-0 z-sticky border-b border-line-subtle">
        <div className="content-max flex items-center gap-4 px-4 py-3 sm:px-6">
          <Wordmark />
          <nav aria-label="Marketing" className="ml-4 hidden items-center gap-4 sm:flex">
            <Link
              href={routes.about}
              className="focus-ring rounded-sm text-callout text-ink-2 transition-colors dur-fast hover:text-ink"
            >
              About
            </Link>
            <Link
              href={routes.surf}
              className="focus-ring rounded-sm text-callout text-ink-2 transition-colors dur-fast hover:text-ink"
            >
              Explore
            </Link>
          </nav>

          <div className="flex-1" />
          <ThemeToggle className="hidden sm:inline-flex" />

          {user ? (
            <ButtonLink href={routes.surf} size="sm">
              Open Klect
            </ButtonLink>
          ) : (
            <>
              <ButtonLink href={routes.signIn} variant="ghost" size="sm">
                Sign in
              </ButtonLink>
              <ButtonLink href={routes.signUp} size="sm">
                Start collecting
              </ButtonLink>
            </>
          )}
        </div>
      </header>

      <main id="main" className="flex-1">
        {children}
      </main>

      <footer className="border-t border-line-subtle">
        <div className="content-max flex flex-col gap-4 px-4 py-8 sm:flex-row sm:items-center sm:px-6">
          <Wordmark size="sm" />
          <p className="text-caption text-ink-3">
            © {new Date().getFullYear()} {SITE_NAME}. Collections, not posts.
          </p>
          <div className="flex-1" />
          <nav aria-label="Footer" className="flex flex-wrap gap-4">
            <Link
              href={routes.about}
              className="focus-ring rounded-sm text-caption text-ink-2 hover:text-ink"
            >
              About
            </Link>
            <Link
              href={routes.surf}
              className="focus-ring rounded-sm text-caption text-ink-2 hover:text-ink"
            >
              Surf
            </Link>
            <Link
              href={routes.signIn}
              className="focus-ring rounded-sm text-caption text-ink-2 hover:text-ink"
            >
              Sign in
            </Link>
          </nav>
        </div>
      </footer>
    </div>
  );
}
