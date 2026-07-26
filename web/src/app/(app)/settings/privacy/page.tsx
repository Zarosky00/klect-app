import type { Metadata } from 'next';
import { redirect } from 'next/navigation';
import { getProfileById } from '@/lib/api';
import { routes } from '@/lib/routes';
import { buildMetadata } from '@/lib/seo';
import { createClient } from '@/lib/supabase/server';
import { getViewerBootstrap } from '@/lib/viewer';
import { SettingsPrivacyForm } from '@/components/social/SettingsPrivacyForm';

export const metadata: Metadata = buildMetadata({
  title: 'Privacy settings',
  description: 'Who can see your account, and who can message you.',
  path: routes.settingsPrivacy,
  noindex: true,
});

export default async function SettingsPrivacyPage() {
  const { user } = await getViewerBootstrap();
  if (!user) redirect(`${routes.signIn}?next=${encodeURIComponent(routes.settingsPrivacy)}`);

  const supabase = await createClient();
  const profile = await getProfileById(supabase, user.id);
  if (!profile) redirect(routes.onboarding);

  return <SettingsPrivacyForm profile={profile} />;
}
