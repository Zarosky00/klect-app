import type { Metadata } from 'next';
import { redirect } from 'next/navigation';
import { listBlockedUsers } from '@/lib/api';
import { routes } from '@/lib/routes';
import { buildMetadata } from '@/lib/seo';
import { createClient } from '@/lib/supabase/server';
import { getViewerBootstrap } from '@/lib/viewer';
import { SettingsBlockedList } from '@/components/social/SettingsBlockedList';
import { listMutedUsers } from '@/components/social/queries';

export const metadata: Metadata = buildMetadata({
  title: 'Blocked and muted',
  description: 'People you have blocked or muted.',
  path: routes.settingsBlocked,
  noindex: true,
});

export default async function SettingsBlockedPage() {
  const { user } = await getViewerBootstrap();
  if (!user) redirect(`${routes.signIn}?next=${encodeURIComponent(routes.settingsBlocked)}`);

  const supabase = await createClient();
  const [blocked, muted] = await Promise.all([
    listBlockedUsers(supabase),
    listMutedUsers(supabase),
  ]);

  return <SettingsBlockedList blocked={blocked} muted={muted} />;
}
