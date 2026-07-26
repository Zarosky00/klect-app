import Link from 'next/link';
import { ButtonLink } from '@/components/ui/Button';
import { cn } from '@/lib/cn';
import { SITE_NAME } from '@/lib/env';
import { routes } from '@/lib/routes';

/**
 * The signed-out call to action on public entity pages.
 *
 * A logged-out visitor arrives here from a search result or a shared link, so
 * this is the one moment the product gets to explain itself: one sentence, one
 * primary action, and a way to keep looking without an account.
 */
export function SignedOutCta({
  subject,
  className,
}: {
  /** What they are looking at, e.g. "this collection". */
  subject?: string;
  className?: string;
}) {
  return (
    <aside
      className={cn(
        'flex flex-col gap-4 rounded-lg border border-line bg-surface-1 p-5',
        'sm:flex-row sm:items-center',
        className,
      )}
    >
      <div className="min-w-0 flex-1">
        <p className="font-display text-title1 text-ink">
          Keep {subject ?? 'this'} — and start a shelf of your own.
        </p>
        <p className="mt-1 text-callout text-ink-2">
          {SITE_NAME} is where collections are the unit of content. Save what you
          love, group it into subcollections, and find collectors with your taste.
        </p>
      </div>

      <div className="flex shrink-0 flex-wrap items-center gap-3">
        <ButtonLink href={routes.signUp}>Start collecting</ButtonLink>
        <Link
          href={routes.surf}
          className="focus-ring rounded-sm text-label text-ink-2 underline underline-offset-4 transition-colors dur-fast hover:text-ink"
        >
          Keep surfing
        </Link>
      </div>
    </aside>
  );
}
