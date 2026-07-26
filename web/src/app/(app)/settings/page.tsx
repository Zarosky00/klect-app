import type { Metadata } from 'next';
import { redirect } from 'next/navigation';
import { getProfileById } from '@/lib/api';
import { routes } from '@/lib/routes';
import { buildMetadata } from '@/lib/seo';
import { createClient } from '@/lib/supabase/server';
import { getViewerBootstrap } from '@/lib/viewer';
import { DangerZone } from '@/components/social/DangerZone';
import { SettingsProfileForm } from '@/components/social/SettingsProfileForm';

export const metadata: Metadata = buildMetadata({
  title: 'Profile settings',
  description: 'Your handle, display name, bio, avatar and banner.',
  path: routes.settings,
  noindex: true,
});

export default async function SettingsProfilePage() {
  const { user } = await getViewerBootstrap();
  if (!user) redirect(`${routes.signIn}?next=${encodeURIComponent(routes.settings)}`);

  const supabase = await createClient();
  const profile = await getProfileById(supabase, user.id);
  // The signup trigger creates the profile, so a missing row means onboarding
  // never finished — send them back rather than render an empty form.
  if (!profile) redirect(routes.onboarding);

  return (
    <div className="flex flex-col gap-12">
      <SettingsProfileForm profile={profile} />
      <DangerZone profile={profile} />
    </div>
  );
}
