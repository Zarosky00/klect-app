import type { Metadata } from 'next';
import { redirect } from 'next/navigation';
import { routes } from '@/lib/routes';
import { buildMetadata } from '@/lib/seo';
import { createClient } from '@/lib/supabase/server';
import { getViewerBootstrap } from '@/lib/viewer';
import { NotificationsFeed } from '@/components/social/NotificationsFeed';
import { listNotificationEntries } from '@/components/social/queries';

export const metadata: Metadata = buildMetadata({
  title: 'Notifications',
  description: 'Likes, saves, reposts, comments, follows, matches and moderation notices.',
  path: routes.notifications,
  noindex: true,
});

export default async function NotificationsPage() {
  const { user } = await getViewerBootstrap();
  // Middleware gates `/notifications`; this is the belt to that braces.
  if (!user) redirect(`${routes.signIn}?next=${encodeURIComponent(routes.notifications)}`);

  const supabase = await createClient();
  const entries = await listNotificationEntries(supabase, { limit: 40 });

  return <NotificationsFeed initialEntries={entries} viewerId={user.id} />;
}
