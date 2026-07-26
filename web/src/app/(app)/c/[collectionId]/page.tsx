import type { Metadata } from 'next';
import { PublicEntityPage } from '@/components/surf/PublicEntityPage';
import { getCollection, getProfileById } from '@/lib/api';
import { compactCount, plural } from '@/lib/format';
import { collectionHref } from '@/lib/routes';
import { buildMetadata, notFoundMetadata } from '@/lib/seo';
import { mediaUrl } from '@/lib/storage';
import { createClient } from '@/lib/supabase/server';

interface PageProps {
  params: Promise<{ collectionId: string }>;
}

export async function generateMetadata({ params }: PageProps): Promise<Metadata> {
  const { collectionId } = await params;
  const supabase = await createClient();
  const collection = await getCollection(supabase, collectionId);
  if (!collection) return notFoundMetadata('Collection');

  const owner = await getProfileById(supabase, collection.user_id);
  const summary = `${compactCount(collection.item_count)} ${plural(collection.item_count, 'item')} in ${compactCount(collection.subcollection_count)} ${plural(collection.subcollection_count, 'subcollection')}`;

  return buildMetadata({
    title: owner ? `${collection.name} by ${owner.display_name}` : collection.name,
    description: collection.description ?? summary,
    path: collectionHref(collection.id),
    image: mediaUrl(collection.cover_path),
    imageAlt: collection.name,
    type: 'article',
    ...(owner ? { authors: [owner.display_name] } : {}),
    noindex: collection.visibility !== 'public' || collection.hidden_at !== null,
  });
}

/**
 * The top level of the hierarchy, in public. Server-rendered so it works logged
 * out and indexes well — the anon role may call `get_closeup`, and RLS decides
 * what comes back rather than the client deciding what to ask for.
 */
export default async function CollectionPage({ params }: PageProps) {
  const { collectionId } = await params;
  return <PublicEntityPage type="collection" id={collectionId} />;
}
