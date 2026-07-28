'use client';

import { useCallback, useState } from 'react';
import { Button, type ButtonSize } from '@/components/ui/Button';
import { useFollowState } from '@/providers/interactions-provider';
import { useSession } from '@/providers/session-provider';
import { useToast } from '@/providers/toast-provider';

/**
 * Optimistic follow. The count moves on click and reconciles with what
 * `toggle_follow` returns — the same engine the like/save/repost pills use, so
 * a follower count on a profile header and one inside a match card can never
 * disagree.
 */
export interface FollowButtonProps {
  userId: string;
  /** Server-rendered follower count and viewer state. */
  followerCount?: number;
  following: boolean;
  size?: ButtonSize;
  block?: boolean;
  className?: string;
}

export function FollowButton({
  userId,
  followerCount,
  following: initialFollowing,
  size = 'md',
  block = false,
  className,
}: FollowButtonProps) {
  const { user } = useSession();
  const { toast } = useToast();
  const [hovering, setHovering] = useState(false);

  const state = useFollowState(userId, {
    ...(followerCount === undefined ? {} : { followerCount }),
    viewerFollows: initialFollowing,
  });

  const isSelf = user?.id === userId;

  const onClick = useCallback(() => {
    if (!user) {
      toast({
        title: 'Sign in to follow',
        description: 'Following builds the Pulse feed and sharpens your matches.',
        tone: 'accent',
        action: { label: 'Sign in', onClick: () => window.location.assign('/signin') },
      });
      return;
    }
    state.toggle();
  }, [state, toast, user]);

  if (isSelf) return null;

  const label = state.following ? (hovering ? 'Unfollow' : 'Following') : 'Follow';

  return (
    <Button
      variant={state.following ? 'secondary' : 'primary'}
      size={size}
      block={block}
      onClick={onClick}
      onMouseEnter={() => setHovering(true)}
      onMouseLeave={() => setHovering(false)}
      onFocus={() => setHovering(true)}
      onBlur={() => setHovering(false)}
      aria-pressed={state.following}
      iconLeft={state.following ? 'check' : 'plus'}
      className={className}
    >
      {label}
    </Button>
  );
}
