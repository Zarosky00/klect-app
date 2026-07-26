import Link from 'next/link';
import { BlurhashImage } from '@/components/ui/BlurhashImage';
import { Icon } from '@/components/ui/Icon';
import { cn } from '@/lib/cn';
import { compactCount, plural } from '@/lib/format';
import { collectionHref, itemHref, subcollectionHref } from '@/lib/routes';
import { mediaUrl } from '@/lib/storage';
import type { CollectionCloseup } from '@/lib/types';

/**
 * The hierarchy, explained with a real shelf rather than a diagram of boxes.
 *
 * Collection → Subcollection → Item, each rung labelled with the fact that
 * matters: **every one of them is independently likeable, saveable, repostable,
 * commentable and counted**. That symmetry is the product, so the landing page
 * shows it working on live public content instead of asserting it in prose.
 */

const LEVELS = [
  {
    number: '01',
    name: 'Collection',
    blurb: 'The shelf you own. “Anime.” “Cameras.” “Every Blue Note pressing I could find.”',
  },
  {
    number: '02',
    name: 'Subcollection',
    blurb: 'The run inside it. “JJK.” “One Piece.” The grouping that only makes sense to a collector.',
  },
  {
    number: '03',
    name: 'Item',
    blurb: 'The thing itself, with every photograph of it and the details you bothered to record.',
  },
] as const;

export function HierarchyDiagram({ payload }: { payload: CollectionCloseup | null }) {
  const collection = payload?.collection ?? null;
  const subcollections = payload?.subcollections.slice(0, 3) ?? [];
  const items = payload?.items.slice(0, 5) ?? [];

  return (
    <div className="grid gap-10 lg:grid-cols-[minmax(0,20rem)_minmax(0,1fr)] lg:gap-14">
      <ol className="flex flex-col gap-8">
        {LEVELS.map((level) => (
          <li key={level.number} className="flex gap-4">
            <span className="tabular pt-1 text-title3 text-accent">{level.number}</span>
            <div>
              <h3 className="font-display text-title1 text-ink">{level.name}</h3>
              <p className="mt-1 text-callout text-ink-2">{level.blurb}</p>
            </div>
          </li>
        ))}

        <li className="rounded-lg border border-line-subtle bg-surface-1 p-4">
          <p className="text-callout text-ink-2">
            All three are{' '}
            <strong className="text-ink">likeable, saveable, repostable,
            commentable, shareable and counted</strong>{' '}
            — independently. Nowhere else can you save a shelf.
          </p>
          <ul className="mt-3 flex flex-wrap gap-2">
            {(
              [
                ['heart', 'like'],
                ['bookmark', 'save'],
                ['repost', 'repost'],
                ['comment', 'comment'],
                ['eye', 'views'],
              ] as const
            ).map(([icon, label]) => (
              <li
                key={label}
                className="inline-flex items-center gap-1.5 rounded-full bg-surface-2 px-2.5 py-1 text-caption text-ink-2"
              >
                <Icon name={icon} size="xs" />
                {label}
              </li>
            ))}
          </ul>
        </li>
      </ol>

      {collection ? (
        <div className="flex flex-col gap-5">
          <Rung
            label="Collection"
            href={collectionHref(collection.id)}
            title={collection.name}
            meta={`${compactCount(collection.subcollection_count)} ${plural(collection.subcollection_count, 'subcollection')} · ${compactCount(collection.item_count)} ${plural(collection.item_count, 'item')}`}
            coverPath={collection.cover_path}
            blurhash={collection.cover_blurhash}
            accent={collection.accent_color}
            size="lg"
          />

          {subcollections.length > 0 ? (
            <Branch>
              <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
                {subcollections.map((sub) => (
                  <Rung
                    key={sub.id}
                    label="Subcollection"
                    href={subcollectionHref(sub.id)}
                    title={sub.name}
                    meta={`${compactCount(sub.item_count)} ${plural(sub.item_count, 'item')}`}
                    coverPath={sub.cover_path}
                    blurhash={sub.cover_blurhash}
                    accent={null}
                    size="md"
                  />
                ))}
              </div>
            </Branch>
          ) : null}

          {items.length > 0 ? (
            <Branch>
              <div className="flex gap-3 overflow-x-auto pb-1">
                {items.map((item) => (
                  <Link
                    key={item.id}
                    href={itemHref(item.id)}
                    className="focus-ring group w-28 flex-none rounded-md sm:w-32"
                  >
                    <BlurhashImage
                      src={mediaUrl(item.cover_path)}
                      alt={item.title}
                      width={item.cover_width}
                      height={item.cover_height}
                      blurhash={item.cover_blurhash}
                      sizes="128px"
                      className="rounded-md"
                    />
                    <p className="mt-1.5 truncate text-caption text-ink-2 transition-colors dur-fast group-hover:text-ink">
                      {item.title}
                    </p>
                  </Link>
                ))}
              </div>
            </Branch>
          ) : null}
        </div>
      ) : null}
    </div>
  );
}

function Branch({ children }: { children: React.ReactNode }) {
  return (
    <div className="relative pl-6">
      <span
        aria-hidden
        className="absolute left-2 top-0 h-full w-px bg-line"
      />
      <span
        aria-hidden
        className="absolute left-2 top-6 h-px w-4 bg-line"
      />
      {children}
    </div>
  );
}

function Rung({
  label,
  href,
  title,
  meta,
  coverPath,
  blurhash,
  accent,
  size,
}: {
  label: string;
  href: string;
  title: string;
  meta: string;
  coverPath: string | null;
  blurhash: string | null;
  accent: string | null;
  size: 'md' | 'lg';
}) {
  return (
    <Link
      href={href}
      className={cn(
        'focus-ring group flex items-center gap-4 overflow-hidden rounded-lg border border-line',
        'bg-surface-1 transition-colors dur-fast ease-standard hover:border-accent',
      )}
    >
      <div className={cn('shrink-0', size === 'lg' ? 'w-28 sm:w-36' : 'w-20')}>
        <BlurhashImage
          src={mediaUrl(coverPath)}
          alt=""
          blurhash={blurhash}
          dominantColor={accent}
          fallbackAspect={1}
          sizes="144px"
        />
      </div>

      <div className="min-w-0 flex-1 py-3 pr-4">
        <p className="text-micro uppercase tracking-widest text-ink-3">{label}</p>
        <p
          className={cn(
            'truncate font-display text-ink',
            size === 'lg' ? 'text-display3' : 'text-title2',
          )}
        >
          {title}
        </p>
        <p className="tabular truncate text-caption text-ink-2">{meta}</p>
      </div>

      <Icon
        name="chevron-right"
        size="md"
        className="mr-4 shrink-0 text-ink-3 transition-colors dur-fast group-hover:text-accent"
      />
    </Link>
  );
}
