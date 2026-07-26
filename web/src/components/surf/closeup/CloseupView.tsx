'use client';

import { useMemo, useState } from 'react';
import Link from 'next/link';
import { ActionBar } from '@/components/ui/ActionBar';
import { BlurhashImage } from '@/components/ui/BlurhashImage';
import { IconButton } from '@/components/ui/Button';
import { Chip, ChipGroup } from '@/components/ui/Chip';
import { cn } from '@/lib/cn';
import { ENTITY_LABEL, entityHref } from '@/lib/entities';
import { compactCount, longTimeAgo, plural } from '@/lib/format';
import { seedFromCloseup } from '@/lib/interactions';
import { closeupHref, collectionHref, routes, subcollectionHref } from '@/lib/routes';
import { mediaUrl } from '@/lib/storage';
import {
  closeupCover,
  closeupDescription,
  closeupTitle,
  type CloseupPayload,
} from '@/lib/types';
import { useRealtimeEntity, useRecordView } from '@/providers/interactions-provider';
import { useSession } from '@/providers/session-provider';
import {
  ImmersiveViewer,
  photosFromMedia,
  type ImmersiveSource,
} from '../ImmersiveViewer';
import { TileGrid } from '../TileGrid';
import {
  tileFromChildItem,
  tileFromChildSubcollection,
  tileFromSibling,
  type TileCard,
  type TileOwner,
} from '../tile-card';
import { CommentThread } from './CommentThread';
import { ItemFacts } from './ItemFacts';
import { MediaPager } from './MediaPager';
import { OverflowSheet } from './OverflowSheet';
import { OwnerRow } from './OwnerRow';

/**
 * The Closeup — the single-tap detail view.
 *
 * The same component serves the intercepting modal, the `/closeup/...` full
 * page and the public `/c` `/s` `/i` pages, because all four are fed by the one
 * `get_closeup` payload. A deep link and an in-grid tap therefore render
 * identically, which is the whole point of the RPC.
 *
 * What the three levels share — and this symmetry *is* the product — is every
 * social affordance: one ActionBar over the optimistic engine, live counters
 * from `UPDATE` on the entity row, one view recorded per mount, a threaded
 * comment section, and an overflow with report/block/copy link.
 */

export type CloseupVariant = 'page' | 'modal';

export interface CloseupViewProps {
  payload: CloseupPayload;
  variant?: CloseupVariant;
  /** Public `/c` `/s` `/i` pages render their own H1; the modal renders one. */
  headingLevel?: 'h1' | 'h2';
  className?: string;
}

export function CloseupView({
  payload,
  variant = 'page',
  headingLevel = 'h1',
  className,
}: CloseupViewProps) {
  // Counts are not read here on purpose: `ActionBar` renders them from the
  // optimistic engine, seeded by `seedFromCloseup` and kept live by realtime.
  const { entity_type: type, entity_id: id, owner, viewer, tags } = payload;
  const { user } = useSession();

  const cover = closeupCover(payload);
  const title = closeupTitle(payload);
  const description = closeupDescription(payload);

  useRealtimeEntity(type, id);
  useRecordView(type, id);

  const [immersive, setImmersive] = useState<ImmersiveSource | null>(null);
  const [overflow, setOverflow] = useState(false);

  const isOwner = viewer.is_owner === true || (user !== null && user.id === owner.id);

  const tileOwner = useMemo<TileOwner>(
    () => ({
      username: owner.username,
      displayName: owner.display_name,
      avatarPath: owner.avatar_path,
      isVerified: owner.is_verified,
    }),
    [owner],
  );

  const media = payload.entity_type === 'item' ? payload.media : [];

  const openImmersive = (startIndex: number): void => {
    setImmersive({
      type,
      id,
      title,
      cover: { path: cover.path, width: cover.width, height: cover.height },
      photos: media.length > 0 ? photosFromMedia(media, title) : undefined,
      startIndex,
    });
  };

  const breadcrumbCollection =
    payload.entity_type === 'item'
      ? payload.breadcrumb.collection
      : payload.entity_type === 'subcollection'
        ? payload.breadcrumb.collection
        : null;
  const breadcrumbSubcollection =
    payload.entity_type === 'item' ? payload.breadcrumb.subcollection : null;

  const siblings: TileCard[] =
    payload.entity_type === 'item'
      ? payload.siblings.map((sibling) => tileFromSibling(sibling, tileOwner))
      : [];

  const childItems: TileCard[] =
    payload.entity_type === 'collection' || payload.entity_type === 'subcollection'
      ? payload.items.map((item) => tileFromChildItem(item, tileOwner))
      : [];

  const childSubcollections: TileCard[] =
    payload.entity_type === 'collection'
      ? payload.subcollections.map((sub) => tileFromChildSubcollection(sub, tileOwner))
      : [];

  const Heading = headingLevel;

  return (
    <>
      <article className={cn('flex flex-col', className)}>
        <div className="grid gap-0 lg:grid-cols-[minmax(0,1.35fr)_minmax(0,1fr)]">
          <div className="bg-sunken p-4 lg:p-6">
            {media.length > 0 ? (
              <MediaPager
                media={media}
                title={title}
                onImmersive={openImmersive}
              />
            ) : payload.entity_type === 'post' ? (
              <div className="flex flex-col gap-3">
                <blockquote className="rounded-lg border border-line-subtle bg-surface-1 p-6 font-display text-display3 text-ink">
                  {payload.post.body ?? 'Post'}
                </blockquote>
                {payload.post.entity_type && payload.post.entity_id ? (
                  <Link
                    href={closeupHref(payload.post.entity_type, payload.post.entity_id)}
                    className={cn(
                      'focus-ring flex items-center gap-2 rounded-lg border border-line',
                      'bg-surface-1 px-4 py-3 text-callout text-ink-2',
                      'transition-colors dur-fast ease-standard hover:border-line-strong hover:text-ink',
                    )}
                  >
                    <span className="text-micro uppercase tracking-widest text-ink-3">
                      {payload.post.entity_type === 'post' ? 'Quotes' : 'Shares'}
                    </span>
                    View the attached {ENTITY_LABEL[payload.post.entity_type].toLowerCase()}
                  </Link>
                ) : null}
              </div>
            ) : (
              <button
                type="button"
                className="focus-ring block w-full overflow-hidden rounded-lg"
                aria-label={`Open ${title} fullscreen`}
                onClick={() => openImmersive(0)}
              >
                <BlurhashImage
                  src={mediaUrl(cover.path)}
                  alt={title}
                  width={cover.width}
                  height={cover.height}
                  blurhash={cover.blurhash}
                  clamp={false}
                  priority
                  sizes="(max-width: 1024px) 100vw, 60vw"
                />
              </button>
            )}
          </div>

          <div className="flex min-w-0 flex-col gap-5 p-4 lg:p-6">
            <div className="flex items-start gap-2">
              <nav
                aria-label="Breadcrumb"
                className="flex min-w-0 flex-1 flex-wrap items-center gap-1.5 text-caption text-ink-3"
              >
                <span className="rounded-full bg-surface-2 px-2 py-0.5 text-micro uppercase tracking-widest">
                  {ENTITY_LABEL[type]}
                </span>
                {breadcrumbCollection ? (
                  <>
                    <span aria-hidden>·</span>
                    <Link
                      href={collectionHref(breadcrumbCollection.id)}
                      className="focus-ring truncate rounded-sm transition-colors dur-fast hover:text-ink"
                    >
                      {breadcrumbCollection.name}
                    </Link>
                  </>
                ) : null}
                {breadcrumbSubcollection ? (
                  <>
                    <span aria-hidden>/</span>
                    <Link
                      href={subcollectionHref(breadcrumbSubcollection.id)}
                      className="focus-ring truncate rounded-sm transition-colors dur-fast hover:text-ink"
                    >
                      {breadcrumbSubcollection.name}
                    </Link>
                  </>
                ) : null}
              </nav>

              <IconButton
                icon="more"
                label="More actions"
                size="sm"
                variant="ghost"
                onClick={() => setOverflow(true)}
              />
            </div>

            <div className="flex flex-col gap-2">
              <Heading className="font-display text-display3 text-ink">{title}</Heading>
              {description ? (
                <p className="whitespace-pre-wrap text-body text-ink-2">{description}</p>
              ) : null}
              <p className="text-caption text-ink-3">
                {payload.entity_type === 'item'
                  ? `Added ${longTimeAgo(payload.item.created_at)}`
                  : payload.entity_type === 'collection'
                    ? `${compactCount(payload.collection.item_count)} ${plural(payload.collection.item_count, 'item')} across ${compactCount(payload.collection.subcollection_count)} ${plural(payload.collection.subcollection_count, 'subcollection')}`
                    : payload.entity_type === 'subcollection'
                      ? `${compactCount(payload.subcollection.item_count)} ${plural(payload.subcollection.item_count, 'item')}`
                      : ''}
              </p>
            </div>

            <OwnerRow
              owner={owner}
              isOwner={isOwner}
              follows={viewer.follows}
              compact={variant === 'modal'}
            />

            <ActionBar
              type={type}
              id={id}
              title={title}
              seed={seedFromCloseup(payload)}
              className="border-y border-line-subtle py-2"
            />

            {tags.length > 0 ? (
              <ChipGroup label="Tags">
                {tags.map((tag) => (
                  <Chip key={tag} href={`${routes.search}?q=${encodeURIComponent(tag)}`}>
                    #{tag}
                  </Chip>
                ))}
              </ChipGroup>
            ) : null}

            {payload.entity_type === 'item' ? <ItemFacts item={payload.item} /> : null}

            {!user ? (
              <p className="rounded-md border border-line-subtle bg-surface-1 px-4 py-3 text-callout text-ink-2">
                <Link
                  href={routes.signUp}
                  className="focus-ring rounded-sm text-accent underline underline-offset-4"
                >
                  Create an account
                </Link>{' '}
                to save this to a shelf of your own.
              </p>
            ) : null}

            <CommentThread type={type} id={id} className="border-t border-line-subtle pt-5" />
          </div>
        </div>

        {childSubcollections.length > 0 ? (
          <ChildSection
            title="Subcollections"
            subtitle="Each one is likeable, saveable and repostable in its own right."
            cards={childSubcollections}
          />
        ) : null}

        {childItems.length > 0 ? (
          <ChildSection
            title={payload.entity_type === 'collection' ? 'Everything inside' : 'Items'}
            cards={childItems}
          />
        ) : null}

        {siblings.length > 0 ? (
          <ChildSection
            title="More from this shelf"
            cards={siblings}
            action={
              breadcrumbSubcollection ? (
                <Link
                  href={subcollectionHref(breadcrumbSubcollection.id)}
                  className="focus-ring rounded-sm text-label text-accent underline underline-offset-4"
                >
                  See all
                </Link>
              ) : null
            }
          />
        ) : null}

        {variant === 'modal' ? (
          <div className="border-t border-line-subtle p-4 lg:p-6">
            <Link
              href={entityHref(type, id)}
              className="focus-ring rounded-sm text-label text-accent underline underline-offset-4"
            >
              Open the full page
            </Link>
          </div>
        ) : null}
      </article>

      <ImmersiveViewer source={immersive} onClose={() => setImmersive(null)} />

      <OverflowSheet
        open={overflow}
        onClose={() => setOverflow(false)}
        type={type}
        id={id}
        title={title}
        owner={{
          id: owner.id,
          username: owner.username,
          displayName: owner.display_name,
        }}
        isOwner={isOwner}
      />
    </>
  );
}

function ChildSection({
  title,
  subtitle,
  cards,
  action,
}: {
  title: string;
  subtitle?: string;
  cards: TileCard[];
  action?: React.ReactNode;
}) {
  return (
    <section className="border-t border-line-subtle p-4 lg:p-6">
      <div className="mb-4 flex items-end gap-3">
        <div className="min-w-0 flex-1">
          <h2 className="font-display text-title1 text-ink">{title}</h2>
          {subtitle ? <p className="mt-1 text-caption text-ink-3">{subtitle}</p> : null}
        </div>
        {action}
      </div>
      <TileGrid cards={cards} showOwner={false} priorityCount={0} />
    </section>
  );
}
