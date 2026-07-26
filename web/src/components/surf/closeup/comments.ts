/**
 * Comment reads for the closeup thread. Isomorphic — no `'use client'` — so a
 * server component could prefetch a thread with the same function.
 *
 * `listComments` gives the rows; the author profiles come from one batched
 * `in()` lookup rather than a join, so the shape stays exactly the generated
 * row type and nothing here depends on PostgREST embedding inference.
 *
 * No count is ever computed here: `like_count` and `reply_count` are counter
 * columns kept correct by triggers (BACKEND_API §1).
 */
import { listComments, type Client } from '@/lib/api';
import type { EntityType } from '@/lib/entities';
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
  replyCount: number;
  createdAt: string;
  editedAt: string | null;
  /** True while an optimistic post is still in flight. */
  pending?: boolean;
}

export const MAX_COMMENT_DEPTH = 3;
export const MAX_COMMENT_LENGTH = 2000;

function toNode(row: CommentRow, authors: Map<string, CommentAuthor>): CommentNode {
  return {
    id: row.id,
    body: row.body,
    author: authors.get(row.author_id) ?? null,
    authorId: row.author_id,
    parentId: row.parent_id,
    depth: row.depth,
    likeCount: row.like_count,
    replyCount: row.reply_count,
    createdAt: row.created_at,
    editedAt: row.edited_at,
  };
}

export async function loadCommentThread(
  client: Client,
  type: EntityType,
  id: string,
  limit = 200,
): Promise<CommentNode[]> {
  const rows = (await listComments(client, type, id, { limit })).filter(
    (row) => row.hidden_at === null,
  );
  if (rows.length === 0) return [];

  const authorIds = [...new Set(rows.map((row) => row.author_id))];
  const { data } = await client
    .from('profiles')
    .select('id, username, display_name, avatar_path, is_verified')
    .in('id', authorIds);

  const authors = new Map<string, CommentAuthor>();
  for (const profile of data ?? []) authors.set(profile.id, profile);

  return rows.map((row) => toNode(row, authors));
}

export interface CommentTreeNode extends CommentNode {
  children: CommentTreeNode[];
}

/** Roots first, replies nested underneath, both in posting order. */
export function buildCommentTree(nodes: readonly CommentNode[]): CommentTreeNode[] {
  const byId = new Map<string, CommentTreeNode>();
  for (const node of nodes) byId.set(node.id, { ...node, children: [] });

  const roots: CommentTreeNode[] = [];
  for (const node of byId.values()) {
    const parent = node.parentId ? byId.get(node.parentId) : undefined;
    if (parent) parent.children.push(node);
    else roots.push(node);
  }

  const sort = (list: CommentTreeNode[]): void => {
    list.sort((a, b) => a.createdAt.localeCompare(b.createdAt));
    for (const child of list) sort(child.children);
  };
  sort(roots);

  return roots;
}
