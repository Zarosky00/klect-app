'use client';

import { useCallback, useState } from 'react';
import { CountPill } from '@/components/ui/CountPill';
import { Icon } from '@/components/ui/Icon';
import { IconButton } from '@/components/ui/Button';
import { useEscape } from '@/components/ui/overlay';
import { cn } from '@/lib/cn';
import { SITE_URL } from '@/lib/env';
import type { SocialSeed } from '@/lib/interactions';
import { useEntitySocial } from '@/providers/interactions-provider';
import { useSession } from '@/providers/session-provider';
import { useToast } from '@/providers/toast-provider';

/**
 * The comment action bar (W3): like · save · repost (Repost/Undo) · reply ·
 * share (copy link / system). Comments are full social citizens since
 * migration 0021 — `toggle_save`/`toggle_repost` with `entity_type='comment'`
 * bump real counter columns, so this is exactly the same optimistic machinery
 * every other entity uses, at comment size.
 */
export interface CommentActionBarProps {
  /** The comment id. Empty string while an optimistic row is in flight. */
  id: string;
  seed?: SocialSeed;
  /** Absolute-path deep link to the discussion this comment lives in. */
  sharePath: string;
  shareTitle?: string | undefined;
  onReply?: (() => void) | undefined;
  disabled?: boolean;
  className?: string;
}

export function CommentActionBar({
  id,
  seed,
  sharePath,
  shareTitle,
  onReply,
  disabled = false,
  className,
}: CommentActionBarProps) {
  const social = useEntitySocial('comment', id, seed);
  const { user } = useSession();
  const { toast, success, fromError } = useToast();
  const [sharing, setSharing] = useState(false);

  useEscape(sharing, () => setSharing(false));

  const requireAuth = useCallback((): boolean => {
    if (user) return true;
    toast({
      title: 'Sign in to do that',
      description: 'Liking, saving and reposting need an account.',
      tone: 'accent',
      action: { label: 'Sign in', onClick: () => window.location.assign('/signin') },
    });
    return false;
  }, [toast, user]);

  const url = `${SITE_URL}${sharePath}`;

  const copyLink = useCallback(async () => {
    setSharing(false);
    try {
      await navigator.clipboard.writeText(url);
      success('Link copied');
    } catch (error) {
      fromError(error);
    }
  }, [fromError, success, url]);

  const systemShare = useCallback(async () => {
    setSharing(false);
    try {
      await navigator.share({ title: shareTitle ?? 'Klect', url });
    } catch (error) {
      // A cancelled share sheet throws AbortError; that is not a failure.
      if (error instanceof Error && error.name === 'AbortError') return;
      fromError(error);
    }
  }, [fromError, shareTitle, url]);

  const canSystemShare =
    typeof navigator !== 'undefined' && typeof navigator.share === 'function';

  return (
    <div className={cn('flex items-center gap-0.5', className)}>
      <CountPill
        icon="heart"
        tone="like"
        compact
        count={social.likeCount}
        active={social.liked}
        label={social.liked ? 'Unlike comment' : 'Like comment'}
        disabled={disabled}
        onClick={() => {
          if (requireAuth()) social.like();
        }}
      />

      <CountPill
        icon="bookmark"
        tone="save"
        compact
        count={social.saveCount}
        active={social.saved}
        label={social.saved ? 'Remove comment from saved' : 'Save comment'}
        disabled={disabled}
        onClick={() => {
          if (requireAuth()) social.save();
        }}
      />

      <CountPill
        icon="repost"
        tone="repost"
        compact
        count={social.repostCount}
        active={social.reposted}
        label={social.reposted ? 'Undo repost' : 'Repost comment'}
        disabled={disabled}
        onClick={() => {
          if (requireAuth()) social.repost();
        }}
      />

      {onReply ? (
        <button
          type="button"
          className={cn(
            'focus-ring rounded-full px-2 py-1 text-caption text-ink-3',
            'transition-colors dur-fast hover:text-ink',
            'disabled:pointer-events-none disabled:opacity-[var(--k-opacity-disabled)]',
          )}
          onClick={onReply}
          disabled={disabled}
        >
          Reply
        </button>
      ) : null}

      <span className="relative inline-flex">
        <IconButton
          icon="share"
          label="Share comment"
          size="sm"
          variant="ghost"
          disabled={disabled}
          aria-haspopup="menu"
          aria-expanded={sharing}
          onClick={() => setSharing((open) => !open)}
        />
        {sharing ? (
          <>
            {/* Invisible scrim: any click outside the menu dismisses it. */}
            <button
              type="button"
              aria-label="Close share options"
              tabIndex={-1}
              className="fixed inset-0 z-raised cursor-default"
              onClick={() => setSharing(false)}
            />
            <div
              role="menu"
              aria-label="Share options"
              className={cn(
                'absolute left-0 top-full z-sheet mt-1 w-48 overflow-hidden',
                'rounded-lg border border-line bg-surface-1 py-1 shadow-high',
              )}
            >
              <button
                type="button"
                role="menuitem"
                className={cn(
                  'focus-ring flex w-full items-center gap-2.5 px-3 py-2 text-left',
                  'text-callout text-ink transition-colors dur-fast ease-standard hover:bg-surface-2',
                )}
                onClick={() => void copyLink()}
              >
                <Icon name="link" size="sm" />
                Copy link
              </button>
              {canSystemShare ? (
                <button
                  type="button"
                  role="menuitem"
                  className={cn(
                    'focus-ring flex w-full items-center gap-2.5 px-3 py-2 text-left',
                    'text-callout text-ink transition-colors dur-fast ease-standard hover:bg-surface-2',
                  )}
                  onClick={() => void systemShare()}
                >
                  <Icon name="share" size="sm" />
                  Share via…
                </button>
              ) : null}
            </div>
          </>
        ) : null}
      </span>
    </div>
  );
}
