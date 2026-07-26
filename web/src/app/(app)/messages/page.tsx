import type { Metadata } from 'next';
import { routes } from '@/lib/routes';
import { buildMetadata } from '@/lib/seo';
import { ButtonLink } from '@/components/ui/Button';
import { EmptyState } from '@/components/ui/EmptyState';

export const metadata: Metadata = buildMetadata({
  title: 'Messages',
  description: 'Direct messages with other collectors.',
  path: routes.messages,
  noindex: true,
});

/**
 * The right-hand pane before a thread is chosen. On mobile the shell hides this
 * pane entirely and shows the conversation list instead, so this is desktop
 * copy — never a dead end.
 */
export default function MessagesIndexPage() {
  return (
    <div className="grid min-h-0 flex-1 place-items-center">
      <EmptyState
        icon="mail"
        title="Pick a conversation"
        description="One DM per pair, ever. Open a collector's profile and press Message to start a new one."
        action={
          <ButtonLink href={routes.matches} variant="secondary" iconLeft="users">
            Find collectors like you
          </ButtonLink>
        }
      />
    </div>
  );
}
