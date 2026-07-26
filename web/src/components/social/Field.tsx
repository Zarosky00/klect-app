'use client';

import { useId, type ReactNode, type SelectHTMLAttributes } from 'react';
import { cn } from '@/lib/cn';
import { Icon } from '@/components/ui/Icon';

/**
 * The select the primitive set does not ship. Same shell, same tokens and the
 * same focus ring as `TextField`, so a form built from both looks like one
 * thing.
 */
export interface SelectFieldProps
  extends Omit<SelectHTMLAttributes<HTMLSelectElement>, 'className' | 'children'> {
  label: string;
  hint?: string;
  error?: string | null;
  labelHidden?: boolean;
  className?: string;
  children: ReactNode;
}

export function SelectField({
  label,
  hint,
  error,
  labelHidden,
  className,
  children,
  id,
  required,
  ...rest
}: SelectFieldProps) {
  const generated = useId();
  const fieldId = id ?? generated;

  return (
    <div className={cn('flex flex-col gap-1.5', className)}>
      <label htmlFor={fieldId} className={cn('text-label text-ink-2', labelHidden && 'sr-only')}>
        {label}
        {required ? <span className="ml-1 text-danger">*</span> : null}
      </label>

      <div className="relative flex items-center">
        <select
          id={fieldId}
          required={required}
          aria-invalid={error ? true : undefined}
          aria-describedby={error ? `${fieldId}-error` : hint ? `${fieldId}-hint` : undefined}
          className={cn(
            'focus-ring h-11 w-full appearance-none rounded-md border bg-surface-2 pl-3 pr-10',
            'text-body text-ink transition-colors dur-fast ease-standard',
            error ? 'border-danger' : 'border-line focus:border-line-strong',
          )}
          {...rest}
        >
          {children}
        </select>
        <span className="pointer-events-none absolute right-3 text-ink-3">
          <Icon name="chevron-down" size="sm" />
        </span>
      </div>

      {error ? (
        <p id={`${fieldId}-error`} role="alert" className="flex items-center gap-1 text-caption text-danger">
          <Icon name="alert" size="xs" />
          {error}
        </p>
      ) : hint ? (
        <p id={`${fieldId}-hint`} className="text-caption text-ink-3">
          {hint}
        </p>
      ) : null}
    </div>
  );
}
