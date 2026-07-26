'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useCallback, useEffect, useState, type ReactNode } from 'react';
import { cn } from '@/lib/cn';
import { routes } from '@/lib/routes';
import { Icon } from '@/components/ui/Icon';
import { useSession } from '@/providers/session-provider';
import { ConversationList } from './ConversationList';
import { listConversationSummaries, type ConversationSummary } from './queries';

/**
 * Two panes on desktop, one at a time on mobile.
 *
 * The index is kept live by two subscriptions rather than polling: `UPDATE` on
 * `conversations` carries the fresh preview and `last_message_at`, and `UPDATE`
 * on your own `conversation_members` row carries the unread count. Both are
 * RLS-filtered on the stream, so nothing you cannot see ever arrives.
 */
export function MessagesShell({
  initialConversations,
  viewerId,
  children,
}: {
  initialConversations: ConversationSummary[];
  viewerId: string;
  children: ReactNode;
}) {
  const pathname = usePathname();
  const { supabase } = useSession();
  const [conversations, setConversations] = useState(initialConversations);

  const onDetail = pathname !== routes.messages;

  const reload = useCallback(() => {
    void listConversationSummaries(supabase, viewerId)
      .then(setConversations)
      .catch(() => {
        // The index is a convenience; a failed refresh keeps the last good list.
      });
  }, [supabase, viewerId]);

  useEffect(() => {
    const channel = supabase
      .channel(`dm-index:${viewerId}`)
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'conversations' },
        () => reload(),
      )
      .on(
        'postgres_changes',
        {
          event: 'UPDATE',
          schema: 'public',
          table: 'conversation_members',
          filter: `user_id=eq.${viewerId}`,
        },
        () => reload(),
      )
      .subscribe();

    return () => {
      void supabase.removeChannel(channel);
    };
  }, [reload, supabase, viewerId]);

  // Coming back to the index should show the freshest previews.
  useEffect(() => {
    if (!onDetail) reload();
  }, [onDetail, reload]);

  return (
    /* The app shell puts a top bar above and a bottom bar below on mobile, and
       neither on desktop — so the pane height is the viewport minus exactly
       what the chrome already took, including both safe-area insets. */
    <div className="flex h-[calc(100dvh-var(--k-topbar-h)-var(--k-bottombar-h)-env(safe-area-inset-top)-env(safe-area-inset-bottom))] min-h-0 md:h-dvh">
      <aside
        aria-label="Conversations"
        className={cn(
          'min-h-0 w-full shrink-0 flex-col border-r border-line-subtle md:flex md:w-80 lg:w-96',
          onDetail ? 'hidden md:flex' : 'flex',
        )}
      >
        <header className="flex items-center justify-between gap-2 border-b border-line-subtle px-4 py-4">
          <h1 className="font-display text-title1 text-ink">Messages</h1>
          <Link
            href={routes.matches}
            className="focus-ring inline-flex items-center gap-1.5 rounded-md px-2 py-1 text-label text-ink-2 hover:text-ink"
            title="Find someone to message"
          >
            <Icon name="plus" size="sm" />
            New
          </Link>
        </header>

        <div className="min-h-0 flex-1 overflow-y-auto">
          <ConversationList conversations={conversations} />
        </div>
      </aside>

      <section
        className={cn(
          'min-h-0 min-w-0 flex-1 flex-col',
          onDetail ? 'flex' : 'hidden md:flex',
        )}
      >
        {children}
      </section>
    </div>
  );
}
