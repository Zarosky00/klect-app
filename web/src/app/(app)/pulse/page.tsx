import type { Metadata } from 'next';
import { pulseFeed } from '@/lib/api';
import { routes } from '@/lib/routes';
import { buildMetadata } from '@/lib/seo';
import { createClient } from '@/lib/supabase/server';
import type { PulseEntry } from '@/lib/types';
import { PulseStream } from './_components/PulseStream';

export const metadata: Metadata = buildMetadata({
  title: 'Pulse',
  description: 'What collectors are adding, reposting and saying.',
  path: routes.pulse,
  noindex: true,
});

const FIRST_PAGE = 25;

/**
 * Pulse is a signed-in surface — middleware already gated it, and `pulse_feed`
 * refuses the anon role anyway. The first Following page is resolved on the
 * server so the stream paints complete; since migration 0018 the envelope
 * embeds each entry's media and target, so no client-side attachment
 * resolution is needed. For-you is fetched on first tab switch.
 */
export default async function PulsePage() {
  const supabase = await createClient();

  let entries: PulseEntry[] = [];

  try {
    entries = await pulseFeed(supabase, { limit: FIRST_PAGE });
  } catch {
    // The client owns the retry surface; an empty first page is recoverable.
    entries = [];
  }

  return (
    <div className="mx-auto w-full max-w-160">
      <header className="glass sticky top-0 z-sticky border-b border-line-subtle px-4 py-3 sm:px-6">
        <h1 className="font-display text-title1 text-ink">Pulse</h1>
        <p className="text-caption text-ink-3">
          The collectors you follow — and the ones you should.
        </p>
      </header>

      <PulseStream initialEntries={entries} />
    </div>
  );
}
