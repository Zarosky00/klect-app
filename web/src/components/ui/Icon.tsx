import { cn } from '@/lib/cn';
import type { JSX, SVGProps } from 'react';

/**
 * The icon set. Stroke-based, 24×24, `currentColor` throughout so an icon
 * inherits whatever token colour its container sets. `filled` swaps to a solid
 * shape — colour is never the only signal for an active state (DESIGN_SYSTEM §6).
 */
export type IconName =
  | 'heart'
  | 'bookmark'
  | 'repost'
  | 'comment'
  | 'share'
  | 'eye'
  | 'more'
  | 'close'
  | 'check'
  | 'alert'
  | 'chevron-left'
  | 'chevron-right'
  | 'chevron-down'
  | 'arrow-left'
  | 'search'
  | 'plus'
  | 'sliders'
  | 'user'
  | 'users'
  | 'bell'
  | 'compass'
  | 'activity'
  | 'flag'
  | 'sun'
  | 'moon'
  | 'monitor'
  | 'image'
  | 'send'
  | 'lock'
  | 'mail'
  | 'shield'
  | 'grid'
  | 'trash'
  | 'link'
  | 'download'
  | 'spinner'
  | 'verified';

type Shape = (filled: boolean) => JSX.Element;

const shapes: Record<IconName, Shape> = {
  heart: (filled) => (
    <path
      d="M12 20.4 4.1 12.5a5.1 5.1 0 0 1 0-7.3 5.1 5.1 0 0 1 7.2 0l.7.7.7-.7a5.1 5.1 0 0 1 7.2 0 5.1 5.1 0 0 1 0 7.3Z"
      fill={filled ? 'currentColor' : 'none'}
    />
  ),
  bookmark: (filled) => (
    <path
      d="M6.5 3.75h11a1 1 0 0 1 1 1v15.5L12 16.1l-6.5 4.15V4.75a1 1 0 0 1 1-1Z"
      fill={filled ? 'currentColor' : 'none'}
    />
  ),
  repost: (filled) => (
    <>
      <path d="M16.5 2.5 20.5 6.5l-4 4" fill="none" />
      <path d="M20.5 6.5H7.5a3 3 0 0 0-3 3v2.5" fill={filled ? 'currentColor' : 'none'} />
      <path d="M7.5 21.5 3.5 17.5l4-4" fill="none" />
      <path d="M3.5 17.5h13a3 3 0 0 0 3-3V12" fill="none" />
    </>
  ),
  comment: (filled) => (
    <path
      d="M20.5 11.6a8.4 8.4 0 0 1-12.2 7.5L3.5 20.5l1.4-4.9A8.4 8.4 0 1 1 20.5 11.6Z"
      fill={filled ? 'currentColor' : 'none'}
    />
  ),
  share: () => (
    <>
      <path d="M12 15.5V3.2" fill="none" />
      <path d="m8.2 7 3.8-3.8L15.8 7" fill="none" />
      <path d="M5 14v5.5a1.5 1.5 0 0 0 1.5 1.5h11a1.5 1.5 0 0 0 1.5-1.5V14" fill="none" />
    </>
  ),
  download: () => (
    <>
      <path d="M12 3.2v12.3" fill="none" />
      <path d="m8.2 11.7 3.8 3.8 3.8-3.8" fill="none" />
      <path d="M5 14v5.5a1.5 1.5 0 0 0 1.5 1.5h11a1.5 1.5 0 0 0 1.5-1.5V14" fill="none" />
    </>
  ),
  eye: () => (
    <>
      <path d="M2.2 12S6 5.5 12 5.5 21.8 12 21.8 12 18 18.5 12 18.5 2.2 12 2.2 12Z" fill="none" />
      <circle cx="12" cy="12" r="3" fill="none" />
    </>
  ),
  more: () => (
    <>
      <circle cx="5" cy="12" r="1.4" fill="currentColor" stroke="none" />
      <circle cx="12" cy="12" r="1.4" fill="currentColor" stroke="none" />
      <circle cx="19" cy="12" r="1.4" fill="currentColor" stroke="none" />
    </>
  ),
  close: () => (
    <>
      <path d="m6 6 12 12" fill="none" />
      <path d="M18 6 6 18" fill="none" />
    </>
  ),
  check: () => <path d="m4.5 12.5 5 5 10-11" fill="none" />,
  alert: () => (
    <>
      <path d="M12 3.4 22 20.6H2Z" fill="none" />
      <path d="M12 10v4.4" fill="none" />
      <circle cx="12" cy="17.6" r="0.9" fill="currentColor" stroke="none" />
    </>
  ),
  'chevron-left': () => <path d="M15 4.5 7.5 12l7.5 7.5" fill="none" />,
  'chevron-right': () => <path d="M9 4.5 16.5 12 9 19.5" fill="none" />,
  'chevron-down': () => <path d="M4.5 9 12 16.5 19.5 9" fill="none" />,
  'arrow-left': () => (
    <>
      <path d="M20 12H4" fill="none" />
      <path d="m10 6-6 6 6 6" fill="none" />
    </>
  ),
  search: () => (
    <>
      <circle cx="11" cy="11" r="6.8" fill="none" />
      <path d="m20.6 20.6-4.7-4.7" fill="none" />
    </>
  ),
  plus: () => (
    <>
      <path d="M12 4.8v14.4" fill="none" />
      <path d="M4.8 12h14.4" fill="none" />
    </>
  ),
  sliders: () => (
    <>
      <path d="M4 6.5h6M14 6.5h6" fill="none" />
      <path d="M4 12h10M18 12h2" fill="none" />
      <path d="M4 17.5h4M12 17.5h8" fill="none" />
      <circle cx="12" cy="6.5" r="1.8" fill="none" />
      <circle cx="16" cy="12" r="1.8" fill="none" />
      <circle cx="10" cy="17.5" r="1.8" fill="none" />
    </>
  ),
  user: (filled) => (
    <>
      <circle cx="12" cy="8.2" r="3.9" fill={filled ? 'currentColor' : 'none'} />
      <path
        d="M4.2 20.5a7.8 7.8 0 0 1 15.6 0"
        fill={filled ? 'currentColor' : 'none'}
      />
    </>
  ),
  users: () => (
    <>
      <circle cx="9.2" cy="8.4" r="3.6" fill="none" />
      <path d="M2.6 20.4a6.6 6.6 0 0 1 13.2 0" fill="none" />
      <path d="M16.4 5.2a3.6 3.6 0 0 1 0 6.6" fill="none" />
      <path d="M18.2 14.6a6.6 6.6 0 0 1 3.2 5.8" fill="none" />
    </>
  ),
  bell: (filled) => (
    <>
      <path
        d="M18.2 9.4a6.2 6.2 0 1 0-12.4 0c0 4.9-2 6.1-2 6.1h16.4s-2-1.2-2-6.1Z"
        fill={filled ? 'currentColor' : 'none'}
      />
      <path d="M13.7 19.2a2 2 0 0 1-3.4 0" fill="none" />
    </>
  ),
  compass: () => (
    <>
      <circle cx="12" cy="12" r="9" fill="none" />
      <path d="m15.6 8.4-2.1 5.1-5.1 2.1 2.1-5.1Z" fill="none" />
    </>
  ),
  activity: () => <path d="M2.8 12h4l3-8 4.4 16 3-8h4" fill="none" />,
  flag: () => (
    <>
      <path d="M5 21V3.6" fill="none" />
      <path d="M5 3.6h12.4l-2.5 4 2.5 4H5Z" fill="none" />
    </>
  ),
  sun: () => (
    <>
      <circle cx="12" cy="12" r="4" fill="none" />
      <path
        d="M12 2.6v2.2M12 19.2v2.2M2.6 12h2.2M19.2 12h2.2M5.4 5.4l1.6 1.6M17 17l1.6 1.6M18.6 5.4 17 7M7 17l-1.6 1.6"
        fill="none"
      />
    </>
  ),
  moon: () => (
    <path d="M20.6 14.8A8.8 8.8 0 1 1 9.2 3.4a7.2 7.2 0 0 0 11.4 11.4Z" fill="none" />
  ),
  monitor: () => (
    <>
      <rect x="2.8" y="4" width="18.4" height="12.6" rx="2" fill="none" />
      <path d="M8.5 20.6h7M12 16.6v4" fill="none" />
    </>
  ),
  image: () => (
    <>
      <rect x="3" y="4.4" width="18" height="15.2" rx="2.2" fill="none" />
      <circle cx="8.6" cy="9.6" r="1.7" fill="none" />
      <path d="m3.8 17.4 4.8-4.8 3.6 3.6 3-3 5 5" fill="none" />
    </>
  ),
  send: () => (
    <>
      <path d="M21.4 2.6 2.6 10.4l7.6 3.4 3.4 7.6Z" fill="none" />
      <path d="M21.4 2.6 10.2 13.8" fill="none" />
    </>
  ),
  lock: () => (
    <>
      <rect x="4.2" y="10.4" width="15.6" height="10.4" rx="2.2" fill="none" />
      <path d="M8 10.4V7.6a4 4 0 0 1 8 0v2.8" fill="none" />
    </>
  ),
  mail: () => (
    <>
      <rect x="2.6" y="4.8" width="18.8" height="14.4" rx="2.2" fill="none" />
      <path d="m3.4 7 8.6 5.8L20.6 7" fill="none" />
    </>
  ),
  shield: () => (
    <path d="M12 2.6 20 5.4v6.2c0 4.9-3.3 8.5-8 9.8-4.7-1.3-8-4.9-8-9.8V5.4Z" fill="none" />
  ),
  grid: () => (
    <>
      <rect x="3.4" y="3.4" width="7" height="7" rx="1.6" fill="none" />
      <rect x="13.6" y="3.4" width="7" height="7" rx="1.6" fill="none" />
      <rect x="3.4" y="13.6" width="7" height="7" rx="1.6" fill="none" />
      <rect x="13.6" y="13.6" width="7" height="7" rx="1.6" fill="none" />
    </>
  ),
  trash: () => (
    <>
      <path d="M3.8 6.6h16.4" fill="none" />
      <path d="M9 6.6V4.9a1.2 1.2 0 0 1 1.2-1.2h3.6A1.2 1.2 0 0 1 15 4.9v1.7" fill="none" />
      <path d="M6.2 6.6v13a2 2 0 0 0 2 2h7.6a2 2 0 0 0 2-2v-13" fill="none" />
    </>
  ),
  link: () => (
    <>
      <path d="M10.2 13.8a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1.4 1.4" fill="none" />
      <path d="M13.8 10.2a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1.4-1.4" fill="none" />
    </>
  ),
  spinner: () => (
    <circle cx="12" cy="12" r="9" fill="none" strokeDasharray="44" strokeDashoffset="14" />
  ),
  verified: () => (
    <>
      <path
        d="m12 2.6 2.4 2 3.1-.4 1 3 2.7 1.6-1.3 2.9 1.3 2.9-2.7 1.6-1 3-3.1-.4-2.4 2-2.4-2-3.1.4-1-3-2.7-1.6L4.1 11.7 2.8 8.8l2.7-1.6 1-3 3.1.4Z"
        fill="currentColor"
        stroke="none"
      />
      <path d="m8.6 12 2.4 2.4 4.4-4.6" fill="none" stroke="var(--k-bg-base)" />
    </>
  ),
};

/**
 * Sizes are multiples of `space.1`, so an icon can never drift off the grid.
 * `inherit` tracks the surrounding type scale instead.
 */
export type IconSize = 'xs' | 'sm' | 'md' | 'lg' | 'xl' | 'inherit';

const sizeValues: Record<IconSize, string> = {
  xs: 'calc(var(--k-space-1) * 3)',
  sm: 'calc(var(--k-space-1) * 4)',
  md: 'calc(var(--k-space-1) * 4.5)',
  lg: 'calc(var(--k-space-1) * 5)',
  xl: 'calc(var(--k-space-1) * 6)',
  inherit: '1.25em',
};

export interface IconProps extends Omit<SVGProps<SVGSVGElement>, 'name' | 'width' | 'height'> {
  name: IconName;
  size?: IconSize;
  filled?: boolean;
  /** Provide when the icon is the only content of an interactive control. */
  title?: string;
}

export function Icon({
  name,
  size = 'inherit',
  filled = false,
  title,
  className,
  strokeWidth = 1.7,
  ...rest
}: IconProps) {
  const shape = shapes[name];
  const dimension = sizeValues[size];
  return (
    <svg
      viewBox="0 0 24 24"
      width={dimension}
      height={dimension}
      fill="none"
      stroke="currentColor"
      strokeWidth={strokeWidth}
      strokeLinecap="round"
      strokeLinejoin="round"
      role={title ? 'img' : 'presentation'}
      aria-hidden={title ? undefined : true}
      aria-label={title}
      className={cn('shrink-0', name === 'spinner' && 'k-spin', className)}
      {...rest}
    >
      {title ? <title>{title}</title> : null}
      {shape(filled)}
    </svg>
  );
}
