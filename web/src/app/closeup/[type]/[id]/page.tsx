import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { CloseupPanel } from '@/components/closeup/CloseupPanel';
import { Wordmark } from '@/components/chrome/Wordmark';
import { Icon } from '@/components/ui/Icon';
import { getCloseup } from '@/lib/api';
import { entityHref, isEntityType } from '@/lib/entities';
import { closeupHref, routes } from '@/lib/routes';
import { buildMetadata, notFoundMetadata } from '@/lib/seo';
import { mediaUrl } from '@/lib/storage';
import { createClient } from '@/lib/supabase/server';
import { closeupCover, closeupDescription, closeupTitle } from '@/lib/types';

interface PageProps {
  params: Promise<{ type: string; id: string }>;
}

export async function generateMetadata({ params }: PageProps): Promise<Metadata> {
  const { type, id } = await params;
  if (!isEntityType(type)) return notFoundMetadata('Page');

  const supabase = await createClient();
  const payload = await getCloseup(supabase, type, id);
  if (!payload) return notFoundMetadata(type);

  const cover = closeupCover(payload);
  const title = closeupTitle(payload);

  return buildMetadata({
    title: `${title} — ${payload.owner.display_name}`,
    description: closeupDescription(payload),
    // The canonical address of a thing is its own page, never the modal route —
    // otherwise `/c/x` and `/closeup/collection/x` compete for the same rank.
    path: entityHref(payload.entity_type, payload.entity_id),
    image: mediaUrl(cover.path),
    imageAlt: title,
    type: 'article',
    authors: [payload.owner.display_name],
  });
}

/**
 * The full-page fallback for `/closeup/[type]/[id]`.
 *
 * When the route is reached by an in-app navigation, `app/@modal/(.)closeup/…`
 * intercepts it and renders the modal over whatever grid you were on. A hard
 * load, a shared link or a refresh lands here instead — same payload, same
 * component, so the two can never disagree.
 *
 * This route sits outside the `(app)` group and so outside the nav chrome,
 * which is right for a modal fallback: it needs one clear way back up, not a
 * whole shell.
 */
export default async function CloseupPage({ params }: PageProps) {
  const { type, id } = await params;
  if (!isEntityType(type)) notFound();

  const supabase = await createClient();
  const payload = await getCloseup(supabase, type, id);
  if (!payload) notFound();

  const canonical = entityHref(payload.entity_type, payload.entity_id);
  const isCanonical = canonical === closeupHref(type, id);

  return (
    <div className="flex min-h-dvh flex-col">
      <header className="glass sticky top-0 z-sticky flex items-center gap-4 border-b border-line-subtle px-4 py-3 sm:px-6">
        <Link
          href={routes.surf}
          className="focus-ring inline-flex items-center gap-2 rounded-md px-2 py-1 text-label text-ink-2 transition-colors dur-fast hover:text-ink"
        >
          <Icon name="arrow-left" size="md" />
          Back to Surf
        </Link>
        <div className="flex-1" />
        <Wordmark size="sm" />
      </header>

      <main id="main" className="content-max w-full flex-1 px-0 py-0 md:px-6 md:py-8">
        <div className="overflow-hidden border-line bg-surface-1 md:rounded-xl md:border">
          <CloseupPanel payload={payload} />
        </div>

        {isCanonical ? null : (
          <p className="px-4 py-6 text-caption text-ink-3 md:px-0">
            This is the shareable view.{' '}
            <Link
              href={canonical}
              className="focus-ring rounded-sm text-accent underline underline-offset-4"
            >
              Open the permanent page
            </Link>
            .
          </p>
        )}
      </main>
    </div>
  );
}
