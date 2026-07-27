import type { Metadata } from 'next';
import { ButtonLink } from '@/components/ui/Button';
import { Icon } from '@/components/ui/Icon';
import { ANDROID_APK_URL, KLECT_APP_VERSION } from '@/lib/app-version';
import { routes } from '@/lib/routes';
import { buildMetadata } from '@/lib/seo';

export const metadata: Metadata = buildMetadata({
  title: 'App & downloads',
  description: 'Klect web update status and the latest Android app download.',
  path: routes.settingsApp,
  noindex: true,
});

export default function SettingsAppPage() {
  return (
    <section className="flex flex-col gap-6">
      <header>
        <h2 className="font-display text-title1 text-ink">App & downloads</h2>
        <p className="mt-1 text-callout text-ink-2">
          The website updates automatically. Android builds can also check for updates from
          Settings inside the app.
        </p>
      </header>

      <div className="grid gap-3 sm:grid-cols-2">
        <article className="rounded-lg border border-line bg-surface-1 p-5">
          <span className="grid size-10 place-items-center rounded-full bg-surface-3 text-ink-2">
            <Icon name="monitor" size="md" />
          </span>
          <h3 className="mt-4 text-title3 text-ink">Web app</h3>
          <p className="mt-1 text-caption text-ink-2">
            Always up to date. Refresh this page whenever you want the newest deployed version.
          </p>
          <p className="mt-4 inline-flex items-center gap-1.5 text-label text-success">
            <Icon name="check" size="xs" />
            No download required
          </p>
        </article>

        <article className="rounded-lg border border-line bg-surface-1 p-5">
          <span className="grid size-10 place-items-center rounded-full bg-accent-subtle text-accent">
            <Icon name="download" size="md" />
          </span>
          <h3 className="mt-4 text-title3 text-ink">Android app</h3>
          <p className="mt-1 text-caption text-ink-2">
            Version {KLECT_APP_VERSION}. Download the latest APK, then allow your browser to open
            Android&apos;s installer.
          </p>
          <ButtonLink
            href={ANDROID_APK_URL}
            target="_blank"
            rel="noopener noreferrer"
            iconLeft="download"
            size="sm"
            className="mt-4"
          >
            Download latest APK
          </ButtonLink>
        </article>
      </div>
    </section>
  );
}
