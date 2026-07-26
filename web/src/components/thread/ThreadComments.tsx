'use client';

import Link from 'next/link';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Avatar } from '@/components/ui/Avatar';
import { Button } from '@/components/ui/Button';
import { ConfirmDialog } from '@/components/ui/ConfirmDialog';
import { EmptyState } from '@/components/ui/EmptyState';
import { ErrorState } from '@/components/ui/ErrorState';
import { Icon } from '@/components/ui/Icon';
import { ReportDialog } from '@/components/ui/ReportDialog';
import { SkeletonRow } from '@/components/ui/Skeleton';
import { TextArea } from '@/components/ui/TextField';
import { deleteComment, getPostThread } from '@/lib/api';
import { cn } from '@/lib/cn';
import { longTimeAgo, shortTimeAgo } from '@/lib/format';
import { postHref, profileHref, routes } from '@/lib/routes';
import type { PulseActor, ThreadComment, ThreadSort } from '@/lib/types';
import { useAddComment, useInteractionStore } from '@/providers/interactions-provider';
import { useSession } from '@/providers/session-provider';
import { useToast } from '@/providers/toast-provider';
import { CommentActionBar } from './CommentActionBar';

/**
 * The discussion under a post — `get_post_thread`'s paged comments with
 * Top/Newest sort, a reply-first composer, optimistic insert, and the full
 * comment action bar (comments are social citizens since 0021).
 *
 * Comments arrive flat with `parent_id` + `depth`; replies render indented in
 * server order, X-style, rather than as a recursive tree — the thread page is
 * a stream, not an outline.
 */

const MAX_COMMENT_LENGTH = 2000;
const PAGE_SIZE = 30;

/** Local row: a server comment, or an optimistic one still in flight. */
type ThreadRow = ThreadComment & { pending?: boolean };

interface SortState {
  rows: ThreadRow[];
  hasMore: boolean;
  initialised: boolean;
}

export interface ThreadCommentsProps {
  postId: string;
  initialComments: ThreadComment[];
  initialHasMore: boolean;
  initialSort: ThreadSort;
  /** Bump to focus the reply composer (the post's comment pill does this). */
  focusSignal?: number;
  className?: string;
}

let optimisticSeq = 0;

export function ThreadComments({
  postId,
  initialComments,
  initialHasMore,
  initialSort,
  focusSignal = 0,
  className,
}: ThreadCommentsProps) {
  const { supabase, user, profile } = useSession();
  const { fromError, success } = useToast();
  const addComment = useAddComment();
  const store = useInteractionStore();

  const [sort, setSort] = useState<ThreadSort>(initialSort);
  const [states, setStates] = useState<Record<ThreadSort, SortState>>(() => ({
    top: {
      rows: initialSort === 'top' ? initialComments : [],
      hasMore: initialSort === 'top' ? initialHasMore : false,
      initialised: initialSort === 'top',
    },
    new: {
      rows: initialSort === 'new' ? initialComments : [],
      hasMore: initialSort === 'new' ? initialHasMore : false,
      initialised: initialSort === 'new',
    },
  }));
  const [error, setError] = useState<unknown>(null);
  const [loading, setLoading] = useState(false);
  const [draft, setDraft] = useState('');
  const [busy, setBusy] = useState(false);
  const [replyTo, setReplyTo] = useState<ThreadRow | null>(null);
  const [reportTarget, setReportTarget] = useState<ThreadRow | null>(null);
  const [deleteTarget, setDeleteTarget] = useState<ThreadRow | null>(null);

  const composerRef = useRef<HTMLTextAreaElement | null>(null);

  const state = states[sort];

  useEffect(() => {
    if (focusSignal > 0) {
      composerRef.current?.focus();
      composerRef.current?.scrollIntoView({ block: 'center' });
    }
  }, [focusSignal]);

  /** First page of a sort, or the next page when `before` is passed. */
  const fetchPage = useCallback(
    async (target: ThreadSort, before?: string) => {
      setLoading(true);
      setError(null);
      try {
        const thread = await getPostThread(supabase, postId, {
          limit: PAGE_SIZE,
          sort: target,
          ...(before === undefined ? {} : { before }),
        });
        const page = thread?.comments ?? [];
        const hasMore = thread?.has_more ?? false;
        setStates((current) => {
          const existing = before === undefined ? [] : current[target].rows;
          const known = new Set(existing.map((row) => row.id));
          const fresh = page.filter((row) => !known.has(row.id));
          return {
            ...current,
            [target]: {
              rows: [...existing, ...fresh],
              hasMore,
              initialised: true,
            },
          };
        });
      } catch (thrown) {
        setError(thrown);
      } finally {
        setLoading(false);
      }
    },
    [postId, supabase],
  );

  const switchSort = useCallback(
    (next: ThreadSort) => {
      setSort(next);
      if (!states[next].initialised) void fetchPage(next);
    },
    [fetchPage, states],
  );

  const loadMore = useCallback(() => {
    // `p_before` is a created_at keyset in both sorts — pass the min on screen.
    let before: string | undefined;
    for (const row of state.rows) {
      if (row.pending) continue;
      if (before === undefined || row.created_at < before) before = row.created_at;
    }
    void fetchPage(sort, before);
  }, [fetchPage, sort, state.rows]);

  const post = useCallback(
    async (body: string, parent: ThreadRow | null) => {
      const trimmed = body.trim();
      if (!trimmed || !user) return;

      optimisticSeq += 1;
      const temporaryId = `optimistic-thread-${optimisticSeq}`;
      const author: PulseActor | null = profile
        ? {
            id: profile.id,
            username: profile.username,
            display_name: profile.display_name,
            avatar_path: profile.avatar_path,
            is_verified: profile.is_verified,
          }
        : null;
      const optimistic: ThreadRow = {
        id: temporaryId,
        body: trimmed,
        author,
        created_at: new Date().toISOString(),
        like_count: 0,
        save_count: 0,
        repost_count: 0,
        reply_count: 0,
        parent_id: parent?.id ?? null,
        depth: parent ? parent.depth + 1 : 0,
        viewer: { liked: false, saved: false, reposted: false },
        pending: true,
      };

      setBusy(true);
      // A reply slots in right under its parent; a new root comment leads.
      setStates((current) => {
        const rows = current[sort].rows;
        let next: ThreadRow[];
        if (parent) {
          const at = rows.findIndex((row) => row.id === parent.id);
          next =
            at < 0
              ? [optimistic, ...rows]
              : [...rows.slice(0, at + 1), optimistic, ...rows.slice(at + 1)];
        } else {
          next = [optimistic, ...rows];
        }
        return { ...current, [sort]: { ...current[sort], rows: next } };
      });
      setDraft('');
      setReplyTo(null);

      const result = await addComment('post', postId, trimmed, parent?.id);
      setBusy(false);

      if (!result) {
        // Failure: drop the optimistic row and give the words back.
        setStates((current) => ({
          ...current,
          [sort]: {
            ...current[sort],
            rows: current[sort].rows.filter((row) => row.id !== temporaryId),
          },
        }));
        setDraft(trimmed);
        setReplyTo(parent);
        return;
      }

      setStates((current) => ({
        ...current,
        [sort]: {
          ...current[sort],
          rows: current[sort].rows.map((row) =>
            row.id === temporaryId ? { ...row, id: result.id, pending: false } : row,
          ),
        },
      }));
    },
    [addComment, postId, profile, sort, user],
  );

  const removeComment = useCallback(
    async (row: ThreadRow) => {
      setDeleteTarget(null);
      const snapshot = states;
      setStates((current) => ({
        top: {
          ...current.top,
          rows: current.top.rows.filter((entry) => entry.id !== row.id),
        },
        new: {
          ...current.new,
          rows: current.new.rows.filter((entry) => entry.id !== row.id),
        },
      }));
      try {
        const { count } = await deleteComment(supabase, row.id);
        store.setCommentCount('post', postId, count);
        success('Comment deleted');
      } catch (thrown) {
        setStates(snapshot);
        fromError(thrown);
      }
    },
    [fromError, postId, states, store, success, supabase],
  );

  const viewerId = user?.id ?? null;
  const sharePath = postHref(postId);

  return (
    <section className={cn('flex flex-col gap-4', className)} aria-label="Comments">
      <div className="flex items-center gap-3">
        <h2 className="min-w-0 flex-1 font-display text-title1 text-ink">Comments</h2>
        <div
          role="group"
          aria-label="Sort comments"
          className="flex items-center gap-0.5 rounded-full border border-line-subtle bg-surface-1 p-0.5"
        >
          {(['top', 'new'] as const).map((candidate) => (
            <button
              key={candidate}
              type="button"
              aria-pressed={sort === candidate}
              onClick={() => switchSort(candidate)}
              className={cn(
                'focus-ring rounded-full px-3 py-1 text-caption transition-colors dur-fast ease-standard',
                sort === candidate ? 'bg-surface-3 text-ink' : 'text-ink-3 hover:text-ink-2',
              )}
            >
              {candidate === 'top' ? 'Top' : 'Newest'}
            </button>
          ))}
        </div>
      </div>

      {user ? (
        <form
          className="flex flex-col gap-2"
          onSubmit={(event) => {
            event.preventDefault();
            void post(draft, replyTo);
          }}
        >
          {replyTo ? (
            <p className="flex items-center gap-2 text-caption text-ink-2">
              <Icon name="comment" size="xs" />
              Replying to @{replyTo.author?.username ?? 'collector'}
              <button
                type="button"
                className="focus-ring rounded-sm text-accent underline underline-offset-4"
                onClick={() => setReplyTo(null)}
              >
                Cancel
              </button>
            </p>
          ) : null}

          <TextArea
            ref={composerRef}
            label="Post your reply"
            labelHidden
            rows={2}
            value={draft}
            maxLength={MAX_COMMENT_LENGTH}
            showCount
            placeholder={replyTo ? 'Write a reply…' : 'Post your reply…'}
            onChange={(event) => setDraft(event.target.value)}
            onKeyDown={(event) => {
              if ((event.metaKey || event.ctrlKey) && event.key === 'Enter') {
                event.preventDefault();
                void post(draft, replyTo);
              }
            }}
          />

          <div className="flex items-center justify-end gap-3">
            <span className="text-caption text-ink-3">⌘/Ctrl + Enter to post</span>
            <Button type="submit" size="sm" loading={busy} disabled={!draft.trim()}>
              Reply
            </Button>
          </div>
        </form>
      ) : (
        <p className="rounded-md border border-line-subtle bg-surface-1 px-4 py-3 text-callout text-ink-2">
          <Link
            href={routes.signIn}
            className="focus-ring rounded-sm text-accent underline underline-offset-4"
          >
            Sign in
          </Link>{' '}
          to join the conversation.
        </p>
      )}

      {error && state.rows.length === 0 ? (
        <ErrorState error={error} compact onRetry={() => void fetchPage(sort)} />
      ) : !state.initialised && loading ? (
        <div className="flex flex-col gap-4">
          <SkeletonRow />
          <SkeletonRow />
        </div>
      ) : state.rows.length === 0 ? (
        <EmptyState
          compact
          icon="comment"
          title="No comments yet"
          description="Be the first to say what you see in this."
        />
      ) : (
        <ol className="flex flex-col gap-5">
          {state.rows.map((row) => {
            const mine = viewerId !== null && viewerId === (row.author?.id ?? null);
            return (
              <li
                key={row.id}
                className={cn(
                  'flex gap-3',
                  row.depth === 1 && 'ml-6',
                  row.depth >= 2 && 'ml-12',
                  row.pending && 'opacity-[var(--k-opacity-hover)]',
                )}
              >
                <Link
                  href={row.author ? profileHref(row.author.username) : '#'}
                  className="focus-ring h-fit shrink-0 rounded-full"
                  tabIndex={row.author ? 0 : -1}
                >
                  <Avatar
                    path={row.author?.avatar_path}
                    name={row.author?.display_name}
                    username={row.author?.username}
                    size="sm"
                    verified={row.author?.is_verified ?? false}
                  />
                </Link>

                <div className="min-w-0 flex-1">
                  <p className="flex flex-wrap items-baseline gap-x-2">
                    <span className="text-body-strong text-ink">
                      {row.author?.display_name ?? 'Collector'}
                    </span>
                    <span className="text-caption text-ink-3">
                      @{row.author?.username ?? 'unknown'}
                    </span>
                    <time
                      dateTime={row.created_at}
                      title={longTimeAgo(row.created_at)}
                      className="text-caption text-ink-3"
                    >
                      {row.pending ? 'posting…' : shortTimeAgo(row.created_at)}
                    </time>
                  </p>

                  <p className="mt-1 whitespace-pre-wrap break-words text-body text-ink-2">
                    {row.body}
                  </p>

                  <div className="mt-1 flex flex-wrap items-center gap-1">
                    <CommentActionBar
                      id={row.pending ? '' : row.id}
                      seed={{
                        likeCount: row.like_count,
                        saveCount: row.save_count,
                        repostCount: row.repost_count,
                        viewerLiked: row.viewer.liked,
                        viewerSaved: row.viewer.saved,
                        viewerReposted: row.viewer.reposted,
                      }}
                      sharePath={sharePath}
                      shareTitle={row.body.slice(0, 60)}
                      onReply={() => {
                        setReplyTo(row);
                        composerRef.current?.focus();
                      }}
                      disabled={row.pending ?? false}
                    />

                    {mine ? (
                      <button
                        type="button"
                        className="focus-ring rounded-full px-2 py-1 text-caption text-ink-3 transition-colors dur-fast hover:text-danger"
                        onClick={() => setDeleteTarget(row)}
                        disabled={row.pending}
                      >
                        Delete
                      </button>
                    ) : (
                      <button
                        type="button"
                        className="focus-ring rounded-full px-2 py-1 text-caption text-ink-3 transition-colors dur-fast hover:text-danger"
                        onClick={() => setReportTarget(row)}
                        disabled={row.pending}
                      >
                        Report
                      </button>
                    )}
                  </div>
                </div>
              </li>
            );
          })}
        </ol>
      )}

      {state.hasMore && state.initialised ? (
        <div className="flex justify-center">
          <Button variant="ghost" size="sm" loading={loading} onClick={loadMore}>
            Load more comments
          </Button>
        </div>
      ) : null}

      <ReportDialog
        open={reportTarget !== null}
        onClose={() => setReportTarget(null)}
        target={{ kind: 'entity', type: 'comment', id: reportTarget?.id ?? '' }}
        subject={reportTarget?.body.slice(0, 60)}
      />

      <ConfirmDialog
        open={deleteTarget !== null}
        onCancel={() => setDeleteTarget(null)}
        onConfirm={() => {
          if (deleteTarget) void removeComment(deleteTarget);
        }}
        title="Delete this comment?"
        description="It disappears for everyone. This cannot be undone."
        confirmLabel="Delete"
        destructive
      />
    </section>
  );
}
