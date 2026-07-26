import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { getProfileByUsername } from '@/lib/api';
import { compactCount } from '@/lib/format';
import { profileHref } from '@/lib/routes';
import { buildMetadata, notFoundMetadata } from '@/lib/seo';
import { avatarUrl, bannerUrl } from '@/lib/storage';
import { createClient } from '@/lib/supabase/server';
import { getViewerBootstrap } from '@/lib/viewer';
import { ProfileScreen, type ProfileTab } from '@/components/social/ProfileScreen';
import {
  getRelationship,
  listCollectionSummaries,
  listInteractedSummaries,
  listItemSummaries,
  type EntitySummary,
  type RelationshipState,
} from '@/components/social/queries';

interface PageProps {
  params: Promise<{ username: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}

const TABS: readonly ProfileTab[] = ['collections', 'items', 'likes', 'saves'];

function resolveTab(value: string | string[] | undefined): ProfileTab {
  const first = Array.isArray(value) ? value[0] : value;
  return (TABS as readonly string[]).includes(first ?? '')
    ? (first as ProfileTab)
    : 'collections';
}

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

/**
 * Server-rendered on purpose: this is a public, indexable page, so the header,
 * the counts and the first page of cards have to be in the HTML rather than
 * behind a spinner. `ProfileScreen` takes over for tabs and interaction.
 *
 * RLS does the visibility work — a private account simply returns no rows, so
 * there is no second permission model to keep in sync here.
 */
export default async function ProfilePage({ params, searchParams }: PageProps) {
  const { username } = await params;
  const query = await searchParams;
  const supabase = await createClient();

  const profile = await getProfileByUsername(supabase, username);
  if (!profile) notFound();

  const { user } = await getViewerBootstrap();
  const tab = resolveTab(query['tab']);

  const [relationship, summaries]: [RelationshipState, EntitySummary[]] = await Promise.all([
    user
      ? getRelationship(supabase, user.id, profile.id)
      : Promise.resolve<RelationshipState>({ following: false, blocked: false, muted: false }),
    tab === 'collections'
      ? listCollectionSummaries(supabase, profile.id)
      : tab === 'items'
        ? listItemSummaries(supabase, profile.id)
        : listInteractedSummaries(supabase, tab === 'likes' ? 'likes' : 'saves', profile.id),
  ]);

  return (
    <ProfileScreen
      profile={profile}
      relationship={relationship}
      initialTab={tab}
      initialSummaries={summaries}
    />
  );
}
