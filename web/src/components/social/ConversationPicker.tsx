'use client';

import { useCallback, useEffect, useState } from 'react';
import { cn } from '@/lib/cn';
import { shortTimeAgo } from '@/lib/format';
import { Avatar } from '@/components/ui/Avatar';
import { EmptyState } from '@/components/ui/EmptyState';
import { ErrorState } from '@/components/ui/ErrorState';
import { Icon } from '@/components/ui/Icon';
import { Sheet } from '@/components/ui/Sheet';
import { SkeletonRow } from '@/components/ui/Skeleton';
import { useSession } from '@/providers/session-provider';
import {
  conversationTitle,
  listConversationSummaries,
  type ConversationSummary,
} from './queries';

/**
 * Picks a conversation to drop something into — the send-to-a-friend half of
 * the share chooser. Mirrors `EntitySharePicker`'s structure: same Sheet, same
 * load/error/empty states, one row per pickable thing.
 *
 * The picker stays open while the send is in flight (`busyId` marks the row),
 * so a failed insert leaves the person exactly where they were.
 */
export function ConversationPicker({
  open,
  onClose,
  onPick,
  busyId = null,
}: {
  open: boolean;
  onClose: () => void;
  onPick: (summary: ConversationSummary) => void;
  /** Conversation a send is in flight to — its row shows a spinner. */
  busyId?: string | null;
}) {
  const { supabase, user } = useSession();
  const [summaries, setSummaries] = useState<ConversationSummary[]>([]);
  const [loading, setLoading] = useState(false);
  const [failure, setFailure] = useState<unknown>(null);

  const load = useCallback(async () => {
    if (!user) return;
    setLoading(true);
    setFailure(null);
    try {
      const all = await listConversationSummaries(supabase, user.id);
      // Left conversations are unpostable; RLS would reject the insert anyway.
      setSummaries(all.filter((summary) => summary.membership?.left_at == null));
    } catch (error) {
      setFailure(error);
    } finally {
      setLoading(false);
    }
  }, [supabase, user]);

  useEffect(() => {
    if (open) void load();
  }, [load, open]);

  return (
    <Sheet
      open={open}
      onClose={onClose}
      title="Send to a friend"
      description="It arrives in chat as a rich card, not a bare link."
      side="bottom"
    >
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
          icon="mail"
          title="No conversations yet"
          description="Start a chat from someone's profile and they will show up here."
          compact
        />
      ) : (
        <ul className="flex flex-col gap-1">
          {summaries.map((summary) => {
            const other = summary.others[0];
            const title = conversationTitle(summary);
            const busy = busyId === summary.conversation.id;
            return (
              <li key={summary.conversation.id}>
                <button
                  type="button"
                  disabled={busyId !== null}
                  onClick={() => onPick(summary)}
                  className={cn(
                    'focus-ring flex w-full items-center gap-3 rounded-lg px-2 py-2 text-left',
                    'transition-colors dur-fast ease-standard hover:bg-surface-2',
                    'disabled:opacity-[var(--k-opacity-disabled)]',
                  )}
                >
                  <Avatar
                    path={summary.conversation.avatar_path ?? other?.avatar_path}
                    name={title}
                    username={other?.username}
                    verified={summary.others.length === 1 && (other?.is_verified ?? false)}
                  />
                  <span className="min-w-0 flex-1">
                    <span className="block truncate text-body-strong text-ink">{title}</span>
                    <span className="block truncate text-caption text-ink-3">
                      {summary.conversation.last_message_preview ??
                        (other ? `@${other.username}` : 'Group')}
                    </span>
                  </span>
                  {busy ? (
                    <Icon name="spinner" size="md" className="shrink-0 text-ink-3" />
                  ) : summary.conversation.last_message_at ? (
                    <span className="shrink-0 text-micro text-ink-3">
                      {shortTimeAgo(summary.conversation.last_message_at)}
                    </span>
                  ) : null}
                </button>
              </li>
            );
          })}
        </ul>
      )}
    </Sheet>
  );
}
