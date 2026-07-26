import type { Metadata } from 'next';
import {
  CONTENT_FILTERS,
  ContentConsole,
  describeServerError,
  listAdminContent,
  type AdminContentRow,
  type AdminErrorInfo,
  type ContentVisibilityFilter,
} from '@/components/admin';
import { isSurfaceEntityType, type SurfaceEntityType } from '@/lib/entities';
import { routes } from '@/lib/routes';
import { buildMetadata } from '@/lib/seo';
import { createClient } from '@/lib/supabase/server';

export const metadata: Metadata = buildMetadata({
  title: 'Content',
  description: 'Klect moderation console.',
  path: routes.adminContent,
  noindex: true,
});

export const dynamic = 'force-dynamic';

function toType(value: string | string[] | undefined): SurfaceEntityType {
  return isSurfaceEntityType(value) ? value : 'item';
}

function toFilter(value: string | string[] | undefined): ContentVisibilityFilter {
  return typeof value === 'string' && (CONTENT_FILTERS as readonly string[]).includes(value)
    ? (value as ContentVisibilityFilter)
    : 'all';
}

interface PageProps {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}

export default async function AdminContentPage({ searchParams }: PageProps) {
  const params = await searchParams;
  const type = toType(params.type);
  const filter = toFilter(params.filter);

  const supabase = await createClient();

  let rows: AdminContentRow[] = [];
  let failure: AdminErrorInfo | null = null;

  try {
    rows = await listAdminContent(supabase, { type, filter, limit: 30, offset: 0 });
  } catch (error) {
    failure = describeServerError(error);
  }

  return (
    <ContentConsole
      initialType={type}
      initialFilter={filter}
      initialRows={rows}
      initialError={failure}
    />
  );
}
