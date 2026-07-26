'use client';

import { forwardRef, useId } from 'react';
import type { InputHTMLAttributes, ReactNode, TextareaHTMLAttributes } from 'react';
import { cn } from '@/lib/cn';
import { Icon, type IconName } from './Icon';

const fieldBase = cn(
  'w-full rounded-md border bg-surface-2 px-3 text-body text-ink',
  'transition-colors dur-fast ease-standard',
  'placeholder:text-ink-3',
  'disabled:cursor-not-allowed disabled:opacity-[var(--k-opacity-disabled)]',
);

function Shell({
  id,
  label,
  hint,
  error,
  required,
  children,
  className,
  labelHidden,
}: {
  id: string;
  label: string;
  hint?: string;
  error?: string | null;
  required?: boolean;
  children: ReactNode;
  className?: string;
  labelHidden?: boolean;
}) {
  return (
    <div className={cn('flex flex-col gap-1.5', className)}>
      <label
        htmlFor={id}
        className={cn('text-label text-ink-2', labelHidden && 'sr-only')}
      >
        {label}
        {required ? <span className="ml-1 text-danger">*</span> : null}
      </label>
      {children}
      {error ? (
        <p id={`${id}-error`} role="alert" className="flex items-center gap-1 text-caption text-danger">
          <Icon name="alert" size="xs" />
          {error}
        </p>
      ) : hint ? (
        <p id={`${id}-hint`} className="text-caption text-ink-3">
          {hint}
        </p>
      ) : null}
    </div>
  );
}

export interface TextFieldProps
  extends Omit<InputHTMLAttributes<HTMLInputElement>, 'className'> {
  label: string;
  hint?: string;
  error?: string | null;
  iconLeft?: IconName;
  trailing?: ReactNode;
  className?: string;
  fieldClassName?: string;
  labelHidden?: boolean;
}

export const TextField = forwardRef<HTMLInputElement, TextFieldProps>(function TextField(
  {
    label,
    hint,
    error,
    iconLeft,
    trailing,
    className,
    fieldClassName,
    labelHidden,
    id,
    required,
    ...rest
  },
  ref,
) {
  const generatedId = useId();
  const fieldId = id ?? generatedId;

  return (
    <Shell
      id={fieldId}
      label={label}
      {...(hint === undefined ? {} : { hint })}
      {...(error === undefined ? {} : { error })}
      {...(required === undefined ? {} : { required })}
      {...(className === undefined ? {} : { className })}
      {...(labelHidden === undefined ? {} : { labelHidden })}
    >
      <div className="relative flex items-center">
        {iconLeft ? (
          <span className="pointer-events-none absolute left-3 text-ink-3">
            <Icon name={iconLeft} size="md" />
          </span>
        ) : null}

        <input
          ref={ref}
          id={fieldId}
          required={required}
          aria-invalid={error ? true : undefined}
          aria-describedby={error ? `${fieldId}-error` : hint ? `${fieldId}-hint` : undefined}
          className={cn(
            fieldBase,
            'focus-ring h-11',
            iconLeft && 'pl-10',
            trailing && 'pr-11',
            error ? 'border-danger' : 'border-line focus:border-line-strong',
            fieldClassName,
          )}
          {...rest}
        />

        {trailing ? <span className="absolute right-2 flex items-center">{trailing}</span> : null}
      </div>
    </Shell>
  );
});

export interface TextAreaProps
  extends Omit<TextareaHTMLAttributes<HTMLTextAreaElement>, 'className'> {
  label: string;
  hint?: string;
  error?: string | null;
  className?: string;
  fieldClassName?: string;
  labelHidden?: boolean;
  /** Renders a live "123 / 280" counter. */
  maxLength?: number;
  showCount?: boolean;
}

export const TextArea = forwardRef<HTMLTextAreaElement, TextAreaProps>(function TextArea(
  {
    label,
    hint,
    error,
    className,
    fieldClassName,
    labelHidden,
    id,
    required,
    maxLength,
    showCount = false,
    value,
    rows = 4,
    ...rest
  },
  ref,
) {
  const generatedId = useId();
  const fieldId = id ?? generatedId;
  const length = typeof value === 'string' ? value.length : 0;

  return (
    <Shell
      id={fieldId}
      label={label}
      {...(hint === undefined ? {} : { hint })}
      {...(error === undefined ? {} : { error })}
      {...(required === undefined ? {} : { required })}
      {...(className === undefined ? {} : { className })}
      {...(labelHidden === undefined ? {} : { labelHidden })}
    >
      <div className="relative">
        <textarea
          ref={ref}
          id={fieldId}
          rows={rows}
          required={required}
          maxLength={maxLength}
          value={value}
          aria-invalid={error ? true : undefined}
          aria-describedby={error ? `${fieldId}-error` : hint ? `${fieldId}-hint` : undefined}
          className={cn(
            fieldBase,
            'focus-ring resize-y py-2.5',
            error ? 'border-danger' : 'border-line focus:border-line-strong',
            fieldClassName,
          )}
          {...rest}
        />
        {showCount && maxLength ? (
          <span className="pointer-events-none absolute bottom-2 right-3 tabular text-micro text-ink-3">
            {length} / {maxLength}
          </span>
        ) : null}
      </div>
    </Shell>
  );
});
