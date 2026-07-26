import type { Metadata } from 'next';
import { redirect } from 'next/navigation';
import { routes } from '@/lib/routes';
import { buildMetadata } from '@/lib/seo';
import { getViewerBootstrap } from '@/lib/viewer';
import { SettingsNotificationsForm } from '@/components/social/SettingsNotificationsForm';

export const metadata: Metadata = buildMetadata({
  title: 'Notification settings',
  description: 'Which notification types pop banners on this device.',
  path: routes.settingsNotifications,
  noindex: true,
});

/**
 * Mutes are a device preference (localStorage), mirroring mobile — so this
 * page has no server data to fetch beyond the auth gate.
 */
export default async function SettingsNotificationsPage() {
  const { user } = await getViewerBootstrap();
  if (!user) {
    redirect(`${routes.signIn}?next=${encodeURIComponent(routes.settingsNotifications)}`);
  }

  return <SettingsNotificationsForm />;
}
