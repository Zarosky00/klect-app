import type { Metadata } from 'next';
import Link from 'next/link';
import { AuthCard } from '@/components/auth/AuthCard';
import { SignUpForm } from '@/components/auth/SignUpForm';
import { routes } from '@/lib/routes';
import { buildMetadata } from '@/lib/seo';

export const metadata: Metadata = buildMetadata({
  title: 'Create your account',
  description: 'Start a collection on Klect. Three levels, infinite shelves.',
  path: routes.signUp,
  noindex: true,
});

export default function SignUpPage() {
  return (
    <AuthCard
      title="Start collecting"
      description="A handle, an email, and you are in."
      footer={
        <>
          Already have an account?{' '}
          <Link
            href={routes.signIn}
            className="focus-ring rounded-sm text-accent underline underline-offset-4"
          >
            Sign in
          </Link>
        </>
      }
    >
      <SignUpForm />
    </AuthCard>
  );
}
