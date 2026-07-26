import type { Metadata } from 'next';
import { redirect } from 'next/navigation';
import { routes } from '@/lib/routes';
import { buildMetadata } from '@/lib/seo';
import { createClient } from '@/lib/supabase/server';
import { getViewerBootstrap } from '@/lib/viewer';
import { CreateFlow } from '@/components/social/CreateFlow';
import { listCollectionSummaries } from '@/components/social/queries';

export const metadata: Metadata = buildMetadata({
  title: 'Create',
  description: 'Start a collection, add a subcollection, or add an item with photos.',
  path: routes.create,
  noindex: true,
});

interface PageProps {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}

function firstParam(value: string | string[] | undefined): string | null {
  const first = Array.isArray(value) ? value[0] : value;
  return first?.trim() || null;
}

/**
 * `?collection=` and `?mode=` let a collection page deep-link straight into
 * "add an item here", which is what keeps the create path at three taps or
 * fewer from anywhere.
 */
export default async function CreatePage({ searchParams }: PageProps) {
  const { user } = await getViewerBootstrap();
  if (!user) redirect(`${routes.signIn}?next=${encodeURIComponent(routes.create)}`);

  const query = await searchParams;
  const supabase = await createClient();
  const collections = await listCollectionSummaries(supabase, user.id, { limit: 100 });

  const mode = firstParam(query['mode']);
  const initialMode =
    mode === 'collection' || mode === 'subcollection' || mode === 'item' ? mode : 'item';

  return (
    <CreateFlow
      collections={collections}
      initialCollectionId={firstParam(query['collection'])}
      initialMode={initialMode}
    />
  );
}
