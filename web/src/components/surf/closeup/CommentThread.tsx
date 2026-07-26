'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import Link from 'next/link';
import { Avatar } from '@/components/ui/Avatar';
import { Button } from '@/components/ui/Button';
import { ConfirmDialog } from '@/components/ui/ConfirmDialog';
import { CountPill } from '@/components/ui/CountPill';
import { EmptyState } from '@/components/ui/EmptyState';
import { ErrorState } from '@/components/ui/ErrorState';
import { Icon } from '@/components/ui/Icon';
import { ReportDialog } from '@/components/ui/ReportDialog';
import { SkeletonRow } from '@/components/ui/Skeleton';
import { TextArea } from '@/components/ui/TextField';
import { deleteComment } from '@/lib/api';
import { cn } from '@/lib/cn';
import type { EntityType } from '@/lib/entities';
import { longTimeAgo, shortTimeAgo } from '@/lib/format';
import { profileHref, routes } from '@/lib/routes';
import {
  useAddComment,
  useEntitySocial,
  useInteractionStore,
} from '@/providers/interactions-provider';
import { useSession } from '@/providers/session-provider';
import { useToast } from '@/providers/toast-provider';
import {
  buildCommentTree,
  loadCommentThread,
  MAX_COMMENT_DEPTH,
  MAX_COMMENT_LENGTH,
  type CommentNode,
  type CommentTreeNode,
} from './comments';

/**
 * The threaded comment thread, shared by the closeup and every public entity
 * page. Comments are a first-class entity type, so each one is likeable and
 * reportable through exactly the same machinery as an item.
 *
 * Posting is optimistic: the comment appears — and the entity's comment count
 * moves — the instant you hit post. If the round trip fails the row is removed,
 * the count is restored by the engine, and **your draft comes back**; text is
 * never lost (CHECKLIST C).
 */

export interface CommentThreadProps {
  type: EntityType;
  id: string;
  /** Focus the composer on mount — used when the closeup is opened via the
   *  comment count. */
  autoFocus?: boolean;
  className?: string;
}

let optimisticSeq = 0;

export function CommentThread({ type, id, autoFocus = false, className }: CommentThreadProps) {
  const { supabase, user, profile } = useSession();
  const { fromError, success } = useToast();
  const addComment = useAddComment();
  const store = useInteractionStore();

  const [nodes, setNodes] = useState<CommentNode[] | null>(null);
  const [error, setError] = useState<unknown>(null);
  const [draft, setDraft] = useState('');
  const [busy, setBusy] = useState(false);
  const [replyTo, setReplyTo] = useState<CommentNode | null>(null);
  const [reportTarget, setReportTarget] = useState<CommentNode | null>(null);
  const [deleteTarget, setDeleteTarget] = useState<CommentNode | null>(null);

  const composerRef = useRef<HTMLTextAreaElement | null>(null);

  const load = useCallback(async () => {
    setError(null);
    try {
      setNodes(await loadCommentThread(supabase, type, id));
    } catch (thrown) {
      setError(thrown);
    }
  }, [id, supabase, type]);

  useEffect(() => {
    void load();
  }, [load]);

  useEffect(() => {
    if (autoFocus) composerRef.current?.focus();
  }, [autoFocus]);

  const tree = useMemo(() => buildCommentTree(nodes ?? []), [nodes]);

  const post = useCallback(
    async (body: string, parent: CommentNode | null) => {
      const trimmed = body.trim();
      if (!trimmed) return;
      if (!user) return;

      optimisticSeq += 1;
      const temporaryId = `optimistic-${optimisticSeq}`;
      const optimistic: CommentNode = {
        id: temporaryId,
        body: trimmed,
        author: profile
          ? {
              id: profile.id,
              username: profile.username,
              display_name: profile.display_name,
              avatar_path: profile.avatar_path,
              is_verified: profile.is_verified,
            }
          : null,
        authorId: user.id,
        parentId: parent?.id ?? null,
        depth: parent ? parent.depth + 1 : 0,
        likeCount: 0,
        replyCount: 0,
        createdAt: new Date().toISOString(),
        editedAt: null,
        pending: true,
      };

      setBusy(true);
      setNodes((current) => [...(current ?? []), optimistic]);
      setDraft('');
      setReplyTo(null);

      const result = await addComment(type, id, trimmed, parent?.id);
      setBusy(false);

      if (!result) {
        // Failure: drop the optimistic row and give the words back.
        setNodes((current) => (current ?? []).filter((node) => node.id !== temporaryId));
        setDraft(trimmed);
        setReplyTo(parent);
        return;
      }

      setNodes((current) =>
        (current ?? []).map((node) =>
          node.id === temporaryId ? { ...node, id: result.id, pending: false } : node,
        ),
      );
      if (parent) {
        setNodes((current) =>
          (current ?? []).map((node) =>
            node.id === parent.id ? { ...node, replyCount: node.replyCount + 1 } : node,
          ),
        );
      }
    },
    [addComment, id, profile, type, user],
  );

  const removeComment = useCallback(
    async (node: CommentNode) => {
      setDeleteTarget(null);
      const snapshot = nodes ?? [];
      setNodes(snapshot.filter((entry) => entry.id !== node.id));
      try {
        const { count } = await deleteComment(supabase, node.id);
        store.setCommentCount(type, id, count);
        success('Comment deleted');
      } catch (thrown) {
        setNodes(snapshot);
        fromError(thrown);
      }
    },
    [fromError, id, nodes, store, success, supabase, type],
  );

  return (
    <section className={cn('flex flex-col gap-4', className)} aria-label="Comments">
      <h2 className="font-display text-title1 text-ink">Comments</h2>

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
            label="Add a comment"
            labelHidden
            rows={3}
            value={draft}
            maxLength={MAX_COMMENT_LENGTH}
            showCount
            placeholder={replyTo ? 'Write a reply…' : 'Say something about this…'}
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
              {replyTo ? 'Reply' : 'Comment'}
            </Button>
          </div>
        </form>
      ) : (
        <p className="rounded-md border border-line-subtle bg-surface-1 px-4 py-3 text-callout text-ink-2">
          <Link href={routes.signIn} className="focus-ring rounded-sm text-accent underline underline-offset-4">
            Sign in
          </Link>{' '}
          to join the conversation.
        </p>
      )}

      {error ? (
        <ErrorState error={error} compact onRetry={() => void load()} />
      ) : nodes === null ? (
        <div className="flex flex-col gap-4">
          <SkeletonRow />
          <SkeletonRow />
        </div>
      ) : tree.length === 0 ? (
        <EmptyState
          compact
          icon="comment"
          title="No comments yet"
          description="Be the first to say what you see in this."
        />
      ) : (
        <ol className="flex flex-col gap-5">
          {tree.map((node) => (
            <CommentBranch
              key={node.id}
              node={node}
              viewerId={user?.id ?? null}
              onReply={(target) => {
                setReplyTo(target);
                composerRef.current?.focus();
              }}
              onReport={setReportTarget}
              onDelete={setDeleteTarget}
            />
          ))}
        </ol>
      )}

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

interface CommentBranchProps {
  node: CommentTreeNode;
  viewerId: string | null;
  onReply: (node: CommentNode) => void;
  onReport: (node: CommentNode) => void;
  onDelete: (node: CommentNode) => void;
}

function CommentBranch({ node, viewerId, onReply, onReport, onDelete }: CommentBranchProps) {
  const social = useEntitySocial('comment', node.pending ? '' : node.id, {
    likeCount: node.likeCount,
  });
  const mine = viewerId !== null && viewerId === node.authorId;

  return (
    <li className={cn('flex flex-col gap-3', node.pending && 'opacity-[var(--k-opacity-hover)]')}>
      <article className="flex gap-3">
        <Link
          href={node.author ? profileHref(node.author.username) : '#'}
          className="focus-ring shrink-0 rounded-full"
          tabIndex={node.author ? 0 : -1}
        >
          <Avatar
            path={node.author?.avatar_path}
            name={node.author?.display_name}
            username={node.author?.username}
            size="sm"
            verified={node.author?.is_verified ?? false}
          />
        </Link>

        <div className="min-w-0 flex-1">
          <p className="flex flex-wrap items-baseline gap-x-2">
            <span className="text-body-strong text-ink">
              {node.author?.display_name ?? 'Collector'}
            </span>
            <span className="text-caption text-ink-3">
              @{node.author?.username ?? 'unknown'}
            </span>
            <time
              dateTime={node.createdAt}
              title={longTimeAgo(node.createdAt)}
              className="text-caption text-ink-3"
            >
              {node.pending ? 'posting…' : shortTimeAgo(node.createdAt)}
            </time>
          </p>

          <p className="mt-1 whitespace-pre-wrap break-words text-body text-ink-2">
            {node.body}
          </p>

          <div className="mt-1 flex items-center gap-1">
            <CountPill
              icon="heart"
              tone="like"
              compact
              count={social.likeCount}
              active={social.liked}
              label={social.liked ? 'Unlike comment' : 'Like comment'}
              disabled={node.pending}
              onClick={() => social.like()}
            />

            {node.depth < MAX_COMMENT_DEPTH ? (
              <button
                type="button"
                className="focus-ring rounded-full px-2 py-1 text-caption text-ink-3 transition-colors dur-fast hover:text-ink"
                onClick={() => onReply(node)}
                disabled={node.pending}
              >
                Reply
              </button>
            ) : null}

            {mine ? (
              <button
                type="button"
                className="focus-ring rounded-full px-2 py-1 text-caption text-ink-3 transition-colors dur-fast hover:text-danger"
                onClick={() => onDelete(node)}
                disabled={node.pending}
              >
                Delete
              </button>
            ) : (
              <button
                type="button"
                className="focus-ring rounded-full px-2 py-1 text-caption text-ink-3 transition-colors dur-fast hover:text-danger"
                onClick={() => onReport(node)}
                disabled={node.pending}
              >
                Report
              </button>
            )}
          </div>
        </div>
      </article>

      {node.children.length > 0 ? (
        <ol className="ml-5 flex flex-col gap-5 border-l border-line-subtle pl-4">
          {node.children.map((child) => (
            <CommentBranch
              key={child.id}
              node={child}
              viewerId={viewerId}
              onReply={onReply}
              onReport={onReport}
              onDelete={onDelete}
            />
          ))}
        </ol>
      ) : null}
    </li>
  );
}
