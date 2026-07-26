/**
 * Reads and writes the social surface needs that `@/lib/api` does not already
 * cover. Same contract as that module — the Supabase client is always the first
 * argument, so one function serves a Server Component and a Client Component.
 *
 * Two rules carried over verbatim:
 *   · counts come from counter columns, never `COUNT(*)`;
 *   · every failure becomes a `KlectError` via `toKlectError`.
 */
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '@/lib/database.types';
import type { EntityType, SurfaceEntityType, Visibility } from '@/lib/entities';
import { toKlectError } from '@/lib/errors';
import type {
  CollectionRow,
  ConversationRow,
  ItemMediaRow,
  ItemRow,
  MessageRow,
  NotificationRow,
  PostRow,
  ProfileRow,
  SubcollectionRow,
} from '@/lib/types';

export type Client = SupabaseClient<Database>;

type Tables = Database['public']['Tables'];
export type ConversationMemberRow = Tables['conversation_members']['Row'];
export type MessageReactionRow = Tables['message_reactions']['Row'];
export type MessageReceiptRow = Tables['message_receipts']['Row'];

function rows<T>(result: { data: T[] | null; error: unknown }): T[] {
  if (result.error) throw toKlectError(result.error);
  return result.data ?? [];
}

function one<T>(result: { data: T | null; error: unknown }): T {
  if (result.error) throw toKlectError(result.error);
  if (result.data === null) throw toKlectError({ code: 'PGRST116', message: 'No rows returned' });
  return result.data;
}

/* ── a card-shaped view of any of the three surfaces ──────────────────────── */

/**
 * The one shape every grid in this surface renders. Collections, subcollections
 * and items all normalise into it, which is what lets a single card component
 * serve all three levels of the hierarchy. Posts join for the shared-into-chat
 * card only — they never appear in a masonry grid.
 */
export interface EntitySummary {
  type: SurfaceEntityType | 'post';
  id: string;
  ownerId: string;
  title: string;
  subtitle: string | null;
  coverPath: string | null;
  coverBlurhash: string | null;
  width: number | null;
  height: number | null;
  accentColor: string | null;
  likeCount: number;
  saveCount: number;
  repostCount: number;
  commentCount: number;
  viewCount: number;
  childCount: number;
  createdAt: string;
  visibility: Visibility | null;
  /** Post only: the full body text — cards render an excerpt. */
  body?: string | null;
  /** Post only: the author byline for the shared-post card. */
  author?: {
    username: string;
    displayName: string;
    avatarPath: string | null;
    isVerified: boolean;
  } | null;
}

export function collectionSummary(row: CollectionRow): EntitySummary {
  return {
    type: 'collection',
    id: row.id,
    ownerId: row.user_id,
    title: row.name,
    subtitle: row.description,
    coverPath: row.cover_path,
    coverBlurhash: row.cover_blurhash,
    width: null,
    height: null,
    accentColor: row.accent_color,
    likeCount: row.like_count,
    saveCount: row.save_count,
    repostCount: row.repost_count,
    commentCount: row.comment_count,
    viewCount: row.view_count,
    childCount: row.item_count,
    createdAt: row.created_at,
    visibility: row.visibility,
  };
}

export function subcollectionSummary(row: SubcollectionRow): EntitySummary {
  return {
    type: 'subcollection',
    id: row.id,
    ownerId: row.user_id,
    title: row.name,
    subtitle: row.description,
    coverPath: row.cover_path,
    coverBlurhash: row.cover_blurhash,
    width: null,
    height: null,
    accentColor: null,
    likeCount: row.like_count,
    saveCount: row.save_count,
    repostCount: row.repost_count,
    commentCount: row.comment_count,
    viewCount: row.view_count,
    childCount: row.item_count,
    createdAt: row.created_at,
    visibility: row.visibility,
  };
}

export function itemSummary(row: ItemRow): EntitySummary {
  return {
    type: 'item',
    id: row.id,
    ownerId: row.user_id,
    title: row.title,
    subtitle: row.brand,
    coverPath: row.cover_path,
    coverBlurhash: row.cover_blurhash,
    width: row.cover_width,
    height: row.cover_height,
    accentColor: null,
    likeCount: row.like_count,
    saveCount: row.save_count,
    repostCount: row.repost_count,
    commentCount: row.comment_count,
    viewCount: row.view_count,
    childCount: row.media_count,
    createdAt: row.created_at,
    visibility: row.visibility,
  };
}

/** The first `post_media` photo, hydrated alongside the post row. */
interface PostThumb {
  storage_path: string;
  blurhash: string | null;
  width: number | null;
  height: number | null;
}

export function postSummary(
  row: PostRow,
  author: ProfileRow | null,
  thumb: PostThumb | null,
): EntitySummary {
  return {
    type: 'post',
    id: row.id,
    ownerId: row.author_id,
    title: row.body?.trim() ? row.body : 'Post',
    subtitle: author ? `@${author.username}` : null,
    coverPath: thumb?.storage_path ?? null,
    coverBlurhash: thumb?.blurhash ?? null,
    width: thumb?.width ?? null,
    height: thumb?.height ?? null,
    accentColor: null,
    likeCount: row.like_count,
    saveCount: row.save_count,
    repostCount: row.repost_count,
    commentCount: row.comment_count,
    viewCount: row.view_count,
    childCount: 0,
    createdAt: row.created_at,
    visibility: row.visibility,
    body: row.body,
    author: author
      ? {
          username: author.username,
          displayName: author.display_name,
          avatarPath: author.avatar_path,
          isVerified: author.is_verified,
        }
      : null,
  };
}

/* ── profile tabs ─────────────────────────────────────────────────────────── */

export interface PageParams {
  limit?: number;
  offset?: number;
}

export async function listCollectionSummaries(
  client: Client,
  userId: string,
  params: PageParams = {},
): Promise<EntitySummary[]> {
  const limit = params.limit ?? 24;
  const offset = params.offset ?? 0;
  const result = await client
    .from('collections')
    .select('*')
    .eq('user_id', userId)
    .is('deleted_at', null)
    .is('hidden_at', null)
    .order('is_pinned', { ascending: false })
    .order('position', { ascending: true })
    .order('created_at', { ascending: false })
    .range(offset, offset + limit - 1);
  return rows<CollectionRow>(result).map(collectionSummary);
}

export async function listItemSummaries(
  client: Client,
  userId: string,
  params: PageParams = {},
): Promise<EntitySummary[]> {
  const limit = params.limit ?? 24;
  const offset = params.offset ?? 0;
  const result = await client
    .from('items')
    .select('*')
    .eq('user_id', userId)
    .is('deleted_at', null)
    .is('hidden_at', null)
    .order('created_at', { ascending: false })
    .range(offset, offset + limit - 1);
  return rows<ItemRow>(result).map(itemSummary);
}

export async function listSubcollectionSummaries(
  client: Client,
  collectionId: string,
): Promise<EntitySummary[]> {
  const result = await client
    .from('subcollections')
    .select('*')
    .eq('collection_id', collectionId)
    .is('deleted_at', null)
    .is('hidden_at', null)
    .order('position', { ascending: true });
  return rows<SubcollectionRow>(result).map(subcollectionSummary);
}

/**
 * The Likes / Saves tabs. `likes` and `saves` are polymorphic, so this reads the
 * join rows first and then batch-hydrates each entity table exactly once —
 * three queries, never one per row.
 */
export async function listInteractedSummaries(
  client: Client,
  table: 'likes' | 'saves',
  userId: string,
  params: PageParams = {},
): Promise<EntitySummary[]> {
  const limit = params.limit ?? 24;
  const offset = params.offset ?? 0;

  const joinResult = await client
    .from(table)
    .select('entity_type, entity_id, created_at')
    .eq('user_id', userId)
    .in('entity_type', ['collection', 'subcollection', 'item'])
    .order('created_at', { ascending: false })
    .range(offset, offset + limit - 1);

  const refs = rows<{ entity_type: EntityType; entity_id: string; created_at: string }>(
    joinResult,
  );
  if (refs.length === 0) return [];

  const idsOf = (type: EntityType): string[] =>
    refs.filter((ref) => ref.entity_type === type).map((ref) => ref.entity_id);

  const collectionIds = idsOf('collection');
  const subcollectionIds = idsOf('subcollection');
  const itemIds = idsOf('item');

  const [collections, subcollections, items] = await Promise.all([
    collectionIds.length
      ? client.from('collections').select('*').in('id', collectionIds).is('deleted_at', null)
      : Promise.resolve({ data: [] as CollectionRow[], error: null }),
    subcollectionIds.length
      ? client
          .from('subcollections')
          .select('*')
          .in('id', subcollectionIds)
          .is('deleted_at', null)
      : Promise.resolve({ data: [] as SubcollectionRow[], error: null }),
    itemIds.length
      ? client.from('items').select('*').in('id', itemIds).is('deleted_at', null)
      : Promise.resolve({ data: [] as ItemRow[], error: null }),
  ]);

  const byKey = new Map<string, EntitySummary>();
  for (const row of rows<CollectionRow>(collections)) {
    byKey.set(`collection:${row.id}`, collectionSummary(row));
  }
  for (const row of rows<SubcollectionRow>(subcollections)) {
    byKey.set(`subcollection:${row.id}`, subcollectionSummary(row));
  }
  for (const row of rows<ItemRow>(items)) {
    byKey.set(`item:${row.id}`, itemSummary(row));
  }

  // Preserve the interaction order, and silently drop anything RLS hid.
  return refs
    .map((ref) => byKey.get(`${ref.entity_type}:${ref.entity_id}`))
    .filter((summary): summary is EntitySummary => summary !== undefined);
}

/* ── relationship state ───────────────────────────────────────────────────── */

export interface RelationshipState {
  following: boolean;
  blocked: boolean;
  muted: boolean;
}

/** Three existence checks, not three counts. */
export async function getRelationship(
  client: Client,
  viewerId: string,
  targetId: string,
): Promise<RelationshipState> {
  if (viewerId === targetId) return { following: false, blocked: false, muted: false };

  const [follow, block, mute] = await Promise.all([
    client
      .from('follows')
      .select('follower_id')
      .eq('follower_id', viewerId)
      .eq('following_id', targetId)
      .maybeSingle(),
    client
      .from('blocks')
      .select('blocker_id')
      .eq('blocker_id', viewerId)
      .eq('blocked_id', targetId)
      .maybeSingle(),
    client
      .from('mutes')
      .select('muter_id')
      .eq('muter_id', viewerId)
      .eq('muted_id', targetId)
      .maybeSingle(),
  ]);

  return {
    following: follow.data !== null,
    blocked: block.data !== null,
    muted: mute.data !== null,
  };
}

export async function listMutedUsers(client: Client): Promise<ProfileRow[]> {
  const { data, error } = await client
    .from('mutes')
    .select('muted:profiles!mutes_muted_id_fkey(*)');
  if (error) throw toKlectError(error);
  return (data ?? [])
    .map((row) => (row as { muted: ProfileRow | null }).muted)
    .filter((profile): profile is ProfileRow => profile !== null);
}

/* ── profiles by id, batched ──────────────────────────────────────────────── */

export async function fetchProfiles(
  client: Client,
  ids: readonly string[],
): Promise<Map<string, ProfileRow>> {
  const unique = [...new Set(ids.filter(Boolean))];
  if (unique.length === 0) return new Map();
  const result = await client.from('profiles').select('*').in('id', unique);
  return new Map(rows<ProfileRow>(result).map((row) => [row.id, row]));
}

/* ── notifications ────────────────────────────────────────────────────────── */

export interface NotificationEntry {
  notification: NotificationRow;
  actor: ProfileRow | null;
}

export async function listNotificationEntries(
  client: Client,
  params: { limit?: number; before?: string } = {},
): Promise<NotificationEntry[]> {
  let query = client
    .from('notifications')
    .select('*')
    .order('created_at', { ascending: false })
    .limit(params.limit ?? 40);
  if (params.before) query = query.lt('created_at', params.before);

  const list = rows<NotificationRow>(await query);
  if (list.length === 0) return [];

  const actors = await fetchProfiles(
    client,
    list.map((row) => row.actor_id).filter((id): id is string => Boolean(id)),
  );

  return list.map((notification) => ({
    notification,
    actor: notification.actor_id ? (actors.get(notification.actor_id) ?? null) : null,
  }));
}

/** Hydrates one realtime INSERT into the same shape the list renders. */
export async function hydrateNotification(
  client: Client,
  notification: NotificationRow,
): Promise<NotificationEntry> {
  if (!notification.actor_id) return { notification, actor: null };
  const { data } = await client
    .from('profiles')
    .select('*')
    .eq('id', notification.actor_id)
    .maybeSingle();
  return { notification, actor: data ?? null };
}

/* ── conversations ────────────────────────────────────────────────────────── */

export interface ConversationSummary {
  conversation: ConversationRow;
  membership: ConversationMemberRow | null;
  /** Everyone but the viewer. For a DM that is exactly one profile. */
  others: ProfileRow[];
}

export function conversationTitle(summary: ConversationSummary, fallback = 'Conversation'): string {
  if (summary.conversation.title) return summary.conversation.title;
  const names = summary.others.map((profile) => profile.display_name).filter(Boolean);
  return names.length > 0 ? names.join(', ') : fallback;
}

async function buildSummaries(
  client: Client,
  viewerId: string,
  conversations: ConversationRow[],
): Promise<ConversationSummary[]> {
  if (conversations.length === 0) return [];
  const ids = conversations.map((row) => row.id);

  const members = rows<ConversationMemberRow>(
    await client.from('conversation_members').select('*').in('conversation_id', ids),
  );

  const profiles = await fetchProfiles(
    client,
    members.filter((member) => member.user_id !== viewerId).map((member) => member.user_id),
  );

  return conversations.map((conversation) => {
    const mine = members.find(
      (member) => member.conversation_id === conversation.id && member.user_id === viewerId,
    );
    const others = members
      .filter(
        (member) =>
          member.conversation_id === conversation.id &&
          member.user_id !== viewerId &&
          member.left_at === null,
      )
      .map((member) => profiles.get(member.user_id))
      .filter((profile): profile is ProfileRow => profile !== undefined);

    return { conversation, membership: mine ?? null, others };
  });
}

export async function listConversationSummaries(
  client: Client,
  viewerId: string,
  limit = 40,
): Promise<ConversationSummary[]> {
  const conversations = rows<ConversationRow>(
    await client
      .from('conversations')
      .select('*')
      .order('last_message_at', { ascending: false, nullsFirst: false })
      .limit(limit),
  );
  return buildSummaries(client, viewerId, conversations);
}

export async function getConversationSummary(
  client: Client,
  viewerId: string,
  conversationId: string,
): Promise<ConversationSummary | null> {
  const { data, error } = await client
    .from('conversations')
    .select('*')
    .eq('id', conversationId)
    .maybeSingle();
  if (error) throw toKlectError(error);
  if (!data) return null;
  const [summary] = await buildSummaries(client, viewerId, [data]);
  return summary ?? null;
}

/**
 * Per-viewer conversation flags. `pinned`, `archived_at` and `muted_until`
 * live on the viewer's own `conversation_members` row (never the conversation),
 * mirroring mobile `ChatApi`: pin is a boolean, archive stamps `archived_at`,
 * mute stamps `muted_until` (null clears either).
 */
export async function updateConversationMembership(
  client: Client,
  conversationId: string,
  userId: string,
  patch: Pick<
    Tables['conversation_members']['Update'],
    'pinned' | 'archived_at' | 'muted_until'
  >,
): Promise<void> {
  const { error } = await client
    .from('conversation_members')
    .update(patch)
    .eq('conversation_id', conversationId)
    .eq('user_id', userId);
  if (error) throw toKlectError(error);
}

/* ── message metadata (reactions, receipts, replies) ──────────────────────── */

export async function listMessageReactions(
  client: Client,
  messageIds: readonly string[],
): Promise<MessageReactionRow[]> {
  if (messageIds.length === 0) return [];
  return rows<MessageReactionRow>(
    await client.from('message_reactions').select('*').in('message_id', [...messageIds]),
  );
}

export async function toggleMessageReaction(
  client: Client,
  messageId: string,
  userId: string,
  emoji: string,
  active: boolean,
): Promise<void> {
  if (active) {
    const { error } = await client
      .from('message_reactions')
      .insert({ message_id: messageId, user_id: userId, emoji });
    // A duplicate simply means it already applied.
    if (error && error.code !== '23505') throw toKlectError(error);
    return;
  }
  const { error } = await client
    .from('message_reactions')
    .delete()
    .eq('message_id', messageId)
    .eq('user_id', userId)
    .eq('emoji', emoji);
  if (error) throw toKlectError(error);
}

export async function listMessageReceipts(
  client: Client,
  messageIds: readonly string[],
): Promise<MessageReceiptRow[]> {
  if (messageIds.length === 0) return [];
  return rows<MessageReceiptRow>(
    await client.from('message_receipts').select('*').in('message_id', [...messageIds]),
  );
}

/** Read receipts for everything the viewer can see. Duplicates are ignored. */
export async function recordMessageReceipts(
  client: Client,
  messageIds: readonly string[],
  userId: string,
): Promise<void> {
  if (messageIds.length === 0) return;
  const { error } = await client
    .from('message_receipts')
    .upsert(
      messageIds.map((id) => ({ message_id: id, user_id: userId })),
      { onConflict: 'message_id,user_id', ignoreDuplicates: true },
    );
  if (error && error.code !== '23505') throw toKlectError(error);
}

/** Batch-loads the messages a thread replies to, so a reply can quote inline. */
export async function fetchMessagesByIds(
  client: Client,
  ids: readonly string[],
): Promise<Map<string, MessageRow>> {
  const unique = [...new Set(ids.filter(Boolean))];
  if (unique.length === 0) return new Map();
  const result = await client.from('messages').select('*').in('id', unique);
  return new Map(rows<MessageRow>(result).map((row) => [row.id, row]));
}

/* ── shared-entity message cards ──────────────────────────────────────────── */

/** Resolves the `shared_entity_*` columns of a batch of messages in one pass. */
export async function fetchSharedEntities(
  client: Client,
  refs: ReadonlyArray<{ type: EntityType; id: string }>,
): Promise<Map<string, EntitySummary>> {
  const map = new Map<string, EntitySummary>();
  const idsOf = (type: EntityType) =>
    [...new Set(refs.filter((ref) => ref.type === type).map((ref) => ref.id))];

  const collectionIds = idsOf('collection');
  const subcollectionIds = idsOf('subcollection');
  const itemIds = idsOf('item');
  const postIds = idsOf('post');
  if (!collectionIds.length && !subcollectionIds.length && !itemIds.length && !postIds.length) {
    return map;
  }

  const [collections, subcollections, items, posts] = await Promise.all([
    collectionIds.length
      ? client.from('collections').select('*').in('id', collectionIds).is('deleted_at', null)
      : Promise.resolve({ data: [] as CollectionRow[], error: null }),
    subcollectionIds.length
      ? client
          .from('subcollections')
          .select('*')
          .in('id', subcollectionIds)
          .is('deleted_at', null)
      : Promise.resolve({ data: [] as SubcollectionRow[], error: null }),
    itemIds.length
      ? client.from('items').select('*').in('id', itemIds).is('deleted_at', null)
      : Promise.resolve({ data: [] as ItemRow[], error: null }),
    postIds.length
      ? client.from('posts').select('*').in('id', postIds).is('deleted_at', null)
      : Promise.resolve({ data: [] as PostRow[], error: null }),
  ]);

  for (const row of rows<CollectionRow>(collections)) {
    map.set(`collection:${row.id}`, collectionSummary(row));
  }
  for (const row of rows<SubcollectionRow>(subcollections)) {
    map.set(`subcollection:${row.id}`, subcollectionSummary(row));
  }
  for (const row of rows<ItemRow>(items)) {
    map.set(`item:${row.id}`, itemSummary(row));
  }

  // Posts need two side lookups the entity tables carry inline: the author
  // byline and the first `post_media` photo. Both are batched, never per-row.
  const postRows = rows<PostRow>(posts);
  if (postRows.length > 0) {
    const [authors, media] = await Promise.all([
      fetchProfiles(
        client,
        postRows.map((row) => row.author_id),
      ),
      client
        .from('post_media')
        .select('post_id, storage_path, blurhash, width, height, position')
        .in(
          'post_id',
          postRows.map((row) => row.id),
        )
        .order('position', { ascending: true }),
    ]);
    const thumbs = new Map<string, PostThumb>();
    for (const entry of rows<PostThumb & { post_id: string; position: number }>(media)) {
      if (!thumbs.has(entry.post_id)) thumbs.set(entry.post_id, entry);
    }
    for (const row of postRows) {
      map.set(
        `post:${row.id}`,
        postSummary(row, authors.get(row.author_id) ?? null, thumbs.get(row.id) ?? null),
      );
    }
  }
  return map;
}

/* ── create flow ──────────────────────────────────────────────────────────── */

/** URL-safe, stable, and unique enough that the per-owner unique index holds. */
export function slugify(value: string): string {
  const base = value
    .normalize('NFKD')
    .replace(/\p{M}+/gu, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 48);
  return base || 'untitled';
}

export function uniqueSlug(value: string): string {
  return `${slugify(value)}-${Math.random().toString(36).slice(2, 7)}`;
}

export interface CreateCollectionInput {
  userId: string;
  name: string;
  description?: string | null;
  visibility: Visibility;
  accentColor?: string | null;
}

export async function createCollection(
  client: Client,
  input: CreateCollectionInput,
): Promise<CollectionRow> {
  return one<CollectionRow>(
    await client
      .from('collections')
      .insert({
        user_id: input.userId,
        name: input.name,
        slug: uniqueSlug(input.name),
        description: input.description ?? null,
        visibility: input.visibility,
        accent_color: input.accentColor ?? null,
      })
      .select('*')
      .single(),
  );
}

export interface CreateSubcollectionInput {
  userId: string;
  collectionId: string;
  name: string;
  description?: string | null;
  visibility?: Visibility | null;
}

export async function createSubcollection(
  client: Client,
  input: CreateSubcollectionInput,
): Promise<SubcollectionRow> {
  return one<SubcollectionRow>(
    await client
      .from('subcollections')
      .insert({
        user_id: input.userId,
        collection_id: input.collectionId,
        name: input.name,
        slug: uniqueSlug(input.name),
        description: input.description ?? null,
        visibility: input.visibility ?? null,
      })
      .select('*')
      .single(),
  );
}

export interface CreateItemInput {
  /** Generated client-side so media can be uploaded to `{user}/{item}/…` first. */
  id: string;
  userId: string;
  collectionId: string;
  subcollectionId?: string | null;
  title: string;
  description?: string | null;
  brand?: string | null;
  model?: string | null;
  year?: number | null;
  condition?: string | null;
  rarity?: string | null;
  acquisitionPlace?: string | null;
  acquisitionDate?: string | null;
  purchasePrice?: number | null;
  currency?: string | null;
  visibility?: Visibility | null;
}

export async function createItem(client: Client, input: CreateItemInput): Promise<ItemRow> {
  return one<ItemRow>(
    await client
      .from('items')
      .insert({
        id: input.id,
        user_id: input.userId,
        collection_id: input.collectionId,
        subcollection_id: input.subcollectionId ?? null,
        title: input.title,
        description: input.description ?? null,
        brand: input.brand ?? null,
        model: input.model ?? null,
        year: input.year ?? null,
        condition: input.condition ?? null,
        rarity: input.rarity ?? null,
        acquisition_place: input.acquisitionPlace ?? null,
        acquisition_date: input.acquisitionDate ?? null,
        purchase_price: input.purchasePrice ?? null,
        currency: input.currency ?? null,
        visibility: input.visibility ?? null,
      })
      .select('*')
      .single(),
  );
}

export interface ItemMediaInput {
  itemId: string;
  userId: string;
  storagePath: string;
  width: number;
  height: number;
  blurhash: string;
  dominantColor: string | null;
  mimeType: string;
  bytes: number;
  altText?: string | null;
  position: number;
}

/**
 * Inserted only after every byte is in the bucket. A trigger copies position 0
 * onto the parent item's `cover_*`, so the cover derives itself.
 */
export async function insertItemMedia(
  client: Client,
  media: readonly ItemMediaInput[],
): Promise<ItemMediaRow[]> {
  if (media.length === 0) return [];
  const result = await client
    .from('item_media')
    .insert(
      media.map((entry) => ({
        item_id: entry.itemId,
        user_id: entry.userId,
        storage_path: entry.storagePath,
        width: entry.width,
        height: entry.height,
        blurhash: entry.blurhash,
        dominant_color: entry.dominantColor,
        mime_type: entry.mimeType,
        bytes: entry.bytes,
        alt_text: entry.altText ?? null,
        position: entry.position,
      })),
    )
    .select('*');
  return rows<ItemMediaRow>(result);
}

export async function listItemMedia(
  client: Client,
  itemId: string,
): Promise<ItemMediaRow[]> {
  return rows<ItemMediaRow>(
    await client
      .from('item_media')
      .select('*')
      .eq('item_id', itemId)
      .order('position', { ascending: true }),
  );
}

/**
 * Tags are a shared vocabulary: find-or-create by slug, then link. Returns how
 * many stuck — the caller reports a partial result rather than failing a create
 * that has already succeeded.
 */
export async function attachTags(
  client: Client,
  params: { entityType: EntityType; entityId: string; userId: string; tags: readonly string[] },
): Promise<number> {
  const names = [...new Set(params.tags.map((tag) => tag.trim()).filter(Boolean))].slice(0, 12);
  if (names.length === 0) return 0;

  const slugs = names.map(slugify);
  const existing = rows<{ id: string; slug: string }>(
    await client.from('tags').select('id, slug').in('slug', slugs),
  );
  const bySlug = new Map(existing.map((tag) => [tag.slug, tag.id]));

  const missing = names.filter((name) => !bySlug.has(slugify(name)));
  if (missing.length > 0) {
    const { data, error } = await client
      .from('tags')
      .upsert(
        missing.map((name) => ({ name, slug: slugify(name) })),
        { onConflict: 'slug' },
      )
      .select('id, slug');
    if (error) throw toKlectError(error);
    for (const tag of data ?? []) bySlug.set(tag.slug, tag.id);
  }

  const links = slugs
    .map((slug) => bySlug.get(slug))
    .filter((id): id is string => Boolean(id))
    .map((tagId) => ({
      tag_id: tagId,
      entity_type: params.entityType,
      entity_id: params.entityId,
      user_id: params.userId,
    }));
  if (links.length === 0) return 0;

  const { error } = await client
    .from('entity_tags')
    .upsert(links, { onConflict: 'entity_type,entity_id,tag_id', ignoreDuplicates: true });
  if (error && error.code !== '23505') throw toKlectError(error);
  return links.length;
}

/* ── account erasure ──────────────────────────────────────────────────────── */

/**
 * Everything a client holding only the publishable key is *able* to erase.
 *
 * Removing the `auth.users` row itself requires the service-role key, which by
 * rule (AGENTS.md §2) never reaches this bundle and has no edge function behind
 * it yet. So this soft-deletes every collection the user owns — the cascade
 * takes their subcollections, items, media rows and polymorphic
 * likes/saves/comments/views with it — scrubs the profile back to an empty
 * shell, and locks the account to private. The UI says exactly this; it does
 * not pretend the auth record is gone.
 */
export async function eraseAccountContent(client: Client, userId: string): Promise<void> {
  const now = new Date().toISOString();

  const collections = await client
    .from('collections')
    .update({ deleted_at: now })
    .eq('user_id', userId)
    .is('deleted_at', null);
  if (collections.error) throw toKlectError(collections.error);

  const profile = await client
    .from('profiles')
    .update({
      display_name: 'Deleted account',
      bio: null,
      location: null,
      website: null,
      avatar_path: null,
      banner_path: null,
      accent_color: null,
      account_visibility: 'private',
      allow_messages_from: 'nobody',
      show_similarity: false,
    })
    .eq('id', userId);
  if (profile.error) throw toKlectError(profile.error);
}
