'use client';

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react';

/**
 * Dark is the default. Light comes from `[data-theme="light"]`. "System" removes
 * the attribute entirely and lets the `prefers-color-scheme` block in
 * `tokens.g.css` decide — no JS in the critical path once the choice is made.
 */
export type ThemePreference = 'system' | 'dark' | 'light';
export type ResolvedTheme = 'dark' | 'light';

export const THEME_STORAGE_KEY = 'klect-theme';

interface ThemeContextValue {
  preference: ThemePreference;
  resolved: ResolvedTheme;
  setPreference: (preference: ThemePreference) => void;
  toggle: () => void;
}

const ThemeContext = createContext<ThemeContextValue | null>(null);

/**
 * Runs before first paint, so a light-theme user never sees a dark flash.
 * Kept as a string because it must be inlined into <head> synchronously.
 *
 * It also writes `<meta name="theme-color">` from the live value of
 * `--k-bg-base`, which is how the browser chrome stays token-accurate without
 * a hex ever being typed into application code.
 */
export const THEME_INIT_SCRIPT = `(function(){var k=${JSON.stringify(THEME_STORAGE_KEY)};
try{var v=localStorage.getItem(k);var r=document.documentElement;
if(v==='light'||v==='dark'){r.setAttribute('data-theme',v);}else{r.removeAttribute('data-theme');}}catch(e){}
function s(){try{var c=getComputedStyle(document.documentElement).getPropertyValue('--k-bg-base').trim();
if(!c)return;var m=document.querySelector('meta[name="theme-color"]');
if(!m){m=document.createElement('meta');m.setAttribute('name','theme-color');document.head.appendChild(m);}
m.setAttribute('content',c);}catch(e){}}
window.__klectSyncThemeColor=s;
if(document.readyState==='loading'){document.addEventListener('DOMContentLoaded',s);}else{s();}})();`;

/** Re-reads `--k-bg-base` and updates the browser chrome colour. */
export function syncThemeColor(): void {
  const globalWithSync = window as typeof window & { __klectSyncThemeColor?: () => void };
  globalWithSync.__klectSyncThemeColor?.();
}

function readStoredPreference(): ThemePreference {
  if (typeof window === 'undefined') return 'system';
  try {
    const stored = window.localStorage.getItem(THEME_STORAGE_KEY);
    if (stored === 'dark' || stored === 'light' || stored === 'system') return stored;
  } catch {
    // Private mode / storage disabled — fall through to system.
  }
  return 'system';
}

function systemTheme(): ResolvedTheme {
  if (typeof window === 'undefined' || !window.matchMedia) return 'dark';
  return window.matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark';
}

function applyPreference(preference: ThemePreference): void {
  const root = document.documentElement;
  if (preference === 'system') root.removeAttribute('data-theme');
  else root.setAttribute('data-theme', preference);
}

export function ThemeProvider({ children }: { children: ReactNode }) {
  // Server render and first client render must agree; the inline script has
  // already put the right attribute on <html>, so hydrating as 'system' and
  // correcting in an effect never causes a visible flash.
  const [preference, setPreferenceState] = useState<ThemePreference>('system');
  const [systemResolved, setSystemResolved] = useState<ResolvedTheme>('dark');

  useEffect(() => {
    setPreferenceState(readStoredPreference());
    setSystemResolved(systemTheme());
  }, []);

  useEffect(() => {
    if (typeof window === 'undefined' || !window.matchMedia) return;
    const query = window.matchMedia('(prefers-color-scheme: light)');
    const listener = (event: MediaQueryListEvent) => {
      setSystemResolved(event.matches ? 'light' : 'dark');
    };
    query.addEventListener('change', listener);
    return () => query.removeEventListener('change', listener);
  }, []);

  const setPreference = useCallback((next: ThemePreference) => {
    setPreferenceState(next);
    applyPreference(next);
    syncThemeColor();
    try {
      window.localStorage.setItem(THEME_STORAGE_KEY, next);
    } catch {
      // Nothing to do — the in-memory preference still applies for this session.
    }
  }, []);

  const resolved: ResolvedTheme = preference === 'system' ? systemResolved : preference;

  const toggle = useCallback(() => {
    setPreference(resolved === 'dark' ? 'light' : 'dark');
  }, [resolved, setPreference]);

  const value = useMemo<ThemeContextValue>(
    () => ({ preference, resolved, setPreference, toggle }),
    [preference, resolved, setPreference, toggle],
  );

  return <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>;
}

export function useTheme(): ThemeContextValue {
  const context = useContext(ThemeContext);
  if (!context) throw new Error('useTheme must be used inside <ThemeProvider/>.');
  return context;
}
