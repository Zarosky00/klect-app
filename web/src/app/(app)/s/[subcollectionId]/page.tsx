import type { Metadata } from 'next';
import { PublicEntityPage } from '@/components/surf/PublicEntityPage';
import { getCollection, getProfileById, getSubcollection } from '@/lib/api';
import { compactCount, plural } from '@/lib/format';
import { subcollectionHref } from '@/lib/routes';
import { buildMetadata, notFoundMetadata } from '@/lib/seo';
import { mediaUrl } from '@/lib/storage';
import { createClient } from '@/lib/supabase/server';

interface PageProps {
  params: Promise<{ subcollectionId: string }>;
}

export async function generateMetadata({ params }: PageProps): Promise<Metadata> {
  const { subcollectionId } = await params;
  const supabase = await createClient();
  const subcollection = await getSubcollection(supabase, subcollectionId);
  if (!subcollection) return notFoundMetadata('Subcollection');

  const [owner, parent] = await Promise.all([
    getProfileById(supabase, subcollection.user_id),
    getCollection(supabase, subcollection.collection_id),
  ]);

  const summary = `${compactCount(subcollection.item_count)} ${plural(subcollection.item_count, 'item')}${parent ? ` in ${parent.name}` : ''}`;

  return buildMetadata({
    title: parent ? `${subcollection.name} — ${parent.name}` : subcollection.name,
    description: subcollection.description ?? summary,
    path: subcollectionHref(subcollection.id),
    image: mediaUrl(subcollection.cover_path),
    imageAlt: subcollection.name,
    type: 'article',
    ...(owner ? { authors: [owner.display_name] } : {}),
    noindex: subcollection.hidden_at !== null,
  });
}

/**
 * The middle level. It is a first-class social object in its own right — the
 * same action bar, comments, counts and overflow as a collection or an item —
 * which is exactly what a shelf-inside-a-shelf needs to be for the hierarchy to
 * mean anything.
 */
export default async function SubcollectionPage({ params }: PageProps) {
  const { subcollectionId } = await params;
  return <PublicEntityPage type="subcollection" id={subcollectionId} />;
}
