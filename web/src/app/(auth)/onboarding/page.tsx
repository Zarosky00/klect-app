import type { Metadata } from 'next';
import { OnboardingFlow } from '@/components/auth/OnboardingFlow';
import { routes } from '@/lib/routes';
import { buildMetadata } from '@/lib/seo';

export const metadata: Metadata = buildMetadata({
  title: 'Set up your account',
  description: 'Three quick steps and your first shelf is ready.',
  path: routes.onboarding,
  noindex: true,
});

export default function OnboardingPage() {
  return <OnboardingFlow />;
}
