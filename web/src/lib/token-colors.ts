import 'server-only';

import { readFileSync } from 'node:fs';
import { join } from 'node:path';

/**
 * Reads colour values straight out of the generated `tokens.g.css`.
 *
 * Rasterised output — the OG card, the favicon — cannot reference a CSS custom
 * property, so it has to resolve the value somewhere. Doing it here keeps the
 * single source of truth intact: no hex is ever typed into application code,
 * and regenerating the tokens changes these images too.
 */
let cached: Record<string, string> | null = null;

function parse(): Record<string, string> {
  const file = join(process.cwd(), 'src', 'styles', 'tokens.g.css');
  const css = readFileSync(file, 'utf8');

  // The first `:root { … }` block is the dark (default) theme.
  const start = css.indexOf(':root {');
  const end = css.indexOf('}', start);
  const block = start >= 0 ? css.slice(start, end) : '';

  const map: Record<string, string> = {};
  for (const match of block.matchAll(/--(k-[a-zA-Z0-9-]+)\s*:\s*([^;]+);/g)) {
    const key = match[1];
    const value = match[2];
    if (key && value) map[key] = value.trim();
  }
  return map;
}

export function tokenColor(name: string, fallback = 'transparent'): string {
  if (!cached) {
    try {
      cached = parse();
    } catch {
      cached = {};
    }
  }
  return cached[name] ?? fallback;
}
