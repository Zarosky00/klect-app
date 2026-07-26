import type { Metadata } from 'next';
import Link from 'next/link';
import { AuthCard } from '@/components/auth/AuthCard';
import { ForgotPasswordForm } from '@/components/auth/ForgotPasswordForm';
import { routes } from '@/lib/routes';
import { buildMetadata } from '@/lib/seo';

export const metadata: Metadata = buildMetadata({
  title: 'Reset your password',
  description: 'Send yourself a password reset link.',
  path: routes.forgotPassword,
  noindex: true,
});

export default function ForgotPasswordPage() {
  return (
    <AuthCard
      title="Reset your password"
      description="We will email you a link that signs you in and lets you set a new one."
      footer={
        <Link
          href={routes.signIn}
          className="focus-ring rounded-sm text-accent underline underline-offset-4"
        >
          Back to sign in
        </Link>
      }
    >
      <ForgotPasswordForm />
    </AuthCard>
  );
}
