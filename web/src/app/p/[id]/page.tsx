import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { Wordmark } from '@/components/chrome/Wordmark';
import { PostThreadView } from '@/components/thread/PostThreadView';
import { Icon } from '@/components/ui/Icon';
import { getPostThread } from '@/lib/api';
import { truncate } from '@/lib/format';
import { postHref, routes } from '@/lib/routes';
import { buildMetadata, notFoundMetadata } from '@/lib/seo';
import { mediaUrl } from '@/lib/storage';
import { createClient } from '@/lib/supabase/server';

interface PageProps {
  params: Promise<{ id: string }>;
}

/** `get_post_thread` is anon-callable, so crawlers get a real card. */
export async function generateMetadata({ params }: PageProps): Promise<Metadata> {
  const { id } = await params;
  const supabase = await createClient();
  const thread = await getPostThread(supabase, id, { limit: 1 }).catch(() => null);
  if (!thread) return notFoundMetadata('Post');

  const post = thread.post;
  const authorName = post.author?.display_name ?? 'A collector';
  const excerpt = post.body ? truncate(post.body.replace(/\s+/g, ' '), 80) : null;
  const cover = post.media?.[0]?.storage_path ?? post.target?.cover_path ?? null;

  return buildMetadata({
    title: excerpt ? `${authorName}: “${excerpt}”` : `${authorName} on Klect`,
    description: post.body,
    path: postHref(id),
    image: mediaUrl(cover),
    imageAlt: excerpt ?? `${authorName} on Klect`,
    type: 'article',
    publishedTime: post.created_at ?? post.sort_at,
    authors: [authorName],
  });
}

/**
 * The full-page fallback for `/p/[id]` — the post thread (W3).
 *
 * In-app navigations are intercepted by `app/@modal/(.)p/…` and render the
 * thread over the current stream; a hard load, a shared link or a refresh
 * lands here instead — same payload, same component, so the two can never
 * disagree. Mirrors the closeup pair exactly.
 */
export default async function PostThreadPage({ params }: PageProps) {
  const { id } = await params;
  const supabase = await createClient();
  const thread = await getPostThread(supabase, id, { limit: 30, sort: 'top' });
  if (!thread || !thread.post.post_id) notFound();

  return (
    <div className="flex min-h-dvh flex-col">
      <header className="glass sticky top-0 z-sticky flex items-center gap-4 border-b border-line-subtle px-4 py-3 sm:px-6">
        <Link
          href={routes.pulse}
          className="focus-ring inline-flex items-center gap-2 rounded-md px-2 py-1 text-label text-ink-2 transition-colors dur-fast hover:text-ink"
        >
          <Icon name="arrow-left" size="md" />
          Back to Pulse
        </Link>
        <div className="flex-1" />
        <Wordmark size="sm" />
      </header>

      <main id="main" className="mx-auto w-full max-w-160 flex-1 px-0 py-0 md:px-6 md:py-8">
        <div className="overflow-hidden border-line bg-surface-1 md:rounded-xl md:border">
          <PostThreadView thread={thread} />
        </div>
      </main>
    </div>
  );
}
