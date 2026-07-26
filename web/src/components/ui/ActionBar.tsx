'use client';

import { useCallback, useState } from 'react';
import { cn } from '@/lib/cn';
import { entityHref, type EntityType } from '@/lib/entities';
import { SITE_URL } from '@/lib/env';
import type { SocialSeed } from '@/lib/interactions';
import { useEntitySocial } from '@/providers/interactions-provider';
import { useSession } from '@/providers/session-provider';
import { useToast } from '@/providers/toast-provider';
import { CountPill } from './CountPill';
import { IconButton } from './Button';
import { ReportDialog } from './ReportDialog';

/**
 * The one action bar. Same code path for a collection, a subcollection, an
 * item, a post or a comment — that symmetry is the product.
 *
 * "Hidden but easily accessible": at rest a surf card shows the photo and
 * nothing else; this bar fades in on hover (web) or lives behind the long-press
 * peek. In the closeup it is always visible.
 */
export type ActionBarVariant = 'bar' | 'overlay' | 'compact';

export interface ActionBarProps {
  type: EntityType;
  id: string;
  seed?: SocialSeed;
  variant?: ActionBarVariant;
  /** Title used in the share sheet and the report dialog. */
  title?: string;
  showViews?: boolean;
  showComment?: boolean;
  showShare?: boolean;
  showReport?: boolean;
  onComment?: () => void;
  className?: string;
}

export function ActionBar({
  type,
  id,
  seed,
  variant = 'bar',
  title,
  showViews = true,
  showComment = true,
  showShare = true,
  showReport = true,
  onComment,
  className,
}: ActionBarProps) {
  const social = useEntitySocial(type, id, seed);
  const { user } = useSession();
  const { toast, success, fromError } = useToast();
  const [reporting, setReporting] = useState(false);

  const compact = variant === 'compact';

  const requireAuth = useCallback((): boolean => {
    if (user) return true;
    toast({
      title: 'Sign in to do that',
      description: 'Collecting, liking and reposting need an account.',
      tone: 'accent',
      action: { label: 'Sign in', onClick: () => window.location.assign('/signin') },
    });
    return false;
  }, [toast, user]);

  const share = useCallback(async () => {
    const url = `${SITE_URL}${entityHref(type, id)}`;
    try {
      if (typeof navigator !== 'undefined' && navigator.share) {
        await navigator.share({ title: title ?? 'Klect', url });
        return;
      }
      await navigator.clipboard.writeText(url);
      success('Link copied');
    } catch (error) {
      // A cancelled share sheet throws AbortError; that is not a failure.
      if (error instanceof Error && error.name === 'AbortError') return;
      fromError(error);
    }
  }, [fromError, id, success, title, type]);

  return (
    <>
      <div
        className={cn(
          'flex items-center',
          compact ? 'gap-0.5' : 'gap-1',
          variant === 'overlay' &&
            'glass rounded-full border border-line px-1 py-0.5 shadow-mid',
          className,
        )}
      >
        <CountPill
          icon="heart"
          tone="like"
          count={social.likeCount}
          active={social.liked}
          compact={compact}
          label={social.liked ? 'Unlike' : 'Like'}
          onClick={() => {
            if (requireAuth()) social.like();
          }}
        />

        <CountPill
          icon="bookmark"
          tone="save"
          count={social.saveCount}
          active={social.saved}
          compact={compact}
          label={social.saved ? 'Remove from saved' : 'Save'}
          onClick={() => {
            if (requireAuth()) social.save();
          }}
        />

        <CountPill
          icon="repost"
          tone="repost"
          count={social.repostCount}
          active={social.reposted}
          compact={compact}
          label={social.reposted ? 'Undo repost' : 'Repost'}
          onClick={() => {
            if (requireAuth()) social.repost();
          }}
        />

        {showComment ? (
          <CountPill
            icon="comment"
            tone="comment"
            count={social.commentCount}
            compact={compact}
            label="Comments"
            readOnly={!onComment}
            {...(onComment ? { onClick: onComment } : {})}
          />
        ) : null}

        {showViews ? (
          <CountPill
            icon="eye"
            tone="view"
            count={social.viewCount}
            compact={compact}
            label={`${social.viewCount} views`}
            readOnly
            hideZero
          />
        ) : null}

        <span className="flex-1" />

        {showShare ? (
          <IconButton
            icon="share"
            label="Share"
            size="sm"
            variant="ghost"
            onClick={() => void share()}
          />
        ) : null}

        {showReport ? (
          <IconButton
            icon="flag"
            label="Report"
            size="sm"
            variant="ghost"
            onClick={() => {
              if (requireAuth()) setReporting(true);
            }}
          />
        ) : null}
      </div>

      <ReportDialog
        open={reporting}
        onClose={() => setReporting(false)}
        target={{ kind: 'entity', type, id }}
        {...(title === undefined ? {} : { subject: title })}
      />
    </>
  );
}
