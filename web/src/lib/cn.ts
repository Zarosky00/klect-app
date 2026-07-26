import clsx, { type ClassValue } from 'clsx';

/** Class name composition. Kept as its own module so it is trivial to swap. */
export function cn(...inputs: ClassValue[]): string {
  return clsx(inputs);
}

export type { ClassValue };
