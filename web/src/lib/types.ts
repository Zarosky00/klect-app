/**
 * Shapes of the `jsonb` payloads the RPCs return.
 *
 * These were read off the live function definitions in `new_klect`, not
 * guessed. If a migration changes a payload, change it here in the same commit.
 */
import type { Database } from '@/lib/database.types';
import type {
  AppRole,
  EntityType,
  ModAction,
  ReportReason,
  ReportStatus,
  SurfaceEntityType,
} from '@/lib/entities';

export type Tables = Database['public']['Tables'];
export type ProfileRow = Tables['profiles']['Row'];
export type CollectionRow = Tables['collections']['Row'];
export type SubcollectionRow = Tables['subcollections']['Row'];
export type ItemRow = Tables['items']['Row'];
export type ItemMediaRow = Tables['item_media']['Row'];
export type CommentRow = Tables['comments']['Row'];
export type NotificationRow = Tables['notifications']['Row'];
export type ConversationRow = Tables['conversations']['Row'];
export type MessageRow = Tables['messages']['Row'];
export type PostRow = Tables['posts']['Row'];
export type ReportRow = Tables['reports']['Row'];
export type AuditLogRow = Tables['audit_log']['Row'];
export type TagRow = Tables['tags']['Row'];

/* ── interactions ─────────────────────────────────────────────────────────── */

/** Every toggle RPC returns exactly this. Authoritative — overwrite local state. */
export interface ToggleResult {
  active: boolean;
  count: number;
}

export interface AddCommentResult {
  id: string;
  count: number;
}

export interface DeleteCommentResult {
  count: number;
}

export interface SubmitReportResult {
  id: string;
  already_reported: boolean;
}

/* ── surf ─────────────────────────────────────────────────────────────────── */

export type SurfCardRaw = Database['public']['CompositeTypes']['surf_card'];

/** Same columns, with the nullability the feed actually guarantees resolved. */
export interface SurfCard {
  entity_type: SurfaceEntityType;
  entity_id: string;
  owner_id: string;
  username: string;
  display_name: string;
  avatar_path: string | null;
  is_verified: boolean;
  title: string;
  subtitle: string | null;
  cover_path: string | null;
  cover_blurhash: string | null;
  /** Intrinsic cover pixels — reserve the masonry tile with these. */
  width: number | null;
  height: number | null;
  accent_color: string | null;
  like_count: number;
  save_count: number;
  repost_count: number;
  comment_count: number;
  view_count: number;
  child_count: number;
  created_at: string;
  score: number;
  viewer_liked: boolean;
  viewer_saved: boolean;
  viewer_reposted: boolean;
  viewer_follows: boolean;
}

export type SurfFilter = 'all' | 'following' | 'items' | 'collections';

export const SURF_FILTERS: readonly SurfFilter[] = [
  'all',
  'following',
  'items',
  'collections',
];

export const SURF_FILTER_LABELS: Record<SurfFilter, string> = {
  all: 'Everything',
  following: 'Following',
  items: 'Items',
  collections: 'Collections',
};

/* ── closeup ──────────────────────────────────────────────────────────────── */

export interface CloseupOwner {
  id: string;
  username: string;
  display_name: string;
  avatar_path: string | null;
  banner_path: string | null;
  bio: string | null;
  is_verified: boolean;
  follower_count: number;
  collection_count: number;
  item_count: number;
}

export interface CloseupViewer {
  liked: boolean;
  saved: boolean;
  reposted: boolean;
  follows: boolean;
  is_owner: boolean | null;
}

export interface CloseupCounts {
  like: number;
  save: number;
  repost: number;
  comment: number;
  view: number;
}

export interface CloseupBase {
  entity_type: EntityType;
  entity_id: string;
  owner: CloseupOwner;
  viewer: CloseupViewer;
  counts: CloseupCounts;
  /** Tag slugs. */
  tags: string[];
}

export interface CloseupMedia {
  id: string;
  storage_path: string;
  width: number | null;
  height: number | null;
  blurhash: string | null;
  alt_text: string | null;
  position: number;
  dominant_color: string | null;
}

export interface BreadcrumbRef {
  id: string;
  name: string;
  slug: string;
}

export interface SiblingRef {
  id: string;
  title: string;
  cover_path: string | null;
  cover_blurhash: string | null;
  cover_width: number | null;
  cover_height: number | null;
  like_count: number;
}

export interface CloseupItemDetail {
  id: string;
  title: string;
  description: string | null;
  brand: string | null;
  model: string | null;
  year: number | null;
  rarity: string | null;
  condition: string | null;
  currency: string | null;
  purchase_price: number | null;
  acquisition_date: string | null;
  acquisition_place: string | null;
  attributes: Record<string, unknown>;
  is_favorite: boolean;
  created_at: string;
  collection_id: string;
  subcollection_id: string | null;
}

export interface ItemCloseup extends CloseupBase {
  entity_type: 'item';
  item: CloseupItemDetail;
  media: CloseupMedia[];
  breadcrumb: { collection: BreadcrumbRef; subcollection: BreadcrumbRef | null };
  siblings: SiblingRef[];
}

export interface CloseupChildItem {
  id: string;
  title: string;
  position: number;
  cover_path: string | null;
  cover_blurhash: string | null;
  cover_width: number | null;
  cover_height: number | null;
  media_count: number;
  like_count: number;
  save_count?: number;
  comment_count?: number;
  subcollection_id?: string | null;
}

export interface CloseupChildSubcollection {
  id: string;
  name: string;
  slug: string;
  position: number;
  cover_path: string | null;
  cover_blurhash: string | null;
  item_count: number;
}

export interface SubcollectionCloseup extends CloseupBase {
  entity_type: 'subcollection';
  subcollection: {
    id: string;
    name: string;
    slug: string;
    cover_path: string | null;
    cover_blurhash: string | null;
    created_at: string;
    item_count: number;
    collection_id: string;
    description?: string | null;
  };
  breadcrumb: { collection: BreadcrumbRef };
  items: CloseupChildItem[];
}

export interface CollectionCloseup extends CloseupBase {
  entity_type: 'collection';
  collection: {
    id: string;
    name: string;
    slug: string;
    description: string | null;
    cover_path: string | null;
    cover_blurhash: string | null;
    accent_color: string | null;
    created_at: string;
    item_count: number;
    subcollection_count: number;
    template_id: string | null;
  };
  subcollections: CloseupChildSubcollection[];
  items: CloseupChildItem[];
}

export interface PostCloseup extends CloseupBase {
  entity_type: 'post';
  post: {
    id: string;
    body: string | null;
    kind: string;
    created_at: string;
    entity_type: EntityType | null;
    entity_id: string | null;
  };
}

export interface CommentCloseup extends CloseupBase {
  entity_type: 'comment';
}

export type CloseupPayload =
  | ItemCloseup
  | SubcollectionCloseup
  | CollectionCloseup
  | PostCloseup
  | CommentCloseup;

/** The cover the closeup should lead with, whatever the entity type. */
export function closeupCover(payload: CloseupPayload): {
  path: string | null;
  blurhash: string | null;
  width: number | null;
  height: number | null;
} {
  switch (payload.entity_type) {
    case 'item': {
      const first = payload.media[0];
      return {
        path: first?.storage_path ?? null,
        blurhash: first?.blurhash ?? null,
        width: first?.width ?? null,
        height: first?.height ?? null,
      };
    }
    case 'subcollection':
      return {
        path: payload.subcollection.cover_path,
        blurhash: payload.subcollection.cover_blurhash,
        width: null,
        height: null,
      };
    case 'collection':
      return {
        path: payload.collection.cover_path,
        blurhash: payload.collection.cover_blurhash,
        width: null,
        height: null,
      };
    default:
      return { path: null, blurhash: null, width: null, height: null };
  }
}

export function closeupTitle(payload: CloseupPayload): string {
  switch (payload.entity_type) {
    case 'item':
      return payload.item.title;
    case 'subcollection':
      return payload.subcollection.name;
    case 'collection':
      return payload.collection.name;
    case 'post':
      return payload.post.body ?? 'Post';
    default:
      return 'Comment';
  }
}

export function closeupDescription(payload: CloseupPayload): string | null {
  switch (payload.entity_type) {
    case 'item':
      return payload.item.description;
    case 'subcollection':
      return payload.subcollection.description ?? null;
    case 'collection':
      return payload.collection.description;
    case 'post':
      return payload.post.body;
    default:
      return null;
  }
}

/* ── pulse ────────────────────────────────────────────────────────────────── */

export type PulseMode = 'following' | 'foryou';

export const PULSE_MODES: readonly PulseMode[] = ['foryou', 'following'];

export const PULSE_MODE_LABELS: Record<PulseMode, string> = {
  foryou: 'For you',
  following: 'Following',
};

export interface PulseActor {
  /** Present since migration 0018; older optimistic rows may omit it. */
  id?: string | null;
  username: string;
  display_name: string;
  avatar_path: string | null;
  is_verified: boolean;
}

export interface PulseReposter {
  id?: string | null;
  username: string;
  display_name: string;
  avatar_path?: string | null;
  is_verified?: boolean;
}

/** One photo attached to a post — mirrors `post_media` (migration 0018). */
export interface PulseMedia {
  id: string;
  storage_path: string;
  width: number | null;
  height: number | null;
  blurhash: string | null;
  dominant_color: string | null;
  alt_text: string | null;
  position: number;
}

/**
 * The server-embedded preview of a post's attached / quoted / reposted thing.
 * Uniform keys across types; `{type, id, unavailable: true}` when the target is
 * not visible to the caller — render a tombstone, never an empty card.
 */
export interface PulseTarget {
  type: EntityType;
  id: string;
  unavailable?: boolean;
  availability?: 'available' | 'unavailable';
  title?: string | null;
  subtitle?: string | null;
  body?: string | null;
  kind?: string | null;
  cover_path?: string | null;
  cover_blurhash?: string | null;
  cover_width?: number | null;
  cover_height?: number | null;
  child_count?: number | null;
  like_count?: number | null;
  created_at?: string | null;
  author?: PulseActor | null;
  /** Comment targets only (0021): the entity the comment hangs off, so a
   *  reposted comment can deep-link into its discussion. */
  parent_type?: EntityType | null;
  parent_id?: string | null;
  /** Complete ordered media for this target (at most four descriptors). */
  media?: PulseMedia[];
  /** One immutable nested attachment level for quoted posts. */
  attached_target?: PulseTarget | null;
}

export interface PulseEntry {
  feed_kind: 'post' | 'repost';
  post_id: string | null;
  sort_at: string;
  actor_id: string | null;
  reposter_id: string | null;
  quote_text: string | null;
  body: string | null;
  target_type: EntityType | null;
  target_id: string | null;
  like_count: number;
  save_count: number;
  repost_count: number;
  comment_count: number;
  view_count: number;
  reply_count: number;
  author: PulseActor | null;
  reposter: PulseReposter | null;
  viewer_liked: boolean;
  viewer_saved: boolean;
  viewer_reposted: boolean;
  /* Additive envelope keys from migration 0018. */
  kind?: string | null;
  entity_type?: string | null;
  entity_id?: string | null;
  created_at?: string;
  reply_to_post_id?: string | null;
  root_post_id?: string | null;
  /** The post's own photos, ordered by position. */
  media?: PulseMedia[];
  /** Server-embedded target payload — quoted post, shared entity, or tombstone. */
  target?: PulseTarget | null;
  /**
   * Composite-keyset cursor (migration 0021): post id for post rows, target
   * entity id for repost rows. Page with `(sort_at, cursor_id)` of the last
   * rendered row as `(p_before, p_before_id)`.
   */
  cursor_id?: string | null;
}

/**
 * Stream identity of an envelope — a repost and its original are two rows,
 * one post id. Includes `target_id` because entity reposts carry no post id,
 * so two same-second reposts by one collector of different things would
 * otherwise collide and dedupe each other away (W3 dedupe bug).
 */
export function pulseEntryKey(entry: PulseEntry): string {
  return `${entry.feed_kind}:${entry.reposter_id ?? ''}:${entry.post_id ?? ''}:${entry.target_id ?? ''}:${entry.sort_at}`;
}

/* ── post thread (migration 0021, `get_post_thread`) ─────────────────────── */

export type ThreadSort = 'top' | 'new';

export interface ThreadCommentViewer {
  liked: boolean;
  saved: boolean;
  reposted: boolean;
}

/** One comment in the thread page — flat, with `parent_id`/`depth` for nesting. */
export interface ThreadComment {
  id: string;
  body: string;
  author: PulseActor | null;
  created_at: string;
  like_count: number;
  save_count: number;
  repost_count: number;
  reply_count: number;
  parent_id: string | null;
  depth: number;
  viewer: ThreadCommentViewer;
}

export interface PostThreadStats {
  like_count: number;
  repost_count: number;
  save_count: number;
  comment_count: number;
  view_count: number;
}

/**
 * The X thread payload: `{post, stats, comments[], has_more}`. Comments are a
 * flat page ordered by the requested sort; `has_more` is explicit (the feed
 * RPCs use the extra-row contract instead because they return bare arrays).
 */
export interface PostThread {
  post: PulseEntry;
  stats: PostThreadStats;
  comments: ThreadComment[];
  has_more: boolean;
}

/* ── search ───────────────────────────────────────────────────────────────── */

export interface SearchPerson {
  id: string;
  username: string;
  display_name: string;
  avatar_path: string | null;
  is_verified: boolean;
  bio: string | null;
  follower_count: number;
}

export interface SearchCollection {
  id: string;
  name: string;
  slug: string;
  cover_path: string | null;
  cover_blurhash: string | null;
  item_count: number;
  like_count: number;
  username: string;
  display_name: string;
  avatar_path: string | null;
}

export interface SearchItem {
  id: string;
  title: string;
  brand: string | null;
  cover_path: string | null;
  cover_blurhash: string | null;
  cover_width: number | null;
  cover_height: number | null;
  like_count: number;
  username: string;
  display_name: string;
  avatar_path: string | null;
}

export interface SearchTag {
  slug: string;
  name: string;
  use_count: number;
}

/** One post row from `search_all`'s posts section (migration 0021). */
export interface SearchPost {
  id: string;
  /** Body excerpt, capped server-side at 280 chars. */
  body: string;
  kind: string;
  created_at: string;
  like_count: number;
  save_count: number;
  repost_count: number;
  comment_count: number;
  view_count: number;
  author: PulseActor | null;
}

export interface SearchResults {
  people: SearchPerson[];
  collections: SearchCollection[];
  items: SearchItem[];
  tags: SearchTag[];
  posts: SearchPost[];
}

export const EMPTY_SEARCH_RESULTS: SearchResults = {
  people: [],
  collections: [],
  items: [],
  tags: [],
  posts: [],
};

/* ── matches ──────────────────────────────────────────────────────────────── */

export interface MatchCollection {
  id: string;
  name: string;
  cover_path: string | null;
  cover_blurhash: string | null;
  item_count: number;
}

export interface MatchPerson {
  id: string;
  username: string;
  display_name: string;
  avatar_path: string | null;
  bio: string | null;
  is_verified: boolean;
  follower_count: number;
  collection_count: number;
  item_count: number;
  /** 0..1 taste overlap. */
  score: number;
  shared_tags: string[] | null;
  viewer_follows: boolean;
  top_collections: MatchCollection[];
}

/* ── admin ────────────────────────────────────────────────────────────────── */

export interface AdminMetrics {
  users: { total: number; suspended: number; new_7d: number; active_24h: number };
  content: {
    collections: number;
    subcollections: number;
    items: number;
    media: number;
    posts: number;
    comments: number;
    hidden: number;
  };
  engagement: {
    likes: number;
    saves: number;
    reposts: number;
    follows: number;
    messages: number;
    calls: number;
  };
  moderation: {
    open: number;
    reviewing: number;
    actioned_7d: number;
    by_reason: Partial<Record<ReportReason, number>>;
  };
  signups_14d: Array<{ day: string; n: number }>;
}

export interface AdminReportActor {
  id: string;
  username: string;
  display_name: string;
  avatar_path: string | null;
}

export interface AdminReportSubject extends AdminReportActor {
  is_suspended: boolean;
  created_at: string;
}

export interface AdminReportPreview {
  title?: string;
  cover_path?: string | null;
  description?: string | null;
}

export interface AdminReport {
  id: string;
  reason: ReportReason;
  details: string | null;
  status: ReportStatus;
  priority: number;
  created_at: string;
  entity_type: EntityType | null;
  entity_id: string | null;
  message_id: string | null;
  reporter: AdminReportActor | null;
  subject: AdminReportSubject | null;
  subject_open_reports: number;
  preview: AdminReportPreview | null;
}

export interface AdminUserDetail {
  profile: ProfileRow | null;
  roles: AppRole[];
  reports_against: number;
  reports_filed: number;
  actions: Array<{ action: ModAction; reason: string | null; created_at: string }>;
  recent_content: Array<{
    kind: 'item';
    id: string;
    title: string;
    cover_path: string | null;
    hidden_at: string | null;
    created_at: string;
  }>;
}
