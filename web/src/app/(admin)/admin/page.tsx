import type { Metadata } from 'next';
import { AdminDashboard, AdminLoadError, serverErrorText } from '@/components/admin';
import { adminMetrics } from '@/lib/api';
import { routes } from '@/lib/routes';
import { buildMetadata } from '@/lib/seo';
import { createClient } from '@/lib/supabase/server';
import type { AdminMetrics } from '@/lib/types';

export const metadata: Metadata = buildMetadata({
  title: 'Admin overview',
  description: 'Klect moderation console.',
  path: routes.admin,
  noindex: true,
});

/** Cookie-bound and staff-only: there is nothing here to cache or prerender. */
export const dynamic = 'force-dynamic';

export default async function AdminOverviewPage() {
  const supabase = await createClient();

  let metrics: AdminMetrics | null = null;
  let failure: string | null = null;

  try {
    metrics = await adminMetrics(supabase);
  } catch (error) {
    failure = serverErrorText(error);
  }

  if (!metrics) {
    return (
      <AdminLoadError
        title="Metrics unavailable"
        message={failure ?? 'admin_metrics() did not answer.'}
      />
    );
  }

  // Fixed here so the 14-day window is identical on both sides of hydration.
  const endDay = new Date().toISOString().slice(0, 10);

  return <AdminDashboard initialMetrics={metrics} endDay={endDay} />;
}
