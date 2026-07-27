import type { Metadata } from 'next';
import Link from 'next/link';
import { TileGrid } from '@/components/surf/TileGrid';
import { tileFromSurfCard, type TileCard } from '@/components/surf/tile-card';
import { ButtonLink } from '@/components/ui/Button';
import { Chip, ChipGroup } from '@/components/ui/Chip';
import { Icon, type IconName } from '@/components/ui/Icon';
import { getCloseup, listPopularTags, surfFeed } from '@/lib/api';
import { compactCount } from '@/lib/format';
import { routes } from '@/lib/routes';
import { buildMetadata } from '@/lib/seo';
import { createClient } from '@/lib/supabase/server';
import { SITE_DESCRIPTION, SITE_NAME, SITE_TAGLINE } from '@/lib/env';
import type { CollectionCloseup } from '@/lib/types';
import { CoverWall } from './_components/CoverWall';
import { HierarchyDiagram } from './_components/HierarchyDiagram';

export const metadata: Metadata = buildMetadata({
  title: `${SITE_NAME} — ${SITE_TAGLINE}`,
  description: SITE_DESCRIPTION,
  path: '/',
});

/** A fixed seed keeps the landing page stable between renders and deploys. */
const LANDING_SEED = 'klect-landing';

const gestures: Array<{ icon: IconName; term: string; description: string }> = [
  {
    icon: 'compass',
    term: 'One click',
    description:
      'The closeup. Every photo in the set, the full catalogue card, live counts, the owner, the breadcrumb, the comments. It opens instantly — nothing waits on a double-click timer.',
  },
  {
    icon: 'image',
    term: 'Two clicks',
    description:
      'Immersive. Fullscreen, scroll or pinch to zoom, drag to pan, arrow keys or a swipe between photos. The chrome steps aside after a moment and returns the instant you move.',
  },
  {
    icon: 'sliders',
    term: 'Hold, or right-click',
    description:
      'The peek. Like, save, repost, share, report — arranged around your cursor. Hidden at rest, one gesture away, never a wall of buttons.',
  },
];

async function landingData(): Promise<{
  cards: TileCard[];
  hierarchy: CollectionCloseup | null;
  tags: Array<{ id: string; name: string; slug: string; use_count: number }>;
}> {
  const supabase = await createClient();

  try {
    const [rows, tags] = await Promise.all([
      surfFeed(supabase, { limit: 36, offset: 0, seed: LANDING_SEED }),
      listPopularTags(supabase, 12).catch(() => []),
    ]);

    const cards = rows.map(tileFromSurfCard);
    const firstCollection = cards.find((card) => card.type === 'collection');

    let hierarchy: CollectionCloseup | null = null;
    if (firstCollection) {
      const payload = await getCloseup(supabase, 'collection', firstCollection.id);
      if (payload?.entity_type === 'collection') hierarchy = payload;
    }

    return { cards, hierarchy, tags };
  } catch {
    // The landing page must still render when the database is unreachable — it
    // is the one page a first-time visitor is guaranteed to see.
    return { cards: [], hierarchy: null, tags: [] };
  }
}

export default async function MarketingHomePage() {
  const { cards, hierarchy, tags } = await landingData();
  const preview = cards.slice(0, 24);
  const wall = cards.slice(0, 20);

  return (
    <>
      {/* ── hero ──────────────────────────────────────────────────────────── */}
      <section className="relative overflow-hidden border-b border-line-subtle">
        <div className="pointer-events-none absolute inset-0">
          <CoverWall cards={wall} className="px-4 pt-8 sm:px-6" />
          <div className="absolute inset-0 bg-gradient-to-b from-base/70 via-base/90 to-base" />
        </div>

        <div className="content-max relative min-w-0 px-4 pb-16 pt-14 sm:px-6 sm:pb-20 sm:pt-20 md:pb-28 md:pt-32">
          <p className="text-label uppercase tracking-widest text-accent">{SITE_TAGLINE}</p>

          <h1 className="mt-5 max-w-[16ch] break-words font-display text-display2 text-ink sm:text-display1">
            The things you keep say more than the things you post.
          </h1>

          <p className="mt-6 max-w-[52ch] text-body text-ink-2">
            Klect makes the <em className="not-italic text-ink">collection</em> the unit of
            content. A shelf holds subcollections. A subcollection holds items. An item holds
            photographs. Every level is a first-class social object — likeable, saveable,
            repostable, and yours.
          </p>

          <div className="mt-9 grid w-full max-w-[32rem] grid-cols-1 gap-3 sm:flex sm:flex-wrap sm:items-center">
            <ButtonLink href={routes.signUp} size="lg" className="w-full sm:w-auto">
              Start collecting
            </ButtonLink>
            <ButtonLink
              href={routes.surf}
              size="lg"
              variant="secondary"
              iconRight="chevron-right"
              className="w-full sm:w-auto"
            >
              Surf without an account
            </ButtonLink>
            {/* APK ships as a GitHub release asset — too big for git or Vercel */}
            <ButtonLink
              href="https://github.com/Zarosky00/klect-app/releases/latest/download/klect.apk"
              size="lg"
              variant="secondary"
              iconLeft="download"
              download
              target="_blank"
              rel="noopener"
              className="w-full sm:w-auto"
            >
              Get the Android app
            </ButtonLink>
          </div>

          {cards.length > 0 ? (
            <p className="mt-6 text-caption text-ink-3">
              Everything on this page is live public content from real shelves.
            </p>
          ) : null}
        </div>
      </section>

      {/* ── the hierarchy ─────────────────────────────────────────────────── */}
      <section className="content-max px-4 py-20 sm:px-6 md:py-28">
        <header className="max-w-[46ch]">
          <p className="text-label uppercase tracking-widest text-accent">The structure</p>
          <h2 className="mt-3 font-display text-display2 text-ink">
            Three levels, not one flat feed.
          </h2>
          <p className="mt-4 text-body text-ink-2">
            Every other network treats the post as the atom — disposable by design, buried by
            tomorrow. A collection is the opposite: something you return to, add to, and show
            off.
          </p>
        </header>

        <div className="mt-12">
          <HierarchyDiagram payload={hierarchy} />
        </div>
      </section>

      {/* ── the gesture contract ──────────────────────────────────────────── */}
      <section className="border-y border-line-subtle bg-sunken">
        <div className="content-max px-4 py-20 sm:px-6 md:py-28">
          <header className="max-w-[46ch]">
            <p className="text-label uppercase tracking-widest text-accent">The feel</p>
            <h2 className="mt-3 font-display text-display2 text-ink">
              One gesture language, everywhere.
            </h2>
            <p className="mt-4 text-body text-ink-2">
              Identical on the web and in your hand. The most common action is one gesture away,
              the rest are two, and nothing is three.
            </p>
          </header>

          <dl className="mt-12 grid gap-6 md:grid-cols-3">
            {gestures.map((gesture) => (
              <div
                key={gesture.term}
                className="flex flex-col gap-3 rounded-lg border border-line-subtle bg-surface-1 p-6"
              >
                <span className="grid size-11 place-items-center rounded-full bg-surface-2 text-accent">
                  <Icon name={gesture.icon} size="lg" />
                </span>
                <dt className="font-display text-title1 text-ink">{gesture.term}</dt>
                <dd className="text-callout text-ink-2">{gesture.description}</dd>
              </div>
            ))}
          </dl>
        </div>
      </section>

      {/* ── the live feed ─────────────────────────────────────────────────── */}
      {preview.length > 0 ? (
        <section className="content-max px-4 py-20 sm:px-6 md:py-28">
          <header className="flex flex-wrap items-end gap-4">
            <div className="min-w-0 flex-1">
              <p className="text-label uppercase tracking-widest text-accent">Surf</p>
              <h2 className="mt-3 font-display text-display2 text-ink">
                This is the actual feed. Try it.
              </h2>
              <p className="mt-4 max-w-[52ch] text-body text-ink-2">
                Items, subcollections and collections interleaved — because a shelf is worth
                surfacing as much as a single thing on it. Click any tile for its closeup,
                double-click for fullscreen, hold for quick actions. No account needed.
              </p>
            </div>
            <ButtonLink href={routes.surf} variant="secondary" iconRight="chevron-right">
              Open Surf
            </ButtonLink>
          </header>

          <div className="mt-10">
            <TileGrid cards={preview} priorityCount={8} />
          </div>
        </section>
      ) : null}

      {/* ── what people collect ───────────────────────────────────────────── */}
      {tags.length > 0 ? (
        <section className="border-t border-line-subtle">
          <div className="content-max px-4 py-16 sm:px-6">
            <h2 className="font-display text-title1 text-ink">What people are collecting</h2>
            <ChipGroup className="mt-5">
              {tags.map((tag) => (
                <Chip key={tag.id} href={`${routes.search}?q=${encodeURIComponent(tag.slug)}`}>
                  #{tag.name}
                  <span className="tabular text-ink-3">{compactCount(tag.use_count)}</span>
                </Chip>
              ))}
            </ChipGroup>
          </div>
        </section>
      ) : null}

      {/* ── close ─────────────────────────────────────────────────────────── */}
      <section className="border-t border-line-subtle bg-sunken">
        <div className="content-max flex flex-col items-start gap-6 px-4 py-20 sm:px-6 md:py-28">
          <h2 className="max-w-[18ch] font-display text-display1 text-ink">
            Start the shelf you have been meaning to start.
          </h2>
          <p className="max-w-[52ch] text-body text-ink-2">
            Photograph it, name it, group it. Klect handles the rest — counts kept honest by the
            database, discovery by taste rather than volume, and a page worth sharing at every
            level.
          </p>
          <div className="flex flex-wrap items-center gap-4">
            <ButtonLink href={routes.signUp} size="lg">
              Create your account
            </ButtonLink>
            <Link
              href={routes.about}
              className="focus-ring rounded-sm text-label text-ink-2 underline underline-offset-4 transition-colors dur-fast hover:text-ink"
            >
              Why collections
            </Link>
            <a
              href="https://github.com/Zarosky00/klect-app/releases/latest/download/klect.apk"
              download
              className="focus-ring rounded-sm text-label text-ink-2 underline underline-offset-4 transition-colors dur-fast hover:text-ink"
            >
              Download the Android app (.apk)
            </a>
          </div>
        </div>
      </section>
    </>
  );
}
