/**
 * Reads the console needs that are not part of the shared `@/lib/api` surface.
 *
 * Everything here is a plain table read, guarded by RLS: `profiles`,
 * `collections`, `subcollections` and `items` are all readable by staff
 * (including rows hidden or private to everyone else — `visible_to_me()` and
 * `can_view_entity()` both short-circuit on `is_staff()`), and `audit_log` is
 * `is_admin()`-only. No privileged key is involved: a moderator hitting the
 * audit query gets a Postgrest `42501`, which the UI surfaces as "Forbidden"
 * rather than swallowing.
 *
 * `@/lib/api` owns the RPC surface; this file deliberately adds no wrapper
 * around an RPC that already exists there.
 */
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '@/lib/database.types';
import type { AppRole, ReportStatus, SurfaceEntityType, Visibility } from '@/lib/entities';
import { KlectError, errorMessage, toKlectError } from '@/lib/errors';

type Client = SupabaseClient<Database>;

/**
 * The database's own words for a failure.
 *
 * `toKlectError` maps Postgrest `42501` to the copy the *public* app needs
 * ("You can no longer interact with this"), which is exactly wrong in the
 * console: here a `42501` is the RPC's `is_staff()` / `is_admin()` /
 * "Superadmin only" check refusing, and the operator needs to read that.
 */
export function serverErrorText(error: unknown): string {
  const seen = new Set<unknown>();
  let current: unknown = error;

  while (current && !seen.has(current)) {
    seen.add(current);
    if (typeof current === 'object' && 'message' in current && !(current instanceof KlectError)) {
      const message = (current as { message?: unknown }).message;
      if (typeof message === 'string' && message) return message;
    }
    current = current instanceof Error ? current.cause : null;
  }
  return errorMessage(error);
}

export interface AdminErrorInfo {
  message: string;
  /** The database said no — a role problem, not a transient one. */
  refused: boolean;
}

/**
 * Serialisable failure description, so a Server Component can hand a real error
 * to a Client Component without shipping an `Error` instance across the wire.
 */
export function describeServerError(error: unknown): AdminErrorInfo {
  const klect = toKlectError(error);
  return {
    message: serverErrorText(error),
    refused: klect.kind === 'forbidden' || klect.kind === 'unauthorized',
  };
}

/** Postgrest treats `,` `.` `(` `)` as syntax inside `or=`; `%` and `_` are LIKE wildcards. */
export function sanitiseSearch(value: string): string {
  return value
    .trim()
    .replace(/[,.()%_*\\"']/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

const OWNER_FRAGMENT = 'id, username, display_name, avatar_path, is_verified';

export interface AdminPersonRef {
  id: string;
  username: string;
  display_name: string;
  avatar_path: string | null;
  is_verified: boolean;
}

/* ── users ────────────────────────────────────────────────────────────────── */

export interface AdminUserRow {
  id: string;
  username: string;
  display_name: string;
  avatar_path: string | null;
  is_verified: boolean;
  is_suspended: boolean;
  suspended_until: string | null;
  account_visibility: Visibility;
  follower_count: number;
  collection_count: number;
  item_count: number;
  created_at: string;
  last_seen_at: string | null;
}

const USER_COLUMNS =
  'id, username, display_name, avatar_path, is_verified, is_suspended, suspended_until, account_visibility, follower_count, collection_count, item_count, created_at, last_seen_at';

export type UserFilter = 'all' | 'suspended' | 'verified' | 'staff';

export const USER_FILTERS: readonly UserFilter[] = ['all', 'suspended', 'verified', 'staff'];

export const USER_FILTER_LABELS: Record<UserFilter, string> = {
  all: 'All',
  suspended: 'Suspended',
  verified: 'Verified',
  staff: 'Staff',
};

export async function listAdminUsers(
  client: Client,
  params: { q?: string; filter?: UserFilter; limit?: number } = {},
): Promise<AdminUserRow[]> {
  const limit = params.limit ?? 40;
  const filter = params.filter ?? 'all';

  let staffIds: string[] | null = null;
  if (filter === 'staff') {
    const { data, error } = await client.from('user_roles').select('user_id');
    if (error) throw toKlectError(error);
    staffIds = [...new Set((data ?? []).map((row) => row.user_id))];
    if (staffIds.length === 0) return [];
  }

  const q = sanitiseSearch(params.q ?? '');

  let filtered = client.from('profiles').select(USER_COLUMNS);
  if (q) filtered = filtered.or(`username.ilike.%${q}%,display_name.ilike.%${q}%`);
  if (filter === 'suspended') filtered = filtered.eq('is_suspended', true);
  if (filter === 'verified') filtered = filtered.eq('is_verified', true);
  if (staffIds) filtered = filtered.in('id', staffIds);

  // Newest accounts first when browsing; most-followed first when searching, so
  // a name collision surfaces the account a report is most likely about.
  const ordered = q
    ? filtered.order('follower_count', { ascending: false })
    : filtered.order('created_at', { ascending: false });

  const { data, error } = await ordered.limit(limit).returns<AdminUserRow[]>();
  if (error) throw toKlectError(error);
  return data ?? [];
}

/** One account by id — for a deep link that lands outside the current page. */
export async function getAdminUser(client: Client, id: string): Promise<AdminUserRow | null> {
  const { data, error } = await client
    .from('profiles')
    .select(USER_COLUMNS)
    .eq('id', id)
    .maybeSingle()
    .returns<AdminUserRow | null>();
  if (error) throw toKlectError(error);
  return data ?? null;
}

/** Roles for a batch of users — the list column, without an RPC per row. */
export async function listRolesFor(
  client: Client,
  userIds: string[],
): Promise<Record<string, AppRole[]>> {
  if (userIds.length === 0) return {};
  const { data, error } = await client
    .from('user_roles')
    .select('user_id, role')
    .in('user_id', userIds);
  if (error) throw toKlectError(error);

  const map: Record<string, AppRole[]> = {};
  for (const row of data ?? []) {
    const bucket = map[row.user_id];
    if (bucket) bucket.push(row.role);
    else map[row.user_id] = [row.role];
  }
  return map;
}

/** Everyone who holds any role — the audit actor filter and the staff tab. */
export async function listStaffProfiles(client: Client): Promise<AdminPersonRef[]> {
  const { data: roleRows, error: roleError } = await client.from('user_roles').select('user_id');
  if (roleError) throw toKlectError(roleError);

  const ids = [...new Set((roleRows ?? []).map((row) => row.user_id))];
  if (ids.length === 0) return [];

  const { data, error } = await client
    .from('profiles')
    .select(OWNER_FRAGMENT)
    .in('id', ids)
    .order('username', { ascending: true })
    .returns<AdminPersonRef[]>();
  if (error) throw toKlectError(error);
  return data ?? [];
}

/* ── content ──────────────────────────────────────────────────────────────── */

export interface AdminContentRow {
  type: SurfaceEntityType;
  id: string;
  title: string;
  cover_path: string | null;
  cover_blurhash: string | null;
  /** `null` on a subcollection/item means "inherit from the parent". */
  visibility: Visibility | null;
  hidden_at: string | null;
  deleted_at: string | null;
  created_at: string;
  like_count: number;
  view_count: number;
  /** Items for a collection/subcollection, media for an item. */
  child_count: number;
  owner: AdminPersonRef | null;
}

export type ContentVisibilityFilter = 'all' | 'visible' | 'hidden';

export const CONTENT_FILTERS: readonly ContentVisibilityFilter[] = ['all', 'visible', 'hidden'];

export const CONTENT_FILTER_LABELS: Record<ContentVisibilityFilter, string> = {
  all: 'All',
  visible: 'Visible',
  hidden: 'Hidden',
};

interface RawContentRow {
  id: string;
  name?: string | null;
  title?: string | null;
  cover_path: string | null;
  cover_blurhash: string | null;
  visibility: Visibility | null;
  hidden_at: string | null;
  deleted_at: string | null;
  created_at: string;
  like_count: number;
  view_count: number;
  item_count?: number | null;
  media_count?: number | null;
  owner: AdminPersonRef | null;
}

export interface ListContentParams {
  type: SurfaceEntityType;
  filter?: ContentVisibilityFilter;
  q?: string;
  limit?: number;
  offset?: number;
}

/**
 * One shape over three tables. The three branches are written out rather than
 * derived from a variable table name because a union-typed Postgrest builder
 * loses every filter overload.
 */
export async function listAdminContent(
  client: Client,
  params: ListContentParams,
): Promise<AdminContentRow[]> {
  const filter = params.filter ?? 'all';
  const limit = params.limit ?? 30;
  const offset = params.offset ?? 0;
  const q = sanitiseSearch(params.q ?? '');
  const to = offset + limit - 1;

  const shared =
    'cover_path, cover_blurhash, visibility, hidden_at, deleted_at, created_at, like_count, view_count';

  let rows: RawContentRow[] = [];

  if (params.type === 'collection') {
    let query = client
      .from('collections')
      .select(`id, name, ${shared}, item_count, owner:profiles!collections_user_id_fkey(${OWNER_FRAGMENT})`);
    if (filter === 'hidden') query = query.not('hidden_at', 'is', null);
    if (filter === 'visible') query = query.is('hidden_at', null);
    if (q) query = query.ilike('name', `%${q}%`);
    const { data, error } = await query
      .order(filter === 'hidden' ? 'hidden_at' : 'created_at', { ascending: false })
      .range(offset, to)
      .returns<RawContentRow[]>();
    if (error) throw toKlectError(error);
    rows = data ?? [];
  } else if (params.type === 'subcollection') {
    let query = client
      .from('subcollections')
      .select(
        `id, name, ${shared}, item_count, owner:profiles!subcollections_user_id_fkey(${OWNER_FRAGMENT})`,
      );
    if (filter === 'hidden') query = query.not('hidden_at', 'is', null);
    if (filter === 'visible') query = query.is('hidden_at', null);
    if (q) query = query.ilike('name', `%${q}%`);
    const { data, error } = await query
      .order(filter === 'hidden' ? 'hidden_at' : 'created_at', { ascending: false })
      .range(offset, to)
      .returns<RawContentRow[]>();
    if (error) throw toKlectError(error);
    rows = data ?? [];
  } else {
    let query = client
      .from('items')
      .select(`id, title, ${shared}, media_count, owner:profiles!items_user_id_fkey(${OWNER_FRAGMENT})`);
    if (filter === 'hidden') query = query.not('hidden_at', 'is', null);
    if (filter === 'visible') query = query.is('hidden_at', null);
    if (q) query = query.ilike('title', `%${q}%`);
    const { data, error } = await query
      .order(filter === 'hidden' ? 'hidden_at' : 'created_at', { ascending: false })
      .range(offset, to)
      .returns<RawContentRow[]>();
    if (error) throw toKlectError(error);
    rows = data ?? [];
  }

  return rows.map((row) => ({
    type: params.type,
    id: row.id,
    title: row.title ?? row.name ?? 'Untitled',
    cover_path: row.cover_path,
    cover_blurhash: row.cover_blurhash,
    visibility: row.visibility ?? null,
    hidden_at: row.hidden_at,
    deleted_at: row.deleted_at,
    created_at: row.created_at,
    like_count: row.like_count,
    view_count: row.view_count,
    child_count: row.media_count ?? row.item_count ?? 0,
    owner: row.owner ?? null,
  }));
}

/* ── audit log ────────────────────────────────────────────────────────────── */

/**
 * Every `perform public.audit(...)` call site in the database, so the filter is
 * populated even when the log is empty. An action found in a fetched page that
 * is not listed here is merged in by the UI.
 */
export const AUDIT_ACTIONS = [
  'report.resolve',
  'entity.moderate',
  'user.state',
  'user.verify',
  'role.change',
] as const;

export const AUDIT_ACTION_LABELS: Record<string, string> = {
  'report.resolve': 'Report resolved',
  'entity.moderate': 'Content hidden / restored',
  'user.state': 'Account suspended / restored',
  'user.verify': 'Verification changed',
  'role.change': 'Role granted / revoked',
};

export function auditActionLabel(action: string): string {
  return AUDIT_ACTION_LABELS[action] ?? action;
}

export interface AuditEntry {
  id: number;
  action: string;
  actor_id: string | null;
  target_table: string | null;
  target_id: string | null;
  detail: unknown;
  created_at: string;
  actor: AdminPersonRef | null;
}

export interface ListAuditParams {
  action?: string;
  actorId?: string;
  limit?: number;
  offset?: number;
}

export async function listAuditEntries(
  client: Client,
  params: ListAuditParams = {},
): Promise<AuditEntry[]> {
  const limit = params.limit ?? 50;
  const offset = params.offset ?? 0;

  let query = client
    .from('audit_log')
    .select(
      `id, action, actor_id, target_table, target_id, detail, created_at, actor:profiles!audit_log_actor_id_fkey(${OWNER_FRAGMENT})`,
    );

  if (params.action) query = query.eq('action', params.action);
  if (params.actorId) query = query.eq('actor_id', params.actorId);

  const { data, error } = await query
    .order('created_at', { ascending: false })
    .order('id', { ascending: false })
    .range(offset, offset + limit - 1)
    .returns<AuditEntry[]>();
  if (error) throw toKlectError(error);
  return data ?? [];
}

/* ── report queue counts ──────────────────────────────────────────────────── */

export const REPORT_STATUSES: readonly ReportStatus[] = [
  'open',
  'reviewing',
  'actioned',
  'dismissed',
];

export const REPORT_STATUS_LABELS: Record<ReportStatus, string> = {
  open: 'Open',
  reviewing: 'Reviewing',
  actioned: 'Actioned',
  dismissed: 'Dismissed',
};

export type ReportCounts = Record<ReportStatus, number>;

export const EMPTY_REPORT_COUNTS: ReportCounts = {
  open: 0,
  reviewing: 0,
  actioned: 0,
  dismissed: 0,
};

/**
 * Queue depth per tab. These are workload numbers with no counter column behind
 * them — unlike social counts, which are always read off the entity row.
 */
export async function countReportsByStatus(client: Client): Promise<ReportCounts> {
  const results = await Promise.all(
    REPORT_STATUSES.map(async (status) => {
      const { count, error } = await client
        .from('reports')
        .select('id', { count: 'exact', head: true })
        .eq('status', status);
      if (error) throw toKlectError(error);
      return [status, count ?? 0] as const;
    }),
  );

  return { ...EMPTY_REPORT_COUNTS, ...Object.fromEntries(results) };
}
