import type { Metadata } from 'next';
import { AppearanceSettings } from '@/components/settings/AppearanceSettings';
import { routes } from '@/lib/routes';
import { buildMetadata } from '@/lib/seo';

export const metadata: Metadata = buildMetadata({
  title: 'Appearance',
  description: 'Follow your system theme, or pin Klect to dark or light.',
  path: routes.settingsAppearance,
  noindex: true,
});

export default function SettingsAppearancePage() {
  return <AppearanceSettings />;
}
