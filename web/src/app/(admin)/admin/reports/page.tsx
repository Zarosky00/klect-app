import type { Metadata } from 'next';
import {
  EMPTY_REPORT_COUNTS,
  REPORT_STATUSES,
  ReportQueue,
  countReportsByStatus,
  describeServerError,
  type AdminErrorInfo,
  type ReportCounts,
} from '@/components/admin';
import { adminListReports } from '@/lib/api';
import type { ReportStatus } from '@/lib/entities';
import { routes } from '@/lib/routes';
import { buildMetadata } from '@/lib/seo';
import { createClient } from '@/lib/supabase/server';
import type { AdminReport } from '@/lib/types';

export const metadata: Metadata = buildMetadata({
  title: 'Report queue',
  description: 'Klect moderation console.',
  path: routes.adminReports,
  noindex: true,
});

export const dynamic = 'force-dynamic';

function toStatus(value: string | string[] | undefined): ReportStatus {
  return typeof value === 'string' && (REPORT_STATUSES as readonly string[]).includes(value)
    ? (value as ReportStatus)
    : 'open';
}

interface PageProps {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}

export default async function AdminReportsPage({ searchParams }: PageProps) {
  const status = toStatus((await searchParams).status);
  const supabase = await createClient();

  let reports: AdminReport[] = [];
  let counts: ReportCounts = EMPTY_REPORT_COUNTS;
  let failure: AdminErrorInfo | null = null;

  try {
    [reports, counts] = await Promise.all([
      adminListReports(supabase, { status, limit: 25, offset: 0 }),
      countReportsByStatus(supabase),
    ]);
  } catch (error) {
    failure = describeServerError(error);
  }

  return (
    <ReportQueue
      initialStatus={status}
      initialReports={reports}
      initialCounts={counts}
      initialError={failure}
    />
  );
}
