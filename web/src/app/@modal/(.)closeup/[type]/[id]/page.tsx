import { notFound } from 'next/navigation';
import { CloseupModal } from '@/components/closeup/CloseupModal';
import { getCloseup } from '@/lib/api';
import { isEntityType } from '@/lib/entities';
import { createClient } from '@/lib/supabase/server';

interface PageProps {
  params: Promise<{ type: string; id: string }>;
}

/**
 * Intercepting route. Navigating to `/closeup/item/<id>` from inside the app
 * renders this over the current grid instead of replacing the page; the URL
 * still changes, so the closeup is shareable and Back closes it.
 */
export default async function InterceptedCloseup({ params }: PageProps) {
  const { type, id } = await params;
  if (!isEntityType(type)) notFound();

  const supabase = await createClient();
  const payload = await getCloseup(supabase, type, id);
  if (!payload) notFound();

  return <CloseupModal payload={payload} />;
}
