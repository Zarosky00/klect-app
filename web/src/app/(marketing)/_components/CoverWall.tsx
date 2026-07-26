import { BlurhashImage } from '@/components/ui/BlurhashImage';
import { cn } from '@/lib/cn';
import { mediaUrl } from '@/lib/storage';
import type { TileCard } from '@/components/surf/tile-card';

/**
 * The hero's backdrop: real covers from real public shelves, laid out as
 * offset columns and pushed behind a scrim so the type stays the loudest thing
 * on the page.
 *
 * Decorative — `aria-hidden`, no links, no alt text. The interactive version of
 * the same content is the live preview further down the page.
 */
export function CoverWall({
  cards,
  className,
}: {
  cards: readonly TileCard[];
  className?: string;
}) {
  if (cards.length === 0) return null;

  // Five offset columns; the middle ones ride higher so the wall reads as a
  // gallery rather than a table.
  const columns = 5;
  const offsets = [
    'translate-y-0',
    '-translate-y-10',
    'translate-y-6',
    '-translate-y-6',
    'translate-y-10',
  ];
  /** Two columns on a phone, three on a tablet, all five on a desktop. */
  const visibility = ['flex', 'flex', 'hidden sm:flex', 'hidden lg:flex', 'hidden lg:flex'];
  const buckets: TileCard[][] = Array.from({ length: columns }, () => []);
  cards.forEach((card, index) => buckets[index % columns]?.push(card));

  return (
    <div aria-hidden className={cn('pointer-events-none select-none', className)}>
      <div className="flex gap-3 opacity-[var(--k-opacity-veil)]">
        {buckets.map((bucket, index) => (
          <div
            key={index}
            className={cn('flex-1 flex-col gap-3', visibility[index], offsets[index])}
          >
            {bucket.slice(0, 4).map((card) => (
              <BlurhashImage
                key={`${card.type}:${card.id}`}
                src={mediaUrl(card.coverPath)}
                alt=""
                width={card.width}
                height={card.height}
                blurhash={card.blurhash}
                dominantColor={card.accentColor}
                sizes="20vw"
                className="rounded-md"
              />
            ))}
          </div>
        ))}
      </div>
    </div>
  );
}
