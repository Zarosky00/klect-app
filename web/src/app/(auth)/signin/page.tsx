import type { Metadata } from 'next';
import Link from 'next/link';
import { Suspense } from 'react';
import { AuthCard } from '@/components/auth/AuthCard';
import { SignInForm } from '@/components/auth/SignInForm';
import { Skeleton } from '@/components/ui/Skeleton';
import { routes } from '@/lib/routes';
import { buildMetadata } from '@/lib/seo';

export const metadata: Metadata = buildMetadata({
  title: 'Sign in',
  description: 'Sign in to Klect to build, surf and save collections.',
  path: routes.signIn,
  noindex: true,
});

export default function SignInPage() {
  return (
    <AuthCard
      title="Welcome back"
      description="Your shelves are where you left them."
      footer={
        <>
          New here?{' '}
          <Link
            href={routes.signUp}
            className="focus-ring rounded-sm text-accent underline underline-offset-4"
          >
            Create an account
          </Link>
        </>
      }
    >
      <Suspense fallback={<Skeleton className="h-64 w-full" />}>
        <SignInForm />
      </Suspense>
    </AuthCard>
  );
}
