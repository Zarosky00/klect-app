'use client';

import { useEffect, useState } from 'react';
import { BlurhashImage } from '@/components/ui/BlurhashImage';
import { EmptyState } from '@/components/ui/EmptyState';
import { ErrorState } from '@/components/ui/ErrorState';
import { Sheet } from '@/components/ui/Sheet';
import { SkeletonRow } from '@/components/ui/Skeleton';
import {
  listCollectionSummaries,
  listItemSummaries,
  subcollectionSummary,
  type EntitySummary,
} from '@/components/social/queries';
import { cn } from '@/lib/cn';
import { ENTITY_LABEL } from '@/lib/entities';
import { compactCount, plural } from '@/lib/format';
import { mediaUrl } from '@/lib/storage';
import { toKlectError } from '@/lib/errors';
import { useSession } from '@/providers/session-provider';

/**
 * Pick one of your own things to share into a post.
 *
 * The three levels of the hierarchy are all shareable — that symmetry is the
 * product — so the sheet lists all three, most recent first, and hands back one
 * `EntitySummary` the composer renders as the attachment card.
 */

const PER_GROUP = 12;

export interface EntityPickerSheetProps {
  open: boolean;
  onClose: () => void;
  onPick: (entity: EntitySummary) => void;
}

interface Loaded {
  collections: EntitySummary[];
  subcollections: EntitySummary[];
  items: EntitySummary[];
}

export function EntityPickerSheet({ open, onClose, onPick }: EntityPickerSheetProps) {
  const { supabase, user } = useSession();
  const [loaded, setLoaded] = useState<Loaded | null>(null);
  const [error, setError] = useState<unknown>(null);

  useEffect(() => {
    if (!open || loaded !== null || !user) return;
    let active = true;

    const load = async () => {
      setError(null);
      try {
        const [collections, items, subRows] = await Promise.all([
          listCollectionSummaries(supabase, user.id, { limit: PER_GROUP }),
          listItemSummaries(supabase, user.id, { limit: PER_GROUP }),
          supabase
            .from('subcollections')
            .select('*')
            .eq('user_id', user.id)
            .is('deleted_at', null)
            .is('hidden_at', null)
            .order('created_at', { ascending: false })
            .limit(PER_GROUP),
        ]);
        if (subRows.error) throw toKlectError(subRows.error);
        if (!active) return;
        setLoaded({
          collections,
          subcollections: (subRows.data ?? []).map(subcollectionSummary),
          items,
        });
      } catch (thrown) {
        if (active) setError(thrown);
      }
    };

    void load();
    return () => {
      active = false;
    };
  }, [loaded, open, supabase, user]);

  const empty =
    loaded !== null &&
    loaded.collections.length === 0 &&
    loaded.subcollections.length === 0 &&
    loaded.items.length === 0;

  return (
    <Sheet
      open={open}
      onClose={onClose}
      title="Share from your shelves"
      description="Attach a collection, a subcollection or an item to this post."
    >
      {error ? (
        <ErrorState error={error} compact onRetry={() => setLoaded(null)} />
      ) : loaded === null ? (
        <div className="flex flex-col gap-4">
          <SkeletonRow />
          <SkeletonRow />
          <SkeletonRow />
        </div>
      ) : empty ? (
        <EmptyState
          compact
          icon="grid"
          title="Nothing to share yet"
          description="Create a collection or add an item first, then share it into Pulse."
        />
      ) : (
        <div className="flex flex-col gap-6">
          <PickerGroup label="Items" entities={loaded.items} onPick={onPick} />
          <PickerGroup
            label="Subcollections"
            entities={loaded.subcollections}
            onPick={onPick}
          />
          <PickerGroup label="Collections" entities={loaded.collections} onPick={onPick} />
        </div>
      )}
    </Sheet>
  );
}

function PickerGroup({
  label,
  entities,
  onPick,
}: {
  label: string;
  entities: EntitySummary[];
  onPick: (entity: EntitySummary) => void;
}) {
  if (entities.length === 0) return null;
  return (
    <section aria-label={label}>
      <h3 className="mb-2 text-micro uppercase tracking-widest text-ink-3">{label}</h3>
      <ul className="flex flex-col gap-1">
        {entities.map((entity) => {
          const childLabel =
            entity.type === 'item'
              ? `${compactCount(entity.childCount)} ${plural(entity.childCount, 'photo')}`
              : `${compactCount(entity.childCount)} ${plural(entity.childCount, 'item')}`;
          return (
            <li key={entity.id}>
              <button
                type="button"
                onClick={() => onPick(entity)}
                className={cn(
                  'focus-ring flex w-full items-center gap-3 rounded-lg p-2 text-left',
                  'transition-colors dur-fast ease-standard hover:bg-surface-2',
                )}
              >
                <span className="w-12 shrink-0 overflow-hidden rounded-md border border-line-subtle">
                  <BlurhashImage
                    src={mediaUrl(entity.coverPath)}
                    alt=""
                    width={null}
                    height={null}
                    blurhash={entity.coverBlurhash}
                    fallbackAspect={1}
                    sizes="48px"
                  />
                </span>
                <span className="min-w-0 flex-1">
                  <span className="block truncate text-body-strong text-ink">
                    {entity.title}
                  </span>
                  <span className="block truncate text-caption text-ink-3">
                    {ENTITY_LABEL[entity.type]} · {childLabel}
                  </span>
                </span>
              </button>
            </li>
          );
        })}
      </ul>
    </section>
  );
}
