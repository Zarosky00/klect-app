'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { cn } from '@/lib/cn';
import { compactCount, shortTimeAgo } from '@/lib/format';
import { conversationHref } from '@/lib/routes';
import { Avatar, AvatarStack } from '@/components/ui/Avatar';
import { EmptyState } from '@/components/ui/EmptyState';
import { Icon } from '@/components/ui/Icon';
import { conversationTitle, type ConversationSummary } from './queries';

/**
 * The DM index: unread badge, last-message preview, newest first.
 *
 * Ordering follows `conversations.last_message_at`, which a trigger maintains —
 * the client never sorts on data it computed itself.
 */
export function ConversationList({
  conversations,
  className,
}: {
  conversations: ConversationSummary[];
  className?: string;
}) {
  const pathname = usePathname();

  if (conversations.length === 0) {
    return (
      <div className={className}>
        <EmptyState
          icon="mail"
          title="No conversations"
          description="Open a collector's profile and press Message. One DM per pair, ever."
          compact
        />
      </div>
    );
  }

  return (
    <ul className={cn('flex flex-col', className)}>
      {conversations.map((summary) => {
        const href = conversationHref(summary.conversation.id);
        const active = pathname === href;
        const unread = summary.membership?.unread_count ?? 0;
        const title = conversationTitle(summary);
        const isGroup = summary.conversation.kind === 'group';
        const other = summary.others[0];

        return (
          <li key={summary.conversation.id}>
            <Link
              href={href}
              aria-current={active ? 'page' : undefined}
              className={cn(
                'focus-ring flex items-center gap-3 border-b border-line-subtle px-4 py-3',
                'transition-colors dur-fast ease-standard',
                active ? 'bg-surface-2' : 'hover:bg-surface-1',
              )}
            >
              {isGroup ? (
                <AvatarStack
                  people={summary.others.map((profile) => ({
                    id: profile.id,
                    avatar_path: profile.avatar_path,
                    display_name: profile.display_name,
                  }))}
                  max={3}
                />
              ) : (
                <Avatar
                  path={other?.avatar_path}
                  name={other?.display_name ?? title}
                  username={other?.username}
                  verified={other?.is_verified ?? false}
                  size="lg"
                />
              )}

              <span className="min-w-0 flex-1">
                <span className="flex items-baseline gap-2">
                  <span
                    className={cn(
                      'min-w-0 flex-1 truncate',
                      unread > 0 ? 'text-body-strong text-ink' : 'text-body text-ink',
                    )}
                  >
                    {title}
                  </span>
                  <span className="tabular shrink-0 text-micro text-ink-3">
                    {shortTimeAgo(summary.conversation.last_message_at)}
                  </span>
                </span>
                <span
                  className={cn(
                    'mt-0.5 block truncate text-caption',
                    unread > 0 ? 'text-ink-2' : 'text-ink-3',
                  )}
                >
                  {summary.conversation.last_message_preview ?? 'No messages yet'}
                </span>
              </span>

              {unread > 0 ? (
                <span
                  className="tabular grid min-w-6 shrink-0 place-items-center rounded-full bg-accent px-1.5 py-0.5 text-micro text-ink-on-accent"
                  aria-label={`${unread} unread`}
                >
                  {compactCount(unread)}
                </span>
              ) : summary.membership?.muted_until ? (
                <span className="shrink-0 text-ink-3" title="Muted">
                  <Icon name="eye" size="sm" />
                </span>
              ) : null}
            </Link>
          </li>
        );
      })}
    </ul>
  );
}
