import { redirect } from 'next/navigation';
import type { ReactNode } from 'react';
import { routes } from '@/lib/routes';
import { createClient } from '@/lib/supabase/server';
import { getViewerBootstrap } from '@/lib/viewer';
import { MessagesShell } from '@/components/social/MessagesShell';
import { listConversationSummaries } from '@/components/social/queries';

/**
 * The conversation index is a layout, not a page, so switching threads never
 * re-fetches or re-mounts the list — and the two-pane desktop layout falls out
 * of that for free.
 */
export default async function MessagesLayout({ children }: { children: ReactNode }) {
  const { user } = await getViewerBootstrap();
  if (!user) redirect(`${routes.signIn}?next=${encodeURIComponent(routes.messages)}`);

  const supabase = await createClient();
  const conversations = await listConversationSummaries(supabase, user.id);

  return (
    <MessagesShell initialConversations={conversations} viewerId={user.id}>
      {children}
    </MessagesShell>
  );
}
