import { format, formatDistanceToNowStrict, isThisYear, isValid, parseISO } from 'date-fns';

/**
 * Compact counts: 1 · 999 · 1.2K · 34K · 1.2M · 3B.
 * Never rounds up past a threshold (`999` never renders as `1.0K`).
 */
export function compactCount(value: number | null | undefined): string {
  const n = typeof value === 'number' && Number.isFinite(value) ? Math.max(0, value) : 0;
  if (n < 1_000) return String(n);
  const units: Array<{ limit: number; suffix: string }> = [
    { limit: 1_000_000_000, suffix: 'B' },
    { limit: 1_000_000, suffix: 'M' },
    { limit: 1_000, suffix: 'K' },
  ];
  for (const { limit, suffix } of units) {
    if (n >= limit) {
      const scaled = n / limit;
      const rendered = scaled >= 100 ? Math.floor(scaled) : Math.floor(scaled * 10) / 10;
      return `${rendered}${suffix}`;
    }
  }
  return String(n);
}

export function plural(count: number, singular: string, pluralForm?: string): string {
  return count === 1 ? singular : (pluralForm ?? `${singular}s`);
}

function toDate(value: string | Date | null | undefined): Date | null {
  if (!value) return null;
  const date = value instanceof Date ? value : parseISO(value);
  return isValid(date) ? date : null;
}

/** "3m", "5h", "2d", "8mo", "3y" — the X-style short stamp. */
export function shortTimeAgo(value: string | Date | null | undefined): string {
  const date = toDate(value);
  if (!date) return '';
  const distance = formatDistanceToNowStrict(date, { addSuffix: false });
  const [rawAmount, unit] = distance.split(' ');
  const amount = rawAmount ?? '';
  const map: Record<string, string> = {
    second: 's',
    seconds: 's',
    minute: 'm',
    minutes: 'm',
    hour: 'h',
    hours: 'h',
    day: 'd',
    days: 'd',
    month: 'mo',
    months: 'mo',
    year: 'y',
    years: 'y',
  };
  const suffix = unit ? (map[unit] ?? '') : '';
  return `${amount}${suffix}`;
}

/** "3 minutes ago" — for screen readers and detail views. */
export function longTimeAgo(value: string | Date | null | undefined): string {
  const date = toDate(value);
  if (!date) return '';
  return formatDistanceToNowStrict(date, { addSuffix: true });
}

/** "12 Mar" this year, "12 Mar 2024" otherwise. */
export function calendarDate(value: string | Date | null | undefined): string {
  const date = toDate(value);
  if (!date) return '';
  return isThisYear(date) ? format(date, 'd MMM') : format(date, 'd MMM yyyy');
}

export function fullDateTime(value: string | Date | null | undefined): string {
  const date = toDate(value);
  if (!date) return '';
  return format(date, "d MMM yyyy 'at' HH:mm");
}

/** Clock time for chat bubbles. */
export function clockTime(value: string | Date | null | undefined): string {
  const date = toDate(value);
  if (!date) return '';
  return format(date, 'HH:mm');
}

export function initials(name: string | null | undefined, fallback = '?'): string {
  const source = (name ?? '').trim();
  if (!source) return fallback;
  const words = source.split(/\s+/).filter(Boolean).slice(0, 2);
  const letters = words.map((word) => [...word][0] ?? '').join('');
  return (letters || source[0] || fallback).toUpperCase();
}

export function handle(username: string | null | undefined): string {
  return username ? `@${username}` : '';
}

export function truncate(value: string, max: number): string {
  if (value.length <= max) return value;
  return `${value.slice(0, Math.max(0, max - 1)).trimEnd()}…`;
}

const USERNAME_PATTERN = /^[a-z0-9_]{3,24}$/;

export function normaliseUsername(value: string): string {
  return value.trim().toLowerCase().replace(/[^a-z0-9_]/g, '');
}

export function isValidUsername(value: string): boolean {
  return USERNAME_PATTERN.test(value);
}

export function isValidEmail(value: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(value.trim());
}

/** The floor the auth UI enforces before it ever hits the network. */
export const MIN_PASSWORD_LENGTH = 8;

export function passwordProblem(value: string): string | null {
  if (value.length < MIN_PASSWORD_LENGTH) {
    return `Use at least ${MIN_PASSWORD_LENGTH} characters.`;
  }
  if (!/[a-zA-Z]/.test(value) || !/[0-9]/.test(value)) {
    return 'Mix in at least one letter and one number.';
  }
  return null;
}
