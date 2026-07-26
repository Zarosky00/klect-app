import type { Metadata } from 'next';
import { AuthCard } from '@/components/auth/AuthCard';
import { ResetPasswordForm } from '@/components/auth/ResetPasswordForm';
import { routes } from '@/lib/routes';
import { buildMetadata } from '@/lib/seo';

export const metadata: Metadata = buildMetadata({
  title: 'Choose a new password',
  description: 'Set a new password for your Klect account.',
  path: routes.resetPassword,
  noindex: true,
});

export default function ResetPasswordPage() {
  return (
    <AuthCard
      title="Choose a new password"
      description="You are signed in from the emailed link. Pick something you have not used elsewhere."
    >
      <ResetPasswordForm />
    </AuthCard>
  );
}
