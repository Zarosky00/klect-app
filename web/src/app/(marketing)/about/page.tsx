import type { Metadata } from 'next';
import { ButtonLink } from '@/components/ui/Button';
import { routes } from '@/lib/routes';
import { buildMetadata } from '@/lib/seo';

export const metadata: Metadata = buildMetadata({
  title: 'About',
  description:
    'Klect is built on one idea: the unit of content is a collection, not a post. Here is why that changes everything downstream.',
  path: routes.about,
});

export default function AboutPage() {
  return (
    <article className="readable-max px-4 py-16 sm:px-6 md:py-24">
      <h1 className="font-display text-display1 text-ink">About Klect</h1>

      <div className="mt-8 flex flex-col gap-6 text-body text-ink-2">
        <p>
          Every social network so far has treated the post as the atom. A post is
          disposable by design: it exists to be consumed once and buried. What people
          actually care about — the shelf, the run of prints, the four cameras they
          could not walk away from — has never had a shape that fits.
        </p>
        <p>
          Klect makes the collection the atom. A collection holds subcollections; a
          subcollection holds items; an item holds photographs. All three levels are
          first class: each one can be liked, saved, reposted, commented on, shared,
          reported and counted independently. That symmetry is not a feature list, it
          is the product.
        </p>

        <h2 className="mt-6 font-display text-title1 text-ink">Two ways to look</h2>
        <p>
          <strong className="text-ink">Surf</strong> is the visual side: a masonry grid
          of collections, subcollections and items, ranked for you and jittered so no
          two people see the same order.{' '}
          <strong className="text-ink">Pulse</strong> is the social side: a
          chronological stream of what the people you follow are adding, reposting and
          saying.
        </p>

        <h2 className="mt-6 font-display text-title1 text-ink">Built for the hand</h2>
        <p>
          One tap opens the closeup. Two opens the fullscreen viewer. A hold opens the
          quick actions. Nothing waits on a double-tap timer, and nothing is buried more
          than two gestures deep.
        </p>

        <h2 className="mt-6 font-display text-title1 text-ink">Honest counts</h2>
        <p>
          Likes, saves, reposts, comments and views are maintained by the database, not
          recomputed by the app. The interface applies your action instantly and then
          reconciles with the authoritative number — so it is always fast and always
          right.
        </p>
      </div>

      <div className="mt-10 flex flex-wrap gap-3">
        <ButtonLink href={routes.signUp}>Start collecting</ButtonLink>
        <ButtonLink href={routes.surf} variant="secondary">
          Surf first
        </ButtonLink>
      </div>
    </article>
  );
}
