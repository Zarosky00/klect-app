import type { Metadata } from 'next';
import { PublicEntityPage } from '@/components/surf/PublicEntityPage';
import { getItem, getProfileById } from '@/lib/api';
import { compactCount, plural } from '@/lib/format';
import { itemHref } from '@/lib/routes';
import { buildMetadata, notFoundMetadata } from '@/lib/seo';
import { mediaUrl } from '@/lib/storage';
import { createClient } from '@/lib/supabase/server';

interface PageProps {
  params: Promise<{ itemId: string }>;
}

export async function generateMetadata({ params }: PageProps): Promise<Metadata> {
  const { itemId } = await params;
  const supabase = await createClient();
  const item = await getItem(supabase, itemId);
  if (!item) return notFoundMetadata('Item');

  const owner = await getProfileById(supabase, item.user_id);
  const facts = [item.brand, item.model, item.year ? String(item.year) : null]
    .filter(Boolean)
    .join(' · ');

  return buildMetadata({
    title: owner ? `${item.title} — ${owner.display_name}` : item.title,
    description:
      item.description ??
      (facts || `${compactCount(item.media_count)} ${plural(item.media_count, 'photo')}`),
    path: itemHref(item.id),
    image: mediaUrl(item.cover_path),
    imageAlt: item.title,
    type: 'article',
    publishedTime: item.created_at,
    ...(owner ? { authors: [owner.display_name] } : {}),
    noindex: item.visibility === 'private' || item.hidden_at !== null,
  });
}

/**
 * The leaf: one thing, with every photograph of it, the catalogue card the
 * collector filled in, the breadcrumb back up the hierarchy, its siblings on
 * the same shelf, and the conversation about it.
 */
export default async function ItemPage({ params }: PageProps) {
  const { itemId } = await params;
  return <PublicEntityPage type="item" id={itemId} />;
}
