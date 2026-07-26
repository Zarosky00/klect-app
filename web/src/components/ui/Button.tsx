'use client';

import Link from 'next/link';
import { forwardRef } from 'react';
import type { AnchorHTMLAttributes, ButtonHTMLAttributes, CSSProperties, ReactNode } from 'react';
import { pressScale } from '@/design/motion';
import { cn } from '@/lib/cn';
import { Icon, type IconName } from './Icon';

export type ButtonVariant = 'primary' | 'secondary' | 'ghost' | 'danger' | 'quiet';
export type ButtonSize = 'sm' | 'md' | 'lg';

const variantClasses: Record<ButtonVariant, string> = {
  primary:
    'bg-accent text-ink-on-accent hover:bg-accent-hover active:bg-accent-press shadow-low',
  secondary:
    'bg-surface-2 text-ink border border-line hover:bg-surface-3 active:bg-surface-4',
  ghost: 'text-ink-2 hover:bg-surface-2 hover:text-ink',
  danger: 'bg-danger-subtle text-danger border border-danger/40 hover:bg-danger/20',
  quiet: 'text-ink-2 hover:text-ink underline underline-offset-4 decoration-line-strong',
};

const sizeClasses: Record<ButtonSize, string> = {
  sm: 'h-8 px-3 gap-1.5 text-label rounded-sm',
  md: 'h-11 px-5 gap-2 text-body-strong rounded-md',
  lg: 'h-12 px-6 gap-2 text-title3 rounded-md',
};

interface CommonProps {
  variant?: ButtonVariant;
  size?: ButtonSize;
  /** Stretches to the container width. */
  block?: boolean;
  loading?: boolean;
  iconLeft?: IconName;
  iconRight?: IconName;
  children?: ReactNode;
  className?: string;
}

function useButtonClasses({
  variant = 'primary',
  size = 'md',
  block,
  className,
}: CommonProps): string {
  return cn(
    'k-pressable focus-ring inline-flex items-center justify-center whitespace-nowrap',
    'font-sans transition-colors dur-fast ease-standard',
    'disabled:pointer-events-none disabled:opacity-[var(--k-opacity-disabled)]',
    'aria-disabled:pointer-events-none aria-disabled:opacity-[var(--k-opacity-disabled)]',
    variantClasses[variant],
    sizeClasses[size],
    block && 'w-full',
    className,
  );
}

const pressStyle = { '--k-press-scale': String(pressScale) } as CSSProperties;

export interface ButtonProps
  extends CommonProps,
    Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'children' | 'className'> {}

export const Button = forwardRef<HTMLButtonElement, ButtonProps>(function Button(
  {
    variant,
    size,
    block,
    loading = false,
    iconLeft,
    iconRight,
    children,
    className,
    disabled,
    type = 'button',
    style,
    ...rest
  },
  ref,
) {
  const classes = useButtonClasses({ variant, size, block, className });
  return (
    <button
      ref={ref}
      type={type}
      className={classes}
      style={{ ...pressStyle, ...style }}
      disabled={disabled || loading}
      aria-busy={loading || undefined}
      {...rest}
    >
      {loading ? (
        <Icon name="spinner" aria-hidden />
      ) : iconLeft ? (
        <Icon name={iconLeft} aria-hidden />
      ) : null}
      {children}
      {iconRight && !loading ? <Icon name={iconRight} aria-hidden /> : null}
    </button>
  );
});

export interface ButtonLinkProps
  extends CommonProps,
    Omit<AnchorHTMLAttributes<HTMLAnchorElement>, 'children' | 'className' | 'href'> {
  href: string;
}

export const ButtonLink = forwardRef<HTMLAnchorElement, ButtonLinkProps>(function ButtonLink(
  { variant, size, block, iconLeft, iconRight, children, className, href, style, ...rest },
  ref,
) {
  const classes = useButtonClasses({ variant, size, block, className });
  return (
    <Link ref={ref} href={href} className={classes} style={{ ...pressStyle, ...style }} {...rest}>
      {iconLeft ? <Icon name={iconLeft} aria-hidden /> : null}
      {children}
      {iconRight ? <Icon name={iconRight} aria-hidden /> : null}
    </Link>
  );
});

export interface IconButtonProps
  extends Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'children' | 'className'> {
  icon: IconName;
  /** Required — an icon-only control must announce itself. */
  label: string;
  variant?: ButtonVariant;
  size?: ButtonSize;
  filled?: boolean;
  className?: string;
}

const iconSizeClasses: Record<ButtonSize, string> = {
  sm: 'size-9 rounded-sm',
  md: 'tap-min rounded-md',
  lg: 'size-12 rounded-md',
};

export const IconButton = forwardRef<HTMLButtonElement, IconButtonProps>(function IconButton(
  { icon, label, variant = 'ghost', size = 'md', filled, className, style, type = 'button', ...rest },
  ref,
) {
  return (
    <button
      ref={ref}
      type={type}
      aria-label={label}
      title={label}
      className={cn(
        'k-pressable focus-ring inline-flex items-center justify-center',
        'transition-colors dur-fast ease-standard',
        'disabled:pointer-events-none disabled:opacity-[var(--k-opacity-disabled)]',
        variantClasses[variant],
        iconSizeClasses[size],
        className,
      )}
      style={{ ...pressStyle, ...style }}
      {...rest}
    >
      <Icon name={icon} filled={filled} size="lg" />
    </button>
  );
});
