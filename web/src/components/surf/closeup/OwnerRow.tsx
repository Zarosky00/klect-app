'use client';

import Link from 'next/link';
import { Avatar } from '@/components/ui/Avatar';
import { Button } from '@/components/ui/Button';
import { cn } from '@/lib/cn';
import { compactCount, plural } from '@/lib/format';
import { profileHref } from '@/lib/routes';
import { useFollowState, useRealtimeProfile } from '@/providers/interactions-provider';
import { useSession } from '@/providers/session-provider';
import { useToast } from '@/providers/toast-provider';
import type { CloseupOwner } from '@/lib/types';

/**
 * The owner of whatever you are looking at, with an optimistic follow button.
 *
 * The follower count is live: it seeds from the payload, moves the instant the
 * button is pressed, reconciles with `toggle_follow`'s authoritative return, and
 * subscribes to `UPDATE` on the profile row so a follow from another device
 * lands here too.
 */
export function OwnerRow({
  owner,
  isOwner,
  follows,
  compact = false,
  className,
}: {
  owner: CloseupOwner;
  isOwner: boolean;
  follows: boolean;
  compact?: boolean;
  className?: string;
}) {
  const { user } = useSession();
  const { toast } = useToast();
  const follow = useFollowState(owner.id, {
    viewerFollows: follows,
    followerCount: owner.follower_count,
  });

  useRealtimeProfile(owner.id);

  return (
    <div className={cn('flex items-center gap-3', className)}>
      <Link
        href={profileHref(owner.username)}
        className="focus-ring flex min-w-0 flex-1 items-center gap-3 rounded-md py-1"
      >
        <Avatar
          path={owner.avatar_path}
          name={owner.display_name}
          username={owner.username}
          size={compact ? 'md' : 'lg'}
          verified={owner.is_verified}
        />
        <span className="min-w-0">
          <span className="block truncate font-display text-title2 text-ink">
            {owner.display_name}
          </span>
          <span className="block truncate text-caption text-ink-3">
            @{owner.username} · {compactCount(follow.followerCount)}{' '}
            {plural(follow.followerCount, 'follower')}
          </span>
        </span>
      </Link>

      {isOwner ? (
        <span className="rounded-full bg-surface-2 px-3 py-1 text-caption text-ink-3">
          Yours
        </span>
      ) : (
        <Button
          size="sm"
          variant={follow.following ? 'secondary' : 'primary'}
          loading={follow.pending}
          onClick={() => {
            if (!user) {
              toast({
                title: 'Sign in to follow',
                description: 'Following builds the feed that finds you collectors like you.',
                tone: 'accent',
                action: {
                  label: 'Sign in',
                  onClick: () => window.location.assign('/signin'),
                },
              });
              return;
            }
            follow.toggle();
          }}
        >
          {follow.following ? 'Following' : 'Follow'}
        </Button>
      )}
    </div>
  );
}
