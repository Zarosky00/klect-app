import Link from 'next/link';
import { cn } from '@/lib/cn';

/**
 * The wordmark. Fraunces, one oxblood dot — the only place the accent
 * appears without the user having asked for something.
 */
export function Wordmark({
  href = '/',
  className,
  size = 'md',
}: {
  href?: string;
  className?: string;
  size?: 'sm' | 'md' | 'lg';
}) {
  const sizeClass =
    size === 'lg' ? 'text-display2' : size === 'sm' ? 'text-title3' : 'text-title1';

  return (
    <Link
      href={href}
      aria-label="Klect — home"
      className={cn(
        'focus-ring inline-flex items-baseline gap-0.5 rounded-sm font-display tracking-tight text-ink',
        sizeClass,
        className,
      )}
    >
      Klect
      <span aria-hidden className="text-accent">
        .
      </span>
    </Link>
  );
}
