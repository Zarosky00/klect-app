import type { Metadata } from 'next';
import { AuthCard } from '@/components/auth/AuthCard';
import { SignOutButton } from '@/components/auth/SignOutButton';
import { getViewerBootstrap } from '@/lib/viewer';
import { fullDateTime } from '@/lib/format';
import { createClient } from '@/lib/supabase/server';
import { routes } from '@/lib/routes';
import { buildMetadata } from '@/lib/seo';

export const metadata: Metadata = buildMetadata({
  title: 'Account suspended',
  description: 'This account is currently suspended.',
  path: routes.suspended,
  noindex: true,
});

export default async function SuspendedPage() {
  const { user } = await getViewerBootstrap();
  let until: string | null = null;
  let reason: string | null = null;

  if (user) {
    const supabase = await createClient();
    const { data } = await supabase
      .from('profiles')
      .select('suspended_until, suspension_reason')
      .eq('id', user.id)
      .maybeSingle();
    until = data?.suspended_until ?? null;
    reason = data?.suspension_reason ?? null;
  }

  return (
    <AuthCard
      title="Your account is suspended"
      description="You can still read what is public, but writes are switched off."
      footer={<SignOutButton />}
    >
      <div className="flex flex-col gap-3 text-callout text-ink-2">
        {reason ? (
          <p>
            <span className="text-ink">Reason:</span> {reason}
          </p>
        ) : null}
        <p>
          {until
            ? `The suspension lifts on ${fullDateTime(until)}.`
            : 'This suspension does not have an end date. Contact support if you think it is a mistake.'}
        </p>
      </div>
    </AuthCard>
  );
}
