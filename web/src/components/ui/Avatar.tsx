'use client';

import { useState } from 'react';
import Image from 'next/image';
import { cn } from '@/lib/cn';
import { initials } from '@/lib/format';
import { avatarUrl, isOptimizableImageSrc } from '@/lib/storage';
import { Icon } from './Icon';

export type AvatarSize = 'xs' | 'sm' | 'md' | 'lg' | 'xl' | '2xl';

const sizeClasses: Record<AvatarSize, string> = {
  xs: 'size-6 text-micro',
  sm: 'size-8 text-caption',
  md: 'size-10 text-label',
  lg: 'size-12 text-body-strong',
  xl: 'size-16 text-title2',
  '2xl': 'size-24 text-display3',
};

/** CSS pixel box per size — the `sizes` hint, so a 40px circle never
    downloads the original upload. Mirrors `sizeClasses` (token space ramp). */
const sizePx: Record<AvatarSize, number> = {
  xs: 24,
  sm: 32,
  md: 40,
  lg: 48,
  xl: 64,
  '2xl': 96,
};

const badgeSizeClasses: Record<AvatarSize, string> = {
  xs: 'size-3 -right-0.5 -bottom-0.5',
  sm: 'size-3.5 -right-0.5 -bottom-0.5',
  md: 'size-4 -right-0.5 -bottom-0.5',
  lg: 'size-5 -right-1 -bottom-0.5',
  xl: 'size-6 -right-1 bottom-0',
  '2xl': 'size-7 right-1 bottom-1',
};

export interface AvatarProps {
  /** `profiles.avatar_path` — bucket-relative or absolute. */
  path?: string | null;
  name?: string | null;
  username?: string | null;
  size?: AvatarSize;
  verified?: boolean;
  className?: string;
  /** Accent ring, for "this is you" or an active state. */
  ring?: boolean;
}

export function Avatar({
  path,
  name,
  username,
  size = 'md',
  verified = false,
  className,
  ring = false,
}: AvatarProps) {
  const [failed, setFailed] = useState(false);
  const src = avatarUrl(path);
  const label = name ?? username ?? 'Collector';

  return (
    <span className={cn('relative inline-flex shrink-0', className)}>
      <span
        className={cn(
          'relative inline-flex items-center justify-center overflow-hidden rounded-full',
          'bg-surface-3 text-ink-2 font-sans font-semibold uppercase',
          ring && 'ring-2 ring-accent ring-offset-2 ring-offset-base',
          sizeClasses[size],
        )}
      >
        {src && !failed ? (
          <Image
            src={src}
            alt=""
            fill
            sizes={`${sizePx[size]}px`}
            unoptimized={!isOptimizableImageSrc(src)}
            className="object-cover"
            onError={() => setFailed(true)}
          />
        ) : name || username ? (
          <span aria-hidden>{initials(label)}</span>
        ) : (
          <Icon name="user" aria-hidden />
        )}
      </span>

      {verified ? (
        <span
          className={cn('absolute text-accent', badgeSizeClasses[size])}
          title="Verified"
        >
          <Icon name="verified" size="inherit" title="Verified" />
        </span>
      ) : null}
    </span>
  );
}

export interface AvatarStackProps {
  people: Array<{ id: string; avatar_path?: string | null; display_name?: string | null }>;
  size?: AvatarSize;
  max?: number;
  className?: string;
}

export function AvatarStack({ people, size = 'sm', max = 4, className }: AvatarStackProps) {
  const shown = people.slice(0, max);
  const overflow = people.length - shown.length;
  return (
    <span className={cn('inline-flex items-center', className)}>
      {shown.map((person, index) => (
        <span
          key={person.id}
          className={cn('rounded-full ring-2 ring-base', index > 0 && '-ml-2')}
        >
          <Avatar path={person.avatar_path} name={person.display_name} size={size} />
        </span>
      ))}
      {overflow > 0 ? (
        <span className="-ml-2 inline-flex items-center rounded-full bg-surface-3 px-2 py-0.5 text-micro text-ink-2 ring-2 ring-base">
          +{overflow}
        </span>
      ) : null}
    </span>
  );
}
