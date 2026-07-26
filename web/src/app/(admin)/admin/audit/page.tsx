import type { Metadata } from 'next';
import {
  AuditConsole,
  describeServerError,
  listAuditEntries,
  listStaffProfiles,
  type AdminErrorInfo,
  type AdminPersonRef,
  type AuditEntry,
} from '@/components/admin';
import { routes } from '@/lib/routes';
import { buildMetadata } from '@/lib/seo';
import { createClient } from '@/lib/supabase/server';

export const metadata: Metadata = buildMetadata({
  title: 'Audit log',
  description: 'Klect moderation console.',
  path: routes.adminAudit,
  noindex: true,
});

export const dynamic = 'force-dynamic';

export default async function AdminAuditPage() {
  const supabase = await createClient();

  let entries: AuditEntry[] = [];
  let actors: AdminPersonRef[] = [];
  let failure: AdminErrorInfo | null = null;

  // The two reads have different gates: `audit_read` is `is_admin()`, while
  // `user_roles` is readable by any staff. A moderator therefore still gets the
  // actor list, and the console explains why the log itself is empty.
  try {
    entries = await listAuditEntries(supabase, { limit: 50, offset: 0 });
  } catch (error) {
    failure = describeServerError(error);
  }

  try {
    actors = await listStaffProfiles(supabase);
  } catch {
    actors = [];
  }

  return <AuditConsole initialEntries={entries} actors={actors} initialError={failure} />;
}
