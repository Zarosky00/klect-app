import { notFound } from 'next/navigation';
import { ThreadModal } from '@/components/thread/ThreadModal';
import { getPostThread } from '@/lib/api';
import { createClient } from '@/lib/supabase/server';

interface PageProps {
  params: Promise<{ id: string }>;
}

/**
 * Intercepting route. Navigating to `/p/<id>` from inside the app renders the
 * post thread over the current stream instead of replacing the page; the URL
 * still changes, so the thread is shareable and Back closes it. Mirrors the
 * `(.)closeup` pair.
 */
export default async function InterceptedPostThread({ params }: PageProps) {
  const { id } = await params;
  const supabase = await createClient();
  const thread = await getPostThread(supabase, id, { limit: 30, sort: 'top' });
  if (!thread || !thread.post.post_id) notFound();

  return <ThreadModal thread={thread} />;
}
