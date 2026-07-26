import type { Metadata } from 'next';
import { notFound, redirect } from 'next/navigation';
import { listMessages } from '@/lib/api';
import { conversationHref, routes } from '@/lib/routes';
import { buildMetadata } from '@/lib/seo';
import { createClient } from '@/lib/supabase/server';
import { getViewerBootstrap } from '@/lib/viewer';
import { MessageThread } from '@/components/social/MessageThread';
import { conversationTitle, getConversationSummary } from '@/components/social/queries';

interface PageProps {
  params: Promise<{ conversationId: string }>;
}

export async function generateMetadata({ params }: PageProps): Promise<Metadata> {
  const { conversationId } = await params;
  return buildMetadata({
    title: 'Conversation',
    description: 'A private conversation on Klect.',
    path: conversationHref(conversationId),
    noindex: true,
  });
}

/**
 * RLS is the only membership check that matters: a conversation you are not a
 * member of simply returns no row, so a guessed id 404s rather than leaking a
 * title. The last page of messages is server-rendered; realtime takes over.
 */
export default async function ConversationPage({ params }: PageProps) {
  const { conversationId } = await params;

  const { user } = await getViewerBootstrap();
  if (!user) redirect(`${routes.signIn}?next=${encodeURIComponent(conversationHref(conversationId))}`);

  const supabase = await createClient();
  const summary = await getConversationSummary(supabase, user.id, conversationId);
  if (!summary) notFound();

  const messages = await listMessages(supabase, conversationId, { limit: 60 });

  return (
    <>
      <h1 className="sr-only">{conversationTitle(summary)}</h1>
      <MessageThread summary={summary} viewerId={user.id} initialMessages={messages} />
    </>
  );
}
