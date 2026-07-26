/**
 * Comment reads for the closeup thread. Isomorphic — no `'use client'` — so a
 * server component could prefetch a thread with the same function.
 *
 * `listComments` gives the rows; the author profiles come from one batched
 * `in()` lookup rather than a join, so the shape stays exactly the generated
 * row type and nothing here depends on PostgREST embedding inference. The
 * viewer's own likes over the page are seeded the same way — one batched read,
 * never one probe per comment.
 *
 * No count is ever computed here: `like_count` and `reply_count` are counter
 * columns kept correct by triggers (BACKEND_API §1).
 */
import { listComments, type Client } from '@/lib/api';
import type { EntityType } from '@/lib/entities';
import { toKlectError } from '@/lib/errors';
import type { CommentRow } from '@/lib/types';

export interface CommentAuthor {
  id: string;
  username: string;
  display_name: string;
  avatar_path: string | null;
  is_verified: boolean;
}

export interface CommentNode {
  id: string;
  body: string;
  author: CommentAuthor | null;
  authorId: string;
  parentId: string | null;
  depth: number;
  likeCount: number;
  /** Trigger-maintained counter columns — comments are full social citizens
   *  since migration 0021. */
  saveCount: number;
  repostCount: number;
  replyCount: number;
  createdAt: string;
  editedAt: string | null;
  /** Seeded from one batched read of the viewer's likes over this page. */
  viewerLiked: boolean;
  viewerSaved: boolean;
  viewerReposted: boolean;
  /** True while an optimistic post is still in flight. */
  pending?: boolean;
}

export const MAX_COMMENT_DEPTH = 3;
export const MAX_COMMENT_LENGTH = 2000;
export const COMMENT_PAGE_SIZE = 50;

export type CommentSort = 'top' | 'newest';

function toNode(
  row: CommentRow,
  authors: Map<string, CommentAuthor>,
  liked: ReadonlySet<string>,
  saved: ReadonlySet<string>,
  reposted: ReadonlySet<string>,
): CommentNode {
  return {
    id: row.id,
    body: row.body,
    author: authors.get(row.author_id) ?? null,
    authorId: row.author_id,
    parentId: row.parent_id,
    depth: row.depth,
    likeCount: row.like_count,
    saveCount: row.save_count,
    repostCount: row.repost_count,
    replyCount: row.reply_count,
    createdAt: row.created_at,
    editedAt: row.edited_at,
    viewerLiked: liked.has(row.id),
    viewerSaved: saved.has(row.id),
    viewerReposted: reposted.has(row.id),
  };
}

export interface CommentPage {
  nodes: CommentNode[];
  /** True when another `loadCommentThread` call could return more rows. */
  hasMore: boolean;
  /** Offset to pass for the next page. */
  nextOffset: number;
}

export async function loadCommentThread(
  client: Client,
  type: EntityType,
  id: string,
  options: { limit?: number; offset?: number; viewerId?: string | null } = {},
): Promise<CommentPage> {
  const limit = options.limit ?? COMMENT_PAGE_SIZE;
  const offset = options.offset ?? 0;

  const raw = await listComments(client, type, id, { limit, offset });
  const rows = raw.filter((row) => row.hidden_at === null);
  const hasMore = raw.length === limit;
  const nextOffset = offset + raw.length;

  if (rows.length === 0) return { nodes: [], hasMore, nextOffset };

  const authorIds = [...new Set(rows.map((row) => row.author_id))];
  const commentIds = rows.map((row) => row.id);

  // The viewer's likes/saves/reposts over the page, one batched read each —
  // never a probe per comment (comments are full social citizens since 0021).
  const none = Promise.resolve({ data: [] as Array<{ entity_id: string }>, error: null });
  const viewerRows = (table: 'likes' | 'saves' | 'reposts') =>
    options.viewerId
      ? client
          .from(table)
          .select('entity_id')
          .eq('user_id', options.viewerId)
          .eq('entity_type', 'comment')
          .in('entity_id', commentIds)
      : none;

  const [authorsResult, likesResult, savesResult, repostsResult] = await Promise.all([
    client
      .from('profiles')
      .select('id, username, display_name, avatar_path, is_verified')
      .in('id', authorIds),
    viewerRows('likes'),
    viewerRows('saves'),
    viewerRows('reposts'),
  ]);
  if (likesResult.error) throw toKlectError(likesResult.error);
  if (savesResult.error) throw toKlectError(savesResult.error);
  if (repostsResult.error) throw toKlectError(repostsResult.error);

  const authors = new Map<string, CommentAuthor>();
  for (const profile of authorsResult.data ?? []) authors.set(profile.id, profile);
  const liked = new Set((likesResult.data ?? []).map((row) => row.entity_id));
  const saved = new Set((savesResult.data ?? []).map((row) => row.entity_id));
  const reposted = new Set((repostsResult.data ?? []).map((row) => row.entity_id));

  return {
    nodes: rows.map((row) => toNode(row, authors, liked, saved, reposted)),
    hasMore,
    nextOffset,
  };
}

export interface CommentTreeNode extends CommentNode {
  children: CommentTreeNode[];
}

/**
 * Roots ordered by `sort` — Top (most liked) or Newest — with replies nested
 * underneath in posting order.
 */
export function buildCommentTree(
  nodes: readonly CommentNode[],
  sort: CommentSort = 'newest',
): CommentTreeNode[] {
  const byId = new Map<string, CommentTreeNode>();
  for (const node of nodes) byId.set(node.id, { ...node, children: [] });

  const roots: CommentTreeNode[] = [];
  for (const node of byId.values()) {
    const parent = node.parentId ? byId.get(node.parentId) : undefined;
    if (parent) parent.children.push(node);
    else roots.push(node);
  }

  roots.sort((a, b) =>
    sort === 'top'
      ? b.likeCount - a.likeCount || a.createdAt.localeCompare(b.createdAt)
      : b.createdAt.localeCompare(a.createdAt),
  );

  const sortChildren = (list: CommentTreeNode[]): void => {
    list.sort((a, b) => a.createdAt.localeCompare(b.createdAt));
    for (const child of list) sortChildren(child.children);
  };
  for (const root of roots) sortChildren(root.children);

  return roots;
}
