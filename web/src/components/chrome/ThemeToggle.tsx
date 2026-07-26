'use client';

import { cn } from '@/lib/cn';
import { Icon, type IconName } from '@/components/ui/Icon';
import { useTheme, type ThemePreference } from '@/providers/theme-provider';

const options: Array<{ value: ThemePreference; label: string; icon: IconName }> = [
  { value: 'system', label: 'System', icon: 'monitor' },
  { value: 'dark', label: 'Dark', icon: 'moon' },
  { value: 'light', label: 'Light', icon: 'sun' },
];

/** Three-way segmented control: follow the OS, or override it. */
export function ThemeToggle({ className }: { className?: string }) {
  const { preference, setPreference } = useTheme();

  return (
    <div
      role="radiogroup"
      aria-label="Theme"
      className={cn(
        'inline-flex items-center gap-0.5 rounded-full border border-line bg-surface-2 p-0.5',
        className,
      )}
    >
      {options.map((option) => {
        const active = preference === option.value;
        return (
          <button
            key={option.value}
            type="button"
            role="radio"
            aria-checked={active}
            aria-label={option.label}
            title={option.label}
            onClick={() => setPreference(option.value)}
            className={cn(
              'focus-ring inline-flex size-8 items-center justify-center rounded-full',
              'transition-colors dur-fast ease-standard',
              active ? 'bg-accent text-ink-on-accent' : 'text-ink-2 hover:text-ink',
            )}
          >
            <Icon name={option.icon} size="sm" />
          </button>
        );
      })}
    </div>
  );
}
