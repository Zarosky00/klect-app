'use client';

import { useCallback, useState } from 'react';
import dynamic from 'next/dynamic';
import { cn } from '@/lib/cn';
import { type EntityType } from '@/lib/entities';
import type { SocialSeed } from '@/lib/interactions';
import type { EngagementTab } from '@/lib/types';
import { useEntitySocial } from '@/providers/interactions-provider';
import { useSession } from '@/providers/session-provider';
import { useToast } from '@/providers/toast-provider';
import { CountPill } from './CountPill';
import { Icon } from './Icon';
import { IconButton } from './Button';
import { useEscape } from './overlay';

/**
 * The report flow (Modal + framer-motion + the reports API) rides on every
 * ActionBar — which is every tile in the masonry. Loading it on first use
 * keeps all of that out of the surf bundle. The share chooser gets the same
 * treatment: it pulls in the messaging queries.
 */
const ReportDialog = dynamic(
  () => import('./ReportDialog').then((module) => module.ReportDialog),
  { ssr: false },
);
const ShareMenu = dynamic(
  () => import('@/components/social/ShareMenu').then((module) => module.ShareMenu),
  { ssr: false },
);
const EngagementDialog = dynamic(
  () => import('@/components/social/EngagementDialog').then((module) => module.EngagementDialog),
  { ssr: false },
);

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
  /**
   * When provided, the repost pill opens an X-style chooser — Repost / Quote /
   * Undo — instead of toggling directly, and Quote calls this. Pulse passes it;
   * surf cards keep the one-tap toggle.
   */
  onQuote?: () => void;
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
  onQuote,
  className,
}: ActionBarProps) {
  const social = useEntitySocial(type, id, seed);
  const { user } = useSession();
  const { toast } = useToast();
  const [reporting, setReporting] = useState(false);
  const [sharing, setSharing] = useState(false);
  /** Latches on first tap: mounts the lazy chunk and keeps it mounted
      afterwards so its close animation still runs. */
  const [reportRequested, setReportRequested] = useState(false);
  const [shareRequested, setShareRequested] = useState(false);
  const [choosing, setChoosing] = useState(false);
  const [engagementTab, setEngagementTab] = useState<EngagementTab | null>(null);

  const openReport = useCallback(() => {
    setReportRequested(true);
    setReporting(true);
  }, []);

  const openShare = useCallback(() => {
    setShareRequested(true);
    setSharing(true);
  }, []);

  useEscape(choosing, () => setChoosing(false));

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

  return (
    <>
      <div
        className={cn(
          'flex items-center',
          compact ? 'gap-0.5' : 'gap-1',
          // Flat token fill, not the `glass` utility: this variant mounts on
          // every tile on touch, and a per-tile backdrop-filter re-blurs the
          // feed on every scroll frame. Glass stays on the two chrome bars.
          variant === 'overlay' &&
            'rounded-full border border-line bg-glass px-1 py-0.5 shadow-mid',
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
          {...(social.likeCount > 0
            ? {
                onCountClick: () => setEngagementTab('like'),
                countLabel: `${social.likeCount} likes, view accounts`,
              }
            : {})}
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

        {onQuote ? (
          <span className="relative inline-flex">
            <CountPill
              icon="repost"
              tone="repost"
              count={social.repostCount}
              active={social.reposted}
              compact={compact}
              label={social.reposted ? 'Repost options' : 'Repost or quote'}
              aria-haspopup="menu"
              aria-expanded={choosing}
              onClick={() => {
                if (requireAuth()) setChoosing((open) => !open);
              }}
              onCountClick={() => setEngagementTab('repost')}
              countLabel={`${social.repostCount} reposts and ${social.quoteCount} quotes, view engagement`}
            />
            {choosing ? (
              <>
                {/* Invisible scrim: any click outside the menu dismisses it. */}
                <button
                  type="button"
                  aria-label="Close repost options"
                  tabIndex={-1}
                  className="fixed inset-0 z-raised cursor-default"
                  onClick={() => setChoosing(false)}
                />
                <div
                  role="menu"
                  aria-label="Repost options"
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
                      'text-callout transition-colors dur-fast ease-standard hover:bg-surface-2',
                      social.reposted ? 'text-danger' : 'text-ink',
                    )}
                    onClick={() => {
                      setChoosing(false);
                      social.repost();
                    }}
                  >
                    <Icon name="repost" size="sm" />
                    {social.reposted ? 'Undo repost' : 'Repost'}
                  </button>
                  <button
                    type="button"
                    role="menuitem"
                    className={cn(
                      'focus-ring flex w-full items-center gap-2.5 px-3 py-2 text-left',
                      'text-callout text-ink transition-colors dur-fast ease-standard hover:bg-surface-2',
                    )}
                    onClick={() => {
                      setChoosing(false);
                      onQuote();
                    }}
                  >
                    <Icon name="comment" size="sm" />
                    Quote
                  </button>
                </div>
              </>
            ) : null}
          </span>
        ) : (
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
            onCountClick={() => setEngagementTab('repost')}
            countLabel={`${social.repostCount} reposts and ${social.quoteCount} quotes, view engagement`}
          />
        )}

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
            onClick={openShare}
          />
        ) : null}

        {showReport ? (
          <IconButton
            icon="flag"
            label="Report"
            size="sm"
            variant="ghost"
            onClick={() => {
              if (requireAuth()) openReport();
            }}
          />
        ) : null}
      </div>

      {reportRequested ? (
        <ReportDialog
          open={reporting}
          onClose={() => setReporting(false)}
          target={{ kind: 'entity', type, id }}
          {...(title === undefined ? {} : { subject: title })}
        />
      ) : null}

      {shareRequested ? (
        <ShareMenu
          open={sharing}
          onClose={() => setSharing(false)}
          type={type}
          id={id}
          title={title}
        />
      ) : null}

      {engagementTab ? (
        <EngagementDialog
          open
          onClose={() => setEngagementTab(null)}
          type={type}
          id={id}
          initialTab={engagementTab}
          initialSummary={{
            like_count: social.likeCount,
            repost_count: social.repostCount,
            quote_count: social.quoteCount,
          }}
        />
      ) : null}
    </>
  );
}
