import type { Metadata } from 'next';
import {
  AdminLoadError,
  UserConsole,
  getAdminUser,
  listAdminUsers,
  listRolesFor,
  serverErrorText,
  type AdminUserRow,
} from '@/components/admin';
import type { AppRole } from '@/lib/entities';
import { routes } from '@/lib/routes';
import { buildMetadata } from '@/lib/seo';
import { createClient } from '@/lib/supabase/server';
import { getViewerBootstrap } from '@/lib/viewer';

export const metadata: Metadata = buildMetadata({
  title: 'Users',
  description: 'Klect moderation console.',
  path: routes.adminUsers,
  noindex: true,
});

export const dynamic = 'force-dynamic';

interface PageProps {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}

export default async function AdminUsersPage({ searchParams }: PageProps) {
  const params = await searchParams;
  const selectedId = typeof params.u === 'string' && params.u ? params.u : null;

  const supabase = await createClient();
  const { roles: viewerRoles } = await getViewerBootstrap();

  let users: AdminUserRow[] = [];
  let roles: Record<string, AppRole[]> = {};
  let failure: string | null = null;

  try {
    users = await listAdminUsers(supabase, { limit: 40 });

    // A deep link from the report queue can point at somebody who is not on the
    // first page of "recently joined" — pull them in so the panel has a row.
    if (selectedId && !users.some((user) => user.id === selectedId)) {
      const pinned = await getAdminUser(supabase, selectedId);
      if (pinned) users = [pinned, ...users];
    }

    roles = await listRolesFor(
      supabase,
      users.map((user) => user.id),
    );
  } catch (error) {
    failure = serverErrorText(error);
  }

  if (failure) {
    return <AdminLoadError title="Accounts unavailable" message={failure} />;
  }

  return (
    <UserConsole
      initialUsers={users}
      initialRoles={roles}
      initialSelectedId={selectedId}
      viewerRoles={viewerRoles}
    />
  );
}
