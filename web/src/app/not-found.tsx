import { ButtonLink } from '@/components/ui/Button';
import { EmptyState } from '@/components/ui/EmptyState';
import { routes } from '@/lib/routes';

export default function NotFound() {
  return (
    <main id="main" className="flex min-h-dvh items-center justify-center">
      <EmptyState
        icon="search"
        title="Nothing here"
        description="This page is private, deleted, or never existed. The rest of Klect is still where you left it."
        action={
          <div className="flex flex-wrap justify-center gap-3">
            <ButtonLink href={routes.surf}>Go surfing</ButtonLink>
            <ButtonLink href={routes.home} variant="secondary">
              Home
            </ButtonLink>
          </div>
        }
      />
    </main>
  );
}
