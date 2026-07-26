# KLECT — web

Next.js 15 (App Router) + TypeScript strict + Tailwind v4. Public site, the app, and `/admin`.

This is the **foundation**. Feature agents replace page files wholesale; everything under
`src/lib`, `src/design`, `src/providers` and `src/components/ui` is the contract they build on.

```bash
npm run dev        # http://localhost:3000
npm run typecheck  # tsc --noEmit
npm run lint       # next lint
npm run build      # next build
npm run test       # vitest
```

Copy `.env.example` → `.env.local`. Only the **publishable** key ever appears here.

---

## The four rules, and where they are enforced

### 1. No hardcoded design values

`src/styles/tokens.g.css` and `src/design/tokens.g.ts` are **generated** from
`packages/tokens/tokens.json`. Never edit them; regenerate with `node packages/tokens/build.mjs`.

`src/styles/theme.css` maps every Tailwind theme key onto a `var(--k-*)` using `@theme inline`, so
utilities emit the custom property at the point of use and the whole UI re-themes with no React
re-render. Spacing derives from one token: `--spacing: var(--k-space-1)`, so `p-6` compiles to
`calc(var(--k-space-1) * 6)`.

| you want | you write |
|---|---|
| surfaces | `bg-base` `bg-sunken` `bg-surface-1…4` `bg-scrim` `glass` |
| text | `text-ink` `text-ink-2` `text-ink-3` `text-ink-on-accent` |
| lines | `border-line-subtle` `border-line` `border-line-strong` |
| brand | `bg-accent` `text-accent` `bg-accent-subtle` |
| actions | `text-like` `text-save` `text-repost` `text-comment` `text-share` |
| type | `text-display1…3` `text-title1…3` `text-body` `text-body-strong` `text-callout` `text-label` `text-caption` `text-micro` `text-count` |
| radius | `rounded-xs…3xl` |
| motion | `dur-instant…deliberate`, `ease-standard/decelerate/accelerate/emphasized/overshoot` |
| layout | `content-max` `readable-max` `tap-min` `k-masonry` |
| focus | `focus-ring` (brass, 2px, never removed) |
| counts | `tabular` |
| z-index | `z-raised` `z-sticky` `z-chrome` `z-sheet` `z-modal` `z-toast` `z-immersive` |

Breakpoints are the one exception: a media query cannot contain `var()`, so `tailwind.config.ts`
derives `screens` from `layout.breakpoint` in `tokens.g.ts`. Still zero literals.

`src/design/motion.ts` holds the framer-motion presets (`curve.*`, `springy.*`, `fadeRise`, …) plus
the few DESIGN_SYSTEM constants `tokens.json` does not carry yet: `pressScale`, `burstScale`,
`burstMs`, `gesture.*`. Import from there rather than typing a number.

`src/app/global-error.tsx` is the only file allowed literal style values — it renders its own
`<html>` and cannot assume the token stylesheet loaded.

### 2. Counts are never computed in the client

Read the counter columns; apply an optimistic delta; reconcile with the `{active, count}` the RPC
returns. All of that already exists:

```tsx
'use client';
import { useEntitySocial } from '@/providers/interactions-provider';
import { seedFromSurfCard } from '@/lib/interactions';

const social = useEntitySocial('item', card.entity_id, seedFromSurfCard(card));
// social.liked / likeCount / saved / saveCount / reposted / repostCount /
// commentCount / viewCount / following / followerCount / pending
social.like();            // instant local flip, RPC after coalescing, rollback on error
social.save('note');
social.repost('quote');
```

Or drop in the whole bar — identical code path for a collection, subcollection, item, post or
comment:

```tsx
<ActionBar type="collection" id={id} title={name} seed={seed} />
```

The engine is `src/lib/interactions.ts`: framework-free and unit tested
(`src/lib/interactions.test.ts`). Its invariant:

```
active = desired
count  = serverCount + (desired === serverActive ? 0 : desired ? +1 : -1)
```

Because the toggles are idempotent flips, ten taps in two seconds cost at most **two** round trips
and always converge on the right state and count. A realtime payload can never stomp a pending
optimistic update.

Live counters: `useRealtimeEntity(type, id)` subscribes to `UPDATE` on the entity row — one event
carries every counter. **Do not mount it per masonry tile**; use it on detail views.
`useRecordView(type, id)` records one view (the server dedupes per viewer per day).
`useAddComment()` posts optimistically and restores the count on failure.

### 3. Never a service-role key

`src/lib/env.ts` reads only `NEXT_PUBLIC_*`. Server work uses `src/lib/supabase/server.ts`
(per-request, current `getAll`/`setAll` cookie API); the browser uses `src/lib/supabase/client.ts`;
`src/middleware.ts` refreshes the session and enforces route access on every request.

### 4. The gesture contract, without the double-tap penalty

`src/components/ui/Pressable.tsx`. The first tap fires `onActivate` **immediately** — nothing is
deferred, so there is no delay to feel. A second tap inside `gesture.doubleTapMs` fires
`onEscalate`; a hold past `gesture.longPressMs` fires `onPeek` and swallows the tap. Right-click and
`Shift+F10` also open the peek; `Enter`/`Space` activate; `F` escalates.

```tsx
<Pressable
  onActivate={() => router.push(closeupHref('item', id))}
  onEscalate={() => openImmersive(id)}
  onPeek={(pos) => openPeek(id, pos)}
/>
```

---

## Layout of the source

```
src/
  app/                  routes (see below)
  components/
    ui/                 the primitive set — import from '@/components/ui'
    chrome/             nav rails, bars, wordmark, theme toggle, placeholders
    auth/               sign in / up / forgot / reset / onboarding
    closeup/            CloseupPanel (shared) + CloseupModal (intercepted)
    settings/
  design/
    tokens.g.ts         GENERATED
    motion.ts           framer-motion presets + gesture constants
  lib/
    api.ts              one typed wrapper per RPC + the table reads the shell needs
    interactions.ts     the optimistic engine
    database.types.ts   GENERATED from the live schema
    entities.ts         entity_type helpers, table map, hrefs
    errors.ts           PostgrestError → KlectError { kind, retryable }
    format.ts           compactCount, shortTimeAgo, validators
    routes.ts           every path, plus the middleware prefix lists
    seo.ts              buildMetadata / defaultMetadata
    storage.ts          bucket URLs and size limits
    supabase/           client.ts · server.ts · middleware.ts
    types.ts            the jsonb payload shapes, read off the live functions
    viewer.ts           per-request viewer bootstrap (React `cache`)
  providers/            theme · toast · session · interactions
  styles/
    tokens.g.css        GENERATED
    theme.css           Tailwind theme — every entry points at a token
    globals.css         base layer + keyframes
```

### Primitives

`ActionBar` · `Avatar`/`AvatarStack` · `BlurhashImage` · `Button`/`ButtonLink`/`IconButton` ·
`Chip`/`ChipGroup` · `ConfirmDialog` · `CountPill`/`RollingCount` · `EmptyState` · `ErrorState` ·
`Icon` · `Modal` · `Pressable` · `ReportDialog` · `Sheet` ·
`Skeleton`/`SkeletonGrid`/`SkeletonTile`/`SkeletonRow`/`SkeletonText` · `TextField`/`TextArea` ·
`ToastCard`.

All keyboard accessible with a visible brass focus ring; all respect `prefers-reduced-motion`.

`BlurhashImage` reserves the tile from the cover's intrinsic `width`/`height` **before** the image
loads, paints the blurhash into it, then cross-fades — that is why the grid never reflows. Grid
ratios are clamped to `aspect.gridMin…gridMax`; pass `clamp={false}` in detail views.

### Routes

| group | routes |
|---|---|
| `(marketing)` | `/` `/about` |
| `(auth)` | `/signin` `/signup` `/forgot-password` `/reset-password` `/onboarding` `/suspended` |
| `auth/` | `/auth/callback` `/auth/confirm` `/auth/signout` (route handlers) |
| `(app)` | `/surf` `/pulse` `/search` `/matches` `/notifications` `/messages` `/messages/[conversationId]` `/create` `/settings` `/settings/privacy` `/settings/blocked` `/settings/appearance` `/u/[username]` `/c/[collectionId]` `/s/[subcollectionId]` `/i/[itemId]` |
| root | `/closeup/[type]/[id]` + `@modal/(.)closeup/[type]/[id]` |
| `(admin)` | `/admin` `/admin/reports` `/admin/users` `/admin/content` `/admin/audit` |
| generated | `/sitemap.xml` `/robots.txt` `/opengraph-image` `/icon` |

Pages rendering `PagePlaceholder` are declared but unbuilt — replace the file wholesale. The four
entity routes already ship real `generateMetadata` (titles, descriptions, OG images taken from the
actual cover); keep it when you replace the body.

**Closeup**: an in-app navigation to `/closeup/item/<id>` is intercepted and rendered as a modal over
whatever grid you were on, with the URL updated so it stays shareable and Back closes it. A hard load
of the same URL renders the full page instead. Both feed `CloseupPanel` from the same `get_closeup`
payload.

### Auth and guards

Three layers, in increasing order of authority:

1. `src/middleware.ts` — refreshes the session, redirects signed-out users off protected prefixes,
   bounces signed-in users off `/signin`, gates `/admin` on `user_roles`, sends un-onboarded users to
   `/onboarding` and suspended users to `/suspended`.
2. `src/app/(admin)/layout.tsx` — re-checks staff before rendering.
3. **The database.** Every `admin_*` RPC re-checks `is_staff()` / `is_admin()`, and RLS covers the
   rest. A leaked route exposes nothing.

Sign-up passes `username` and `display_name` in `options.data`; the `handle_new_user` trigger reads
them to seed the profile. Onboarding is three steps — handle, profile, people — and stamps
`profiles.onboarded_at`, which is what the middleware gate reads.

### Theming

Dark by default; light via `[data-theme="light"]`; "system" removes the attribute and lets the
`prefers-color-scheme` block in `tokens.g.css` decide. The choice is persisted to `localStorage`
under `klect-theme` and applied by an inline `<head>` script before first paint — no flash. That same
script writes `<meta name="theme-color">` from the live `--k-bg-base`, which is why no hex appears in
`layout.tsx`.

---

## Conventions worth keeping

- Server Components fetch; Client Components interact. `createClient()` from
  `@/lib/supabase/server` in the former, from `@/lib/supabase/client` in the latter — every function
  in `src/lib/api.ts` takes the client as its first argument so one implementation serves both.
- Failures travel as `KlectError`; `toast.fromError(error, { retry })` picks the copy and offers a
  retry only when retrying could help. A duplicate follow/like is treated as success and never
  toasts.
- Loading states are skeletons shaped like the final layout, never a centred spinner on a full page.
- Every error state offers a way forward (`ErrorState` with `onRetry`).
