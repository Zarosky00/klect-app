/**
 * KLECT data access — one typed wrapper per RPC in `docs/BACKEND_API.md`,
 * plus the handful of table reads the shell needs (SEO metadata, the admin
 * guard, messaging).
 *
 * Every function takes the Supabase client as its first argument, so the same
 * code path serves a Server Component (`createClient()` from
 * `@/lib/supabase/server`) and a Client Component (`createClient()` from
 * `@/lib/supabase/client`).
 *
 * Two rules this file exists to enforce:
 *   · counts are read from counter columns and from RPC return values — never
 *     COUNT(*) in the client;
 *   · every failure becomes a `KlectError` with a `kind` the UI can branch on.
 */
import type { PostgrestError, SupabaseClient } from '@supabase/supabase-js';
import type { Database, Json } from '@/lib/database.types';
import type {
  AppRole,
  EntityType,
  ModAction,
  ReportReason,
  ReportStatus,
} from '@/lib/entities';
import { isSurfaceEntityType } from '@/lib/entities';
import { toKlectError } from '@/lib/errors';
import type {
  AddCommentResult,
  AdminMetrics,
  AdminReport,
  AdminUserDetail,
  AuditLogRow,
  CloseupPayload,
  CollectionRow,
  CommentRow,
  ConversationRow,
  DeleteCommentResult,
  ItemRow,
  MatchPerson,
  MessageRow,
  NotificationRow,
  ProfileRow,
  PulseEntry,
  PulseMode,
  SearchResults,
  SubcollectionRow,
  SubmitReportResult,
  SurfCard,
  SurfCardRaw,
  SurfFilter,
  ToggleResult,
} from '@/lib/types';
import { EMPTY_SEARCH_RESULTS } from '@/lib/types';

export type Client = SupabaseClient<Database>;

/* ── plumbing ─────────────────────────────────────────────────────────────── */

function unwrap<T>(result: { data: T | null; error: PostgrestError | null }): T {
  if (result.error) throw toKlectError(result.error);
  if (result.data === null) {
    throw toKlectError({ code: 'PGRST116', message: 'No rows returned' });
  }
  return result.data;
}

function unwrapNullable<T>(result: { data: T | null; error: PostgrestError | null }): T | null {
  if (result.error) throw toKlectError(result.error);
  return result.data;
}

/** RPCs that return `jsonb` come back as `Json`; assert the shape we documented. */
function asJson<T>(value: unknown): T {
  return value as T;
}

function toggleResult(value: unknown): ToggleResult {
  const raw = value as { active?: unknown; count?: unknown } | null;
  return {
    active: Boolean(raw?.active),
    count: Number(raw?.count ?? 0),
  };
}

/* ── interactions ─────────────────────────────────────────────────────────────
   All idempotent. Apply the delta optimistically, fire, then overwrite local
   state with what comes back. A double-fire cannot corrupt the count. */

export async function toggleLike(
  client: Client,
  type: EntityType,
  id: string,
): Promise<ToggleResult> {
  const { data, error } = await client.rpc('toggle_like', { p_type: type, p_id: id });
  if (error) throw toKlectError(error);
  return toggleResult(data);
}

export async function toggleSave(
  client: Client,
  type: EntityType,
  id: string,
  note?: string,
): Promise<ToggleResult> {
  const { data, error } = await client.rpc('toggle_save', {
    p_type: type,
    p_id: id,
    ...(note === undefined ? {} : { p_note: note }),
  });
  if (error) throw toKlectError(error);
  return toggleResult(data);
}

export async function toggleRepost(
  client: Client,
  type: EntityType,
  id: string,
  quote?: string,
): Promise<ToggleResult> {
  const { data, error } = await client.rpc('toggle_repost', {
    p_type: type,
    p_id: id,
    ...(quote === undefined ? {} : { p_quote: quote }),
  });
  if (error) throw toKlectError(error);
  return toggleResult(data);
}

/** Returns the *target's* follower count. */
export async function toggleFollow(client: Client, userId: string): Promise<ToggleResult> {
  const { data, error } = await client.rpc('toggle_follow', { p_user: userId });
  if (error) throw toKlectError(error);
  return toggleResult(data);
}

/** Deduped per viewer per day, server-side. Returns the new view count. */
export async function recordView(
  client: Client,
  type: EntityType,
  id: string,
): Promise<number> {
  const { data, error } = await client.rpc('record_view', { p_type: type, p_id: id });
  if (error) throw toKlectError(error);
  return Number(data ?? 0);
}

export async function addComment(
  client: Client,
  type: EntityType,
  id: string,
  body: string,
  parentId?: string,
): Promise<AddCommentResult> {
  const { data, error } = await client.rpc('add_comment', {
    p_type: type,
    p_id: id,
    p_body: body,
    ...(parentId === undefined ? {} : { p_parent: parentId }),
  });
  if (error) throw toKlectError(error);
  const raw = data as { id?: string; count?: number } | null;
  return { id: String(raw?.id ?? ''), count: Number(raw?.count ?? 0) };
}

export async function deleteComment(
  client: Client,
  commentId: string,
): Promise<DeleteCommentResult> {
  const { data, error } = await client.rpc('delete_comment', { p_comment: commentId });
  if (error) throw toKlectError(error);
  return { count: Number((data as { count?: number } | null)?.count ?? 0) };
}

export interface SubmitReportInput {
  reason: ReportReason;
  entityType?: EntityType;
  entityId?: string;
  userId?: string;
  messageId?: string;
  details?: string;
}

/** Reporting the same target twice returns `already_reported`, never an error. */
export async function submitReport(
  client: Client,
  input: SubmitReportInput,
): Promise<SubmitReportResult> {
  const { data, error } = await client.rpc('submit_report', {
    p_reason: input.reason,
    ...(input.entityType === undefined ? {} : { p_type: input.entityType }),
    ...(input.entityId === undefined ? {} : { p_id: input.entityId }),
    ...(input.userId === undefined ? {} : { p_user: input.userId }),
    ...(input.messageId === undefined ? {} : { p_message: input.messageId }),
    ...(input.details === undefined ? {} : { p_details: input.details }),
  });
  if (error) throw toKlectError(error);
  const raw = data as { id?: string; already_reported?: boolean } | null;
  return {
    id: String(raw?.id ?? ''),
    already_reported: Boolean(raw?.already_reported),
  };
}

/* ── feeds & discovery ────────────────────────────────────────────────────── */

/** Drops rows the composite type allows to be null but the grid cannot render. */
export function normaliseSurfCard(raw: SurfCardRaw): SurfCard | null {
  if (!isSurfaceEntityType(raw.entity_type) || !raw.entity_id || !raw.owner_id) return null;
  return {
    entity_type: raw.entity_type,
    entity_id: raw.entity_id,
    owner_id: raw.owner_id,
    username: raw.username ?? '',
    display_name: raw.display_name ?? '',
    avatar_path: raw.avatar_path,
    is_verified: raw.is_verified ?? false,
    title: raw.title ?? '',
    subtitle: raw.subtitle,
    cover_path: raw.cover_path,
    cover_blurhash: raw.cover_blurhash,
    width: raw.width,
    height: raw.height,
    accent_color: raw.accent_color,
    like_count: raw.like_count ?? 0,
    save_count: raw.save_count ?? 0,
    repost_count: raw.repost_count ?? 0,
    comment_count: raw.comment_count ?? 0,
    view_count: raw.view_count ?? 0,
    child_count: raw.child_count ?? 0,
    created_at: raw.created_at ?? new Date(0).toISOString(),
    score: raw.score ?? 0,
    viewer_liked: raw.viewer_liked ?? false,
    viewer_saved: raw.viewer_saved ?? false,
    viewer_reposted: raw.viewer_reposted ?? false,
    viewer_follows: raw.viewer_follows ?? false,
  };
}

export interface SurfFeedParams {
  limit?: number;
  offset?: number;
  /**
   * A stable per-user string. It jitters ranking deterministically, so two
   * accounts never see the same order while one account's pagination stays
   * consistent across pages. Pass the same seed for every page of a session.
   */
  seed?: string;
  filter?: SurfFilter;
}

export async function surfFeed(
  client: Client,
  params: SurfFeedParams = {},
): Promise<SurfCard[]> {
  const { data, error } = await client.rpc('surf_feed', {
    p_limit: params.limit ?? 30,
    p_offset: params.offset ?? 0,
    ...(params.seed === undefined ? {} : { p_seed: params.seed }),
    ...(params.filter === undefined ? {} : { p_filter: params.filter }),
  });
  if (error) throw toKlectError(error);
  const rows = (data ?? []) as SurfCardRaw[];
  return rows
    .map(normaliseSurfCard)
    .filter((card): card is SurfCard => card !== null);
}

export async function pulseFeed(
  client: Client,
  params: { limit?: number; before?: string; mode?: PulseMode } = {},
): Promise<PulseEntry[]> {
  const { data, error } = await client.rpc('pulse_feed', {
    p_limit: params.limit ?? 25,
    ...(params.before === undefined ? {} : { p_before: params.before }),
    ...(params.mode === undefined ? {} : { p_mode: params.mode }),
  });
  if (error) throw toKlectError(error);
  return asJson<PulseEntry[]>(data ?? []);
}

/** One uploaded photo, described for `create_post`'s `p_media`. */
export interface PostMediaDescriptor {
  /** Bucket-relative key — MUST start with the uploader's uid. */
  storage_path: string;
  width?: number | null;
  height?: number | null;
  blurhash?: string | null;
  dominant_color?: string | null;
  mime_type?: string | null;
  bytes?: number | null;
  alt_text?: string | null;
  position?: number | null;
}

export interface CreatePostInput {
  body?: string;
  /** Share a collection/subcollection/item, or quote a post (`entityType: 'post'`). */
  entityType?: EntityType;
  entityId?: string;
  media?: PostMediaDescriptor[];
  replyTo?: string;
}

/**
 * THE insert path for posts — direct INSERT on `posts` was revoked in
 * migration 0018. Returns the post's full pulse envelope so the stream can
 * prepend it verbatim, media and embedded target included.
 */
export async function createPost(client: Client, input: CreatePostInput): Promise<PulseEntry> {
  const { data, error } = await client.rpc('create_post', {
    p_body: input.body ?? '',
    ...(input.entityType === undefined ? {} : { p_entity_type: input.entityType }),
    ...(input.entityId === undefined ? {} : { p_entity_id: input.entityId }),
    ...(input.media === undefined ? {} : { p_media: input.media as unknown as Json }),
    ...(input.replyTo === undefined ? {} : { p_reply_to: input.replyTo }),
  });
  if (error) throw toKlectError(error);
  return asJson<PulseEntry>(data);
}

/** The single-tap detail payload. Shape varies by `entity_type`. */
export async function getCloseup(
  client: Client,
  type: EntityType,
  id: string,
): Promise<CloseupPayload | null> {
  const { data, error } = await client.rpc('get_closeup', { p_type: type, p_id: id });
  if (error) throw toKlectError(error);
  if (!data || typeof data !== 'object') return null;
  const payload = asJson<CloseupPayload>(data);
  return payload.entity_id ? payload : null;
}

export async function searchAll(
  client: Client,
  query: string,
  limit = 20,
): Promise<SearchResults> {
  if (!query.trim()) return EMPTY_SEARCH_RESULTS;
  const { data, error } = await client.rpc('search_all', { p_q: query, p_limit: limit });
  if (error) throw toKlectError(error);
  const raw = asJson<Partial<SearchResults>>(data ?? {});
  return {
    people: raw.people ?? [],
    collections: raw.collections ?? [],
    items: raw.items ?? [],
    tags: raw.tags ?? [],
  };
}

/** Collectors ranked by taste overlap. Recomputes server-side when stale. */
export async function getMatches(client: Client, limit = 20): Promise<MatchPerson[]> {
  const { data, error } = await client.rpc('get_matches', { p_limit: limit });
  if (error) throw toKlectError(error);
  return asJson<MatchPerson[]>(data ?? []);
}

/* ── messaging ────────────────────────────────────────────────────────────── */

/** One DM per pair, ever. Throws `messages_blocked` if they don't accept DMs. */
export async function startDm(client: Client, otherUserId: string): Promise<string> {
  const { data, error } = await client.rpc('start_dm', { p_other: otherUserId });
  if (error) throw toKlectError(error);
  return String(data);
}

export async function markConversationRead(
  client: Client,
  conversationId: string,
): Promise<void> {
  const { error } = await client.rpc('mark_conversation_read', {
    p_conversation: conversationId,
  });
  if (error) throw toKlectError(error);
}

/** `null` ids marks everything read. Returns how many rows changed. */
export async function markNotificationsRead(
  client: Client,
  ids?: string[],
): Promise<number> {
  const { data, error } = await client.rpc('mark_notifications_read', {
    ...(ids === undefined ? {} : { p_ids: ids }),
  });
  if (error) throw toKlectError(error);
  return Number(data ?? 0);
}

/* ── admin ─────────────────────────────────────────────────────────────────
   Every one of these re-checks `is_staff()` / `is_admin()` server-side, so the
   client guard is UX, never security. */

export async function adminMetrics(client: Client): Promise<AdminMetrics> {
  const { data, error } = await client.rpc('admin_metrics');
  if (error) throw toKlectError(error);
  return asJson<AdminMetrics>(data);
}

export async function adminListReports(
  client: Client,
  params: { status?: ReportStatus; limit?: number; offset?: number } = {},
): Promise<AdminReport[]> {
  const { data, error } = await client.rpc('admin_list_reports', {
    p_status: params.status ?? 'open',
    p_limit: params.limit ?? 50,
    p_offset: params.offset ?? 0,
  });
  if (error) throw toKlectError(error);
  return asJson<AdminReport[]>(data ?? []);
}

/** Resolving one report auto-resolves every other open report on the same target. */
export async function adminResolveReport(
  client: Client,
  params: {
    reportId: string;
    action: ModAction;
    reason?: string;
    suspendDays?: number;
  },
): Promise<unknown> {
  const { data, error } = await client.rpc('admin_resolve_report', {
    p_report: params.reportId,
    p_action: params.action,
    ...(params.reason === undefined ? {} : { p_reason: params.reason }),
    ...(params.suspendDays === undefined ? {} : { p_suspend_days: params.suspendDays }),
  });
  if (error) throw toKlectError(error);
  return data;
}

export async function adminModerateEntity(
  client: Client,
  params: { type: EntityType; id: string; hidden: boolean; reason?: string },
): Promise<unknown> {
  const { data, error } = await client.rpc('admin_moderate_entity', {
    p_type: params.type,
    p_id: params.id,
    p_hidden: params.hidden,
    ...(params.reason === undefined ? {} : { p_reason: params.reason }),
  });
  if (error) throw toKlectError(error);
  return data;
}

export async function adminSetUserState(
  client: Client,
  params: { userId: string; suspended: boolean; days?: number; reason?: string },
): Promise<unknown> {
  const { data, error } = await client.rpc('admin_set_user_state', {
    p_user: params.userId,
    p_suspended: params.suspended,
    ...(params.days === undefined ? {} : { p_days: params.days }),
    ...(params.reason === undefined ? {} : { p_reason: params.reason }),
  });
  if (error) throw toKlectError(error);
  return data;
}

export async function adminSetVerified(
  client: Client,
  userId: string,
  verified: boolean,
): Promise<unknown> {
  const { data, error } = await client.rpc('admin_set_verified', {
    p_user: userId,
    p_verified: verified,
  });
  if (error) throw toKlectError(error);
  return data;
}

/** Superadmin only. */
export async function adminSetRole(
  client: Client,
  params: { userId: string; role: AppRole; grant?: boolean },
): Promise<unknown> {
  const { data, error } = await client.rpc('admin_set_role', {
    p_user: params.userId,
    p_role: params.role,
    ...(params.grant === undefined ? {} : { p_grant: params.grant }),
  });
  if (error) throw toKlectError(error);
  return data;
}

export async function adminUserDetail(
  client: Client,
  userId: string,
): Promise<AdminUserDetail> {
  const { data, error } = await client.rpc('admin_user_detail', { p_user: userId });
  if (error) throw toKlectError(error);
  return asJson<AdminUserDetail>(data);
}

export async function adminAuditLog(
  client: Client,
  params: { limit?: number; offset?: number } = {},
): Promise<AuditLogRow[]> {
  const limit = params.limit ?? 50;
  const offset = params.offset ?? 0;
  const { data, error } = await client
    .from('audit_log')
    .select('*')
    .order('created_at', { ascending: false })
    .range(offset, offset + limit - 1);
  if (error) throw toKlectError(error);
  return data ?? [];
}

/* ── viewer & profiles ────────────────────────────────────────────────────── */

const STAFF_ROLES: readonly AppRole[] = ['moderator', 'admin', 'superadmin'];

export async function getViewerRoles(client: Client): Promise<AppRole[]> {
  const {
    data: { user },
  } = await client.auth.getUser();
  if (!user) return [];
  const { data, error } = await client
    .from('user_roles')
    .select('role')
    .eq('user_id', user.id);
  if (error) throw toKlectError(error);
  return (data ?? []).map((row) => row.role);
}

export function rolesAreStaff(roles: readonly AppRole[]): boolean {
  return roles.some((role) => STAFF_ROLES.includes(role));
}

export async function getViewerProfile(client: Client): Promise<ProfileRow | null> {
  const {
    data: { user },
  } = await client.auth.getUser();
  if (!user) return null;
  return unwrapNullable(
    await client.from('profiles').select('*').eq('id', user.id).maybeSingle(),
  );
}

export async function getProfileByUsername(
  client: Client,
  username: string,
): Promise<ProfileRow | null> {
  return unwrapNullable(
    await client.from('profiles').select('*').eq('username', username).maybeSingle(),
  );
}

export async function getProfileById(
  client: Client,
  id: string,
): Promise<ProfileRow | null> {
  return unwrapNullable(
    await client.from('profiles').select('*').eq('id', id).maybeSingle(),
  );
}

export async function usernameAvailable(client: Client, username: string): Promise<boolean> {
  const { data, error } = await client
    .from('profiles')
    .select('id')
    .eq('username', username)
    .maybeSingle();
  if (error) throw toKlectError(error);
  return data === null;
}

export type ProfileUpdate = Database['public']['Tables']['profiles']['Update'];

export async function updateProfile(
  client: Client,
  userId: string,
  patch: ProfileUpdate,
): Promise<ProfileRow> {
  return unwrap(
    await client.from('profiles').update(patch).eq('id', userId).select('*').single(),
  );
}

/** Marks onboarding finished. Called at the end of the 3-step flow. */
export async function completeOnboarding(
  client: Client,
  userId: string,
  patch: ProfileUpdate = {},
): Promise<ProfileRow> {
  return updateProfile(client, userId, { ...patch, onboarded_at: new Date().toISOString() });
}

/**
 * A cold-start substitute for `get_matches`: a brand-new account has no taste
 * vector yet, so onboarding suggests the most-followed public collectors instead.
 */
export async function listSuggestedCollectors(
  client: Client,
  params: { excludeUserId?: string; limit?: number } = {},
): Promise<ProfileRow[]> {
  let query = client
    .from('profiles')
    .select('*')
    .eq('account_visibility', 'public')
    .eq('is_suspended', false)
    .order('follower_count', { ascending: false })
    .order('collection_count', { ascending: false })
    .limit(params.limit ?? 12);
  if (params.excludeUserId) query = query.neq('id', params.excludeUserId);
  const { data, error } = await query;
  if (error) throw toKlectError(error);
  return data ?? [];
}

/* ── entity reads (SEO metadata, deep links) ──────────────────────────────── */

export async function getCollection(
  client: Client,
  id: string,
): Promise<CollectionRow | null> {
  return unwrapNullable(
    await client
      .from('collections')
      .select('*')
      .eq('id', id)
      .is('deleted_at', null)
      .maybeSingle(),
  );
}

export async function getSubcollection(
  client: Client,
  id: string,
): Promise<SubcollectionRow | null> {
  return unwrapNullable(
    await client
      .from('subcollections')
      .select('*')
      .eq('id', id)
      .is('deleted_at', null)
      .maybeSingle(),
  );
}

export async function getItem(client: Client, id: string): Promise<ItemRow | null> {
  return unwrapNullable(
    await client.from('items').select('*').eq('id', id).is('deleted_at', null).maybeSingle(),
  );
}

export async function listCollectionsByUser(
  client: Client,
  userId: string,
): Promise<CollectionRow[]> {
  const { data, error } = await client
    .from('collections')
    .select('*')
    .eq('user_id', userId)
    .is('deleted_at', null)
    .order('is_pinned', { ascending: false })
    .order('position', { ascending: true });
  if (error) throw toKlectError(error);
  return data ?? [];
}

/** Everything the sitemap needs, cheap and public-only by RLS. */
export async function listPublicSitemapEntries(
  client: Client,
  limit = 5000,
): Promise<{
  profiles: Array<{ username: string; updated_at: string }>;
  collections: Array<{ id: string; updated_at: string }>;
  subcollections: Array<{ id: string; updated_at: string }>;
  items: Array<{ id: string; updated_at: string }>;
}> {
  const [profiles, collections, subcollections, items] = await Promise.all([
    client
      .from('profiles')
      .select('username, updated_at')
      .eq('account_visibility', 'public')
      .eq('is_suspended', false)
      .limit(limit),
    client
      .from('collections')
      .select('id, updated_at')
      .eq('visibility', 'public')
      .is('deleted_at', null)
      .is('hidden_at', null)
      .limit(limit),
    client
      .from('subcollections')
      .select('id, updated_at')
      .is('deleted_at', null)
      .is('hidden_at', null)
      .limit(limit),
    client
      .from('items')
      .select('id, updated_at')
      .is('deleted_at', null)
      .is('hidden_at', null)
      .limit(limit),
  ]);

  return {
    profiles: profiles.data ?? [],
    collections: collections.data ?? [],
    subcollections: subcollections.data ?? [],
    items: items.data ?? [],
  };
}

/* ── comments ─────────────────────────────────────────────────────────────── */

export async function listComments(
  client: Client,
  type: EntityType,
  id: string,
  params: { limit?: number; offset?: number } = {},
): Promise<CommentRow[]> {
  const limit = params.limit ?? 50;
  const offset = params.offset ?? 0;
  const { data, error } = await client
    .from('comments')
    .select('*')
    .eq('entity_type', type)
    .eq('entity_id', id)
    .is('deleted_at', null)
    .order('created_at', { ascending: true })
    .range(offset, offset + limit - 1);
  if (error) throw toKlectError(error);
  return data ?? [];
}

/* ── notifications & conversations ────────────────────────────────────────── */

export async function listNotifications(
  client: Client,
  params: { limit?: number; before?: string } = {},
): Promise<NotificationRow[]> {
  let query = client
    .from('notifications')
    .select('*')
    .order('created_at', { ascending: false })
    .limit(params.limit ?? 40);
  if (params.before) query = query.lt('created_at', params.before);
  const { data, error } = await query;
  if (error) throw toKlectError(error);
  return data ?? [];
}

export async function countUnreadNotifications(client: Client): Promise<number> {
  const { count, error } = await client
    .from('notifications')
    .select('id', { count: 'exact', head: true })
    .is('read_at', null);
  if (error) throw toKlectError(error);
  return count ?? 0;
}

export async function listConversations(
  client: Client,
  limit = 40,
): Promise<ConversationRow[]> {
  const { data, error } = await client
    .from('conversations')
    .select('*')
    .order('last_message_at', { ascending: false, nullsFirst: false })
    .limit(limit);
  if (error) throw toKlectError(error);
  return data ?? [];
}

export async function listMessages(
  client: Client,
  conversationId: string,
  params: { limit?: number; before?: string } = {},
): Promise<MessageRow[]> {
  let query = client
    .from('messages')
    .select('*')
    .eq('conversation_id', conversationId)
    .is('deleted_at', null)
    .order('created_at', { ascending: false })
    .limit(params.limit ?? 50);
  if (params.before) query = query.lt('created_at', params.before);
  const { data, error } = await query;
  if (error) throw toKlectError(error);
  return (data ?? []).slice().reverse();
}

export type MessageInsert = Database['public']['Tables']['messages']['Insert'];

/**
 * Messages are sent by INSERT, not by an RPC — triggers then update the
 * conversation preview, bump unread counts and fan out notifications.
 */
export async function sendMessage(
  client: Client,
  message: MessageInsert,
): Promise<MessageRow> {
  return unwrap(await client.from('messages').insert(message).select('*').single());
}

/**
 * Rewrites the body of the viewer's own message and stamps `edited_at`.
 * Mirrors mobile `ChatApi.editMessage` — RLS plus the `author_id` filter keep
 * this to the author's own rows.
 */
export async function editMessage(
  client: Client,
  messageId: string,
  authorId: string,
  body: string,
): Promise<void> {
  const { error } = await client
    .from('messages')
    .update({ body, edited_at: new Date().toISOString() })
    .eq('id', messageId)
    .eq('author_id', authorId);
  if (error) throw toKlectError(error);
}

/**
 * Soft-deletes the viewer's own message for everyone. Threads filter on
 * `deleted_at is null` (and live rows render a "Message deleted" stub), so
 * the bubble disappears on both sides. Mirrors mobile `ChatApi.deleteMessage`.
 */
export async function deleteMessage(
  client: Client,
  messageId: string,
  authorId: string,
): Promise<void> {
  const { error } = await client
    .from('messages')
    .update({ deleted_at: new Date().toISOString(), body: null })
    .eq('id', messageId)
    .eq('author_id', authorId);
  if (error) throw toKlectError(error);
}

/* ── blocks & mutes (settings) ────────────────────────────────────────────── */

export async function listBlockedUsers(client: Client): Promise<ProfileRow[]> {
  const { data, error } = await client
    .from('blocks')
    .select('blocked:profiles!blocks_blocked_id_fkey(*)');
  if (error) throw toKlectError(error);
  return (data ?? [])
    .map((row) => (row as { blocked: ProfileRow | null }).blocked)
    .filter((profile): profile is ProfileRow => profile !== null);
}

export async function blockUser(client: Client, userId: string): Promise<void> {
  const {
    data: { user },
  } = await client.auth.getUser();
  if (!user) throw toKlectError({ code: 'PGRST301', message: 'Sign in to do that.' });
  const { error } = await client
    .from('blocks')
    .insert({ blocker_id: user.id, blocked_id: userId });
  if (error && error.code !== '23505') throw toKlectError(error);
}

export async function unblockUser(client: Client, userId: string): Promise<void> {
  const {
    data: { user },
  } = await client.auth.getUser();
  if (!user) throw toKlectError({ code: 'PGRST301', message: 'Sign in to do that.' });
  const { error } = await client
    .from('blocks')
    .delete()
    .eq('blocker_id', user.id)
    .eq('blocked_id', userId);
  if (error) throw toKlectError(error);
}

export async function muteUser(client: Client, userId: string): Promise<void> {
  const {
    data: { user },
  } = await client.auth.getUser();
  if (!user) throw toKlectError({ code: 'PGRST301', message: 'Sign in to do that.' });
  const { error } = await client
    .from('mutes')
    .insert({ muter_id: user.id, muted_id: userId });
  if (error && error.code !== '23505') throw toKlectError(error);
}

export async function unmuteUser(client: Client, userId: string): Promise<void> {
  const {
    data: { user },
  } = await client.auth.getUser();
  if (!user) throw toKlectError({ code: 'PGRST301', message: 'Sign in to do that.' });
  const { error } = await client
    .from('mutes')
    .delete()
    .eq('muter_id', user.id)
    .eq('muted_id', userId);
  if (error) throw toKlectError(error);
}

/* ── tags ─────────────────────────────────────────────────────────────────── */

export async function listPopularTags(
  client: Client,
  limit = 24,
): Promise<Array<{ id: string; name: string; slug: string; use_count: number }>> {
  const { data, error } = await client
    .from('tags')
    .select('id, name, slug, use_count')
    .order('use_count', { ascending: false })
    .limit(limit);
  if (error) throw toKlectError(error);
  return data ?? [];
}
