import { notFound } from 'next/navigation';
import { CloseupPanel } from '@/components/closeup/CloseupPanel';
import { getCloseup } from '@/lib/api';
import type { SurfaceEntityType } from '@/lib/entities';
import { createClient } from '@/lib/supabase/server';
import { getViewerBootstrap } from '@/lib/viewer';
import { EntityJsonLd } from './seo/EntityJsonLd';
import { SignedOutCta } from './SignedOutCta';

/**
 * The public, server-rendered page behind `/c/[id]`, `/s/[id]` and `/i/[id]`.
 *
 * All three levels share one implementation because all three are the same kind
 * of object: `get_closeup` returns the same envelope for each, RLS answers for
 * the anon role exactly as it does for a signed-in one, and the closeup body
 * branches on `entity_type` internally. So a collection page, a subcollection
 * page and an item page can never drift apart in what they support.
 *
 * Everything a crawler needs is in the first response: the title, the
 * description, the photography, the owner, the counts, the child grid, the
 * comments and a `CollectionPage`/`CreativeWork` + `BreadcrumbList` JSON-LD
 * graph. Nothing is behind a client fetch.
 */
export async function PublicEntityPage({
  type,
  id,
}: {
  type: SurfaceEntityType;
  id: string;
}) {
  const supabase = await createClient();
  const payload = await getCloseup(supabase, type, id);
  // `null` covers deleted, hidden, private and followers-only-and-you-are-not.
  if (!payload) notFound();

  const { user } = await getViewerBootstrap();
  const subject =
    type === 'collection'
      ? 'this collection'
      : type === 'subcollection'
        ? 'this shelf'
        : 'this';

  return (
    <div className="content-max px-0 py-0 md:px-6 md:py-8">
      <EntityJsonLd payload={payload} />

      <div className="overflow-hidden border-line bg-surface-1 md:rounded-xl md:border">
        <CloseupPanel payload={payload} />
      </div>

      {user ? null : (
        <div className="px-4 py-8 md:px-0">
          <SignedOutCta subject={subject} />
        </div>
      )}
    </div>
  );
}
