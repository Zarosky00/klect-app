'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useCallback, useMemo, useState } from 'react';
import { cn } from '@/lib/cn';
import { ENTITY_LABEL, entityHref } from '@/lib/entities';
import { compactCount, plural } from '@/lib/format';
import { closeupHref } from '@/lib/routes';
import { mediaUrl } from '@/lib/storage';
import { ActionBar } from '@/components/ui/ActionBar';
import { BlurhashImage } from '@/components/ui/BlurhashImage';
import { Icon } from '@/components/ui/Icon';
import { Pressable } from '@/components/ui/Pressable';
import { useSession } from '@/providers/session-provider';
import { ImmersiveViewer, type ImmersivePhoto } from './ImmersiveViewer';
import { PeekMenu } from './PeekMenu';
import { listItemMedia, type EntitySummary } from './queries';

/**
 * One tile, three entity levels, three gestures.
 *
 *   single tap  → Closeup (intercepted modal, deep-linkable URL)
 *   double tap  → immersive fullscreen viewer
 *   long press  → radial quick-action peek
 *
 * `Pressable` resolves the double-tap without the ~260ms penalty, so the single
 * tap navigates on the same frame the finger lifts.
 *
 * At rest the tile is the photo and nothing else; counts and actions fade in on
 * hover or keyboard focus (DESIGN_SYSTEM §4, "hidden but easily accessible").
 */

export interface EntityCardProps {
  summary: EntitySummary;
  /** Rendered under the photo. Off for dense strips. */
  showMeta?: boolean;
  priority?: boolean;
  sizes?: string;
  className?: string;
}

export function EntityCard({
  summary,
  showMeta = true,
  priority = false,
  sizes,
  className,
}: EntityCardProps) {
  const router = useRouter();
  const { supabase } = useSession();
  const [peek, setPeek] = useState<{ x: number; y: number } | null>(null);
  const [immersive, setImmersive] = useState(false);
  const [photos, setPhotos] = useState<ImmersivePhoto[] | null>(null);

  const seed = useMemo(
    () => ({
      likeCount: summary.likeCount,
      saveCount: summary.saveCount,
      repostCount: summary.repostCount,
      commentCount: summary.commentCount,
      viewCount: summary.viewCount,
      childCount: summary.childCount,
    }),
    [summary],
  );

  const coverPhoto = useMemo<ImmersivePhoto[]>(
    () => [
      {
        id: summary.id,
        src: mediaUrl(summary.coverPath),
        alt: summary.title,
        width: summary.width,
        height: summary.height,
      },
    ],
    [summary],
  );

  const openCloseup = useCallback(() => {
    router.push(closeupHref(summary.type, summary.id));
  }, [router, summary.id, summary.type]);

  /** The escalation: an item opens its whole photo set, not just the cover. */
  const openImmersive = useCallback(async () => {
    setImmersive(true);
    if (photos || summary.type !== 'item') return;
    try {
      const media = await listItemMedia(supabase, summary.id);
      if (media.length === 0) return;
      setPhotos(
        media.map((entry, index) => ({
          id: entry.id,
          src: mediaUrl(entry.storage_path),
          alt: entry.alt_text ?? `${summary.title} — photo ${index + 1} of ${media.length}`,
          width: entry.width,
          height: entry.height,
        })),
      );
    } catch {
      // The cover is already on screen; a failed set fetch is not worth a toast.
    }
  }, [photos, summary.id, summary.title, summary.type, supabase]);

  const childLabel =
    summary.type === 'item'
      ? `${compactCount(summary.childCount)} ${plural(summary.childCount, 'photo')}`
      : `${compactCount(summary.childCount)} ${plural(summary.childCount, 'item')}`;

  return (
    <>
      <div className={cn('group relative flex flex-col', className)}>
        <div className="relative overflow-hidden rounded-lg border border-line-subtle bg-surface-1">
          <BlurhashImage
            src={mediaUrl(summary.coverPath)}
            alt={summary.title}
            width={summary.width}
            height={summary.height}
            blurhash={summary.coverBlurhash}
            dominantColor={summary.accentColor}
            priority={priority}
            {...(sizes === undefined ? {} : { sizes })}
          />

          <Pressable
            className="absolute inset-0 size-full"
            aria-label={`${ENTITY_LABEL[summary.type]}: ${summary.title}. Press to open, press twice for fullscreen, hold for quick actions.`}
            feedback={false}
            onActivate={openCloseup}
            onEscalate={() => void openImmersive()}
            onPeek={(position) => setPeek(position)}
          />

          <span className="pointer-events-none absolute left-2 top-2 rounded-full bg-scrim px-2 py-0.5 text-micro uppercase tracking-widest text-ink">
            {ENTITY_LABEL[summary.type]}
          </span>

          {summary.childCount > 0 ? (
            <span className="pointer-events-none absolute right-2 top-2 flex items-center gap-1 rounded-full bg-scrim px-2 py-0.5 text-micro text-ink">
              <Icon name={summary.type === 'item' ? 'image' : 'grid'} size="xs" />
              {compactCount(summary.childCount)}
            </span>
          ) : null}

          <div
            className={cn(
              'absolute inset-x-2 bottom-2 z-raised',
              'opacity-0 transition-opacity dur-fast ease-standard',
              'group-hover:opacity-100 group-focus-within:opacity-100',
            )}
          >
            <ActionBar
              type={summary.type}
              id={summary.id}
              seed={seed}
              title={summary.title}
              variant="overlay"
              showViews={false}
              showComment={false}
              showReport={false}
            />
          </div>
        </div>

        {showMeta ? (
          <div className="mt-2 min-w-0">
            <Link
              href={entityHref(summary.type, summary.id)}
              className="focus-ring block truncate rounded-sm text-body-strong text-ink hover:text-accent"
            >
              {summary.title}
            </Link>
            <p className="mt-0.5 truncate text-caption text-ink-3">
              {summary.subtitle ? `${summary.subtitle} · ` : ''}
              {childLabel}
            </p>
          </div>
        ) : null}
      </div>

      <PeekMenu
        open={peek !== null}
        onClose={() => setPeek(null)}
        position={peek}
        type={summary.type}
        id={summary.id}
        title={summary.title}
      />

      <ImmersiveViewer
        open={immersive}
        onClose={() => setImmersive(false)}
        photos={photos ?? coverPhoto}
        title={summary.title}
      />
    </>
  );
}

/** The masonry the profile, search and match grids share. */
export function EntityGrid({
  summaries,
  emptyState,
  className,
}: {
  summaries: EntitySummary[];
  emptyState?: React.ReactNode;
  className?: string;
}) {
  if (summaries.length === 0) return <>{emptyState ?? null}</>;
  return (
    <div className={cn('k-masonry', className)}>
      {summaries.map((summary, index) => (
        <EntityCard
          key={`${summary.type}:${summary.id}`}
          summary={summary}
          priority={index < 4}
        />
      ))}
    </div>
  );
}
