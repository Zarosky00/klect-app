'use client';

import { useCallback, useEffect, useState } from 'react';
import { cn } from '@/lib/cn';
import { ENTITY_LABEL } from '@/lib/entities';
import { compactCount, plural } from '@/lib/format';
import { mediaUrl } from '@/lib/storage';
import { BlurhashImage } from '@/components/ui/BlurhashImage';
import { Chip, ChipGroup } from '@/components/ui/Chip';
import { EmptyState } from '@/components/ui/EmptyState';
import { ErrorState } from '@/components/ui/ErrorState';
import { Sheet } from '@/components/ui/Sheet';
import { SkeletonRow } from '@/components/ui/Skeleton';
import { useSession } from '@/providers/session-provider';
import {
  listCollectionSummaries,
  listItemSummaries,
  type EntitySummary,
} from './queries';

/**
 * Picks something of yours to drop into a conversation. Collections and items
 * only — a subcollection is reachable one tap deeper from either.
 */
export function EntitySharePicker({
  open,
  onClose,
  onPick,
}: {
  open: boolean;
  onClose: () => void;
  onPick: (summary: EntitySummary) => void;
}) {
  const { supabase, user } = useSession();
  const [scope, setScope] = useState<'collections' | 'items'>('collections');
  const [summaries, setSummaries] = useState<EntitySummary[]>([]);
  const [loading, setLoading] = useState(false);
  const [failure, setFailure] = useState<unknown>(null);

  const load = useCallback(async () => {
    if (!user) return;
    setLoading(true);
    setFailure(null);
    try {
      setSummaries(
        scope === 'collections'
          ? await listCollectionSummaries(supabase, user.id, { limit: 40 })
          : await listItemSummaries(supabase, user.id, { limit: 40 }),
      );
    } catch (error) {
      setFailure(error);
    } finally {
      setLoading(false);
    }
  }, [scope, supabase, user]);

  useEffect(() => {
    if (open) void load();
  }, [load, open]);

  return (
    <Sheet
      open={open}
      onClose={onClose}
      title="Share from your shelves"
      description="It arrives as a rich card, not a bare link."
      side="bottom"
    >
      <ChipGroup label="What to share" className="pb-4">
        <Chip selected={scope === 'collections'} onClick={() => setScope('collections')}>
          Collections
        </Chip>
        <Chip selected={scope === 'items'} onClick={() => setScope('items')}>
          Items
        </Chip>
      </ChipGroup>

      {failure ? (
        <ErrorState error={failure} onRetry={() => void load()} compact />
      ) : loading ? (
        <div className="flex flex-col gap-3">
          {Array.from({ length: 5 }, (_, index) => (
            <SkeletonRow key={index} />
          ))}
        </div>
      ) : summaries.length === 0 ? (
        <EmptyState
          icon="grid"
          title="Nothing to share yet"
          description="Create a collection and it will show up here."
          compact
        />
      ) : (
        <ul className="flex flex-col gap-1">
          {summaries.map((summary) => (
            <li key={`${summary.type}:${summary.id}`}>
              <button
                type="button"
                onClick={() => {
                  onPick(summary);
                  onClose();
                }}
                className={cn(
                  'focus-ring flex w-full items-center gap-3 rounded-lg px-2 py-2 text-left',
                  'transition-colors dur-fast ease-standard hover:bg-surface-2',
                )}
              >
                <span className="size-12 shrink-0 overflow-hidden rounded-md">
                  <BlurhashImage
                    src={mediaUrl(summary.coverPath)}
                    alt=""
                    blurhash={summary.coverBlurhash}
                    fallbackAspect={1}
                    sizes="48px"
                  />
                </span>
                <span className="min-w-0 flex-1">
                  <span className="block truncate text-body-strong text-ink">
                    {summary.title}
                  </span>
                  <span className="block truncate text-caption text-ink-3">
                    {ENTITY_LABEL[summary.type]} · {compactCount(summary.childCount)}{' '}
                    {plural(summary.childCount, summary.type === 'item' ? 'photo' : 'item')}
                  </span>
                </span>
              </button>
            </li>
          ))}
        </ul>
      )}
    </Sheet>
  );
}
