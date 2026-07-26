'use client';

import { cn } from '@/lib/cn';
import { Icon, type IconName } from '@/components/ui/Icon';
import { useTheme, type ThemePreference } from '@/providers/theme-provider';

const choices: Array<{
  value: ThemePreference;
  label: string;
  icon: IconName;
  blurb: string;
}> = [
  {
    value: 'system',
    label: 'Match my system',
    icon: 'monitor',
    blurb: 'Klect follows your OS setting and switches with it.',
  },
  {
    value: 'dark',
    label: 'Always dark',
    icon: 'moon',
    blurb: 'A private gallery at night. Near-black, never pure black.',
  },
  {
    value: 'light',
    label: 'Always light',
    icon: 'sun',
    blurb: 'Paper-white surfaces with the same oxblood accent.',
  },
];

export function AppearanceSettings() {
  const { preference, resolved, setPreference } = useTheme();

  return (
    <section className="flex flex-col gap-6">
      <header>
        <h2 className="font-display text-title1 text-ink">Appearance</h2>
        <p className="mt-1 text-callout text-ink-2">
          Dark is the default because photography reads better against it. Your choice is
          stored on this device and applied before the first paint, so there is never a
          flash of the wrong theme.
        </p>
      </header>

      <fieldset className="flex flex-col gap-2">
        <legend className="sr-only">Theme</legend>
        {choices.map((choice) => {
          const active = preference === choice.value;
          return (
            <label
              key={choice.value}
              className={cn(
                'flex cursor-pointer items-start gap-3 rounded-lg border p-4',
                'transition-colors dur-fast ease-standard',
                'focus-within:outline-2 focus-within:outline-offset-2 focus-within:outline-focus',
                active
                  ? 'border-accent bg-accent-subtle'
                  : 'border-line bg-surface-1 hover:bg-surface-2',
              )}
            >
              <input
                type="radio"
                name="theme"
                value={choice.value}
                checked={active}
                onChange={() => setPreference(choice.value)}
                className="sr-only"
              />
              <span
                className={cn(
                  'grid size-10 shrink-0 place-items-center rounded-full',
                  active ? 'bg-accent text-ink-on-accent' : 'bg-surface-3 text-ink-2',
                )}
              >
                <Icon name={choice.icon} size="md" />
              </span>
              <span className="min-w-0">
                <span className="block text-body-strong text-ink">{choice.label}</span>
                <span className="mt-0.5 block text-caption text-ink-2">{choice.blurb}</span>
              </span>
              {active ? (
                <span className="ml-auto text-accent">
                  <Icon name="check" size="md" />
                </span>
              ) : null}
            </label>
          );
        })}
      </fieldset>

      <p className="text-caption text-ink-3">
        Currently rendering in <strong className="text-ink-2">{resolved}</strong>. Reduced
        motion is honoured automatically — if your system asks for less movement, Klect
        replaces every transform with a short fade.
      </p>
    </section>
  );
}
