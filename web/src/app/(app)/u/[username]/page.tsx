import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import {
  getProfileByUsername,
  myProfileReactions,
  profileDiscussionActivity,
  profilePulseActivity,
} from '@/lib/api';
import { compactCount } from '@/lib/format';
import { profileHref } from '@/lib/routes';
import { buildMetadata, notFoundMetadata } from '@/lib/seo';
import { avatarUrl, bannerUrl } from '@/lib/storage';
import { createClient } from '@/lib/supabase/server';
import type {
  CursorPage,
  ProfileDiscussionItem,
  ProfilePulseView,
  ProfileReactionAction,
  ProfileReactionItem,
  ProfileSurface,
  PulseEntry,
} from '@/lib/types';
import { getViewerBootstrap } from '@/lib/viewer';
import {
  ProfileScreen,
  type ProfileInitialState,
  type ProfileMode,
  type ProfilePulseSection,
  type ProfileSurfView,
} from '@/components/social/ProfileScreen';
import {
  getRelationship,
  listCollectionSummaries,
  listItemSummaries,
  type EntitySummary,
  type RelationshipState,
} from '@/components/social/queries';

interface PageProps {
  params: Promise<{ username: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}

const first = (value: string | string[] | undefined): string | undefined =>
  Array.isArray(value) ? value[0] : value;
const member = <T extends string>(value: string | undefined, values: readonly T[], fallback: T): T =>
  values.includes(value as T) ? (value as T) : fallback;
const emptyPage = <T,>(): CursorPage<T> => ({ items: [], has_more: false, next_cursor: null });

export async function generateMetadata({ params }: PageProps): Promise<Metadata> {
  const { username } = await params;
  const supabase = await createClient();
  const profile = await getProfileByUsername(supabase, username);
  if (!profile) return notFoundMetadata('Profile');
  const stats = [
    `${compactCount(profile.collection_count)} collections`,
    `${compactCount(profile.item_count)} items`,
    `${compactCount(profile.follower_count)} followers`,
  ].join(' · ');
  return buildMetadata({
    title: `${profile.display_name} (@${profile.username})`,
    description: profile.bio ? `${profile.bio} — ${stats}` : stats,
    path: profileHref(profile.username),
    image: bannerUrl(profile.banner_path) ?? avatarUrl(profile.avatar_path),
    imageAlt: `${profile.display_name} on Klect`,
    type: 'profile',
    noindex: profile.account_visibility !== 'public' || profile.is_suspended,
  });
}

export default async function ProfilePage({ params, searchParams }: PageProps) {
  const { username } = await params;
  const query = await searchParams;
  const supabase = await createClient();
  const profile = await getProfileByUsername(supabase, username);
  if (!profile) notFound();

  const { user } = await getViewerBootstrap();
  const isSelf = user?.id === profile.id;
  const legacyTab = first(query['tab']);
  const requestedMode = first(query['mode']);
  let mode: ProfileMode = member(requestedMode, ['surf', 'pulse', 'activity'],
    legacyTab === 'posts' ? 'pulse' : legacyTab === 'likes' || legacyTab === 'saves' ? 'activity' : 'surf');
  if (mode === 'activity' && !isSelf) mode = 'surf';

  const view = first(query['view']);
  const surfView: ProfileSurfView = member(
    view ?? legacyTab,
    ['collections', 'items'],
    'collections',
  );
  const pulseSection: ProfilePulseSection = member(
    view ?? (legacyTab === 'posts' ? 'posts' : undefined),
    ['posts', 'replies', 'media'],
    'posts',
  );
  const postView: Exclude<ProfilePulseView, 'media'> = member(
    first(query['filter']),
    ['all', 'originals', 'reposts', 'quotes'],
    'all',
  );
  const discussionSurface: ProfileSurface = member(
    first(query['surface']),
    ['all', 'surf', 'pulse'],
    'all',
  );
  const activityAction: ProfileReactionAction =
    (view ?? legacyTab) === 'saves' ? 'save' : 'like';
  const reactionSurface = member(first(query['surface']), ['surf', 'pulse'], 'surf');

  const relationshipPromise = user
    ? getRelationship(supabase, user.id, profile.id)
    : Promise.resolve<RelationshipState>({ following: false, blocked: false, muted: false });

  let summaries: EntitySummary[] = [];
  let pulsePage: CursorPage<PulseEntry> | null = null;
  let discussionPage: CursorPage<ProfileDiscussionItem> | null = null;
  let reactionPage: CursorPage<ProfileReactionItem> | null = null;

  try {
    if (mode === 'surf') {
      summaries = surfView === 'collections'
        ? await listCollectionSummaries(supabase, profile.id)
        : await listItemSummaries(supabase, profile.id);
    } else if (mode === 'pulse' && pulseSection === 'replies') {
      discussionPage = await profileDiscussionActivity(
        supabase,
        profile.id,
        discussionSurface,
        { limit: 20 },
      );
    } else if (mode === 'pulse') {
      pulsePage = await profilePulseActivity(
        supabase,
        profile.id,
        pulseSection === 'media' ? 'media' : postView,
        { limit: 20 },
      );
    } else if (isSelf) {
      reactionPage = await myProfileReactions(
        supabase,
        activityAction,
        reactionSurface,
        { limit: 24 },
      );
    }
  } catch {
    if (mode === 'pulse' && pulseSection === 'replies') discussionPage = emptyPage();
    else if (mode === 'pulse') pulsePage = emptyPage();
    else if (mode === 'activity') reactionPage = emptyPage();
  }

  const initial: ProfileInitialState = {
    mode,
    surfView,
    pulseSection,
    postView,
    discussionSurface,
    activityAction,
    reactionSurface,
    summaries,
    pulsePage,
    discussionPage,
    reactionPage,
  };

  return (
    <ProfileScreen
      profile={profile}
      relationship={await relationshipPromise}
      initial={initial}
    />
  );
}
