# KLECT — "Editorial Noir"

Values live in `packages/tokens/tokens.json` and compile to `mobile/lib/design/tokens.g.dart`,
`web/src/styles/tokens.g.css`, `web/src/design/tokens.g.ts`.
**A raw hex, px, ms, or cubic-bezier anywhere in application code is a bug.**

---

## 1. The idea

A collection app should feel like a **private gallery at night**, not a dashboard. Three consequences:

1. **Dark-first.** Base is `#0A0B0E` — near-black, not `#000`. Pure black causes halation around light
   text on OLED and flattens depth; this keeps the battery win while the UI still has air.
2. **Depth comes from surface, not shadow.** Elevation steps the ramp `surface1 → surface4`.
   Shadows appear once, softly, under floating chrome only. Stacked shadows read cheap.
3. **The photo is the hero.** Chrome is quiet: `textSecondary` for metadata, one oxblood accent
   (`#A6323F` dark · `#7C2531` light) reserved for the user's own intent — save, primary CTA,
   focus ring. Everything else in the UI is greyscale so that user photography is the only source
   of colour. Oxblood reads wine cellar and leather binding — deep and desaturated where
   Pinterest's red is loud. **The accent is always a flat fill; a gradient carrying the accent is
   a bug.** `semantic.warning` stays amber — it is a warning colour, not brand.

The 60/30/10 split: 60% graphite neutrals, 30% surface/border structure, 10% oxblood + action colours.

The dark accent ramp is three chromatic steps plus two alphas: press `#8C2A35` · default `#A6323F`
· hover `#BE4450`, with `subtle`/`ring` as alpha layers of the default. `border.focus` and
`match.peak` sit on the hover step in dark — it is the first step of the family that clears 3:1
against every surface tier a ring can wrap. Light uses `#7C2531` with darker hover/press.

### Action colours are semantic and never swapped

| action | colour | why |
|---|---|---|
| like | `#FF4D6D` rose | affection, not urgency |
| save | `#A6323F` oxblood | the brand action — collecting is the point |
| repost | `#2DD4A7` mint | circulation |
| comment | `#4C9AFF` azure | conversation |
| share | `#A5ACBA` grey | utility, not an achievement |

---

## 2. Type

- **Display** — `Fraunces` (variable: `opsz`, `SOFT`, `WONK`). Only for collection names, profile
  display names, and empty-state headlines. A sharp editorial serif at large size is what separates
  "gallery" from "admin panel". Mobile pins the `opsz` axis to the rendered size.
- **UI** — `Instrument Sans` (variable `wght`). Everything else.
- **Weights are exact.** The token ramp's 450/550/650 are real variable-font positions —
  `FontVariation('wght', …)` on mobile, numeric weights on web — never rounded to static hundreds.
- **Both families are bundled.** Mobile ships the variable TTFs via pubspec `fonts:` (no runtime
  fetch, no Roboto first paint; OFL licences ride along in `assets/fonts/`). Web loads the same
  pair through `next/font/google` with `display: swap`.
- **Counts** — always **tabular figures**. A like count that shifts width while animating looks broken.

Scale: `display1/2/3 · title1/2/3 · body · bodyStrong · callout · label · caption · micro · count`.

---

## 3. Motion

Two rules, and they are absolute:

1. **Anything the finger drives is a spring. Anything the system drives is a curve.**
2. **Nothing exceeds 480ms.** Premium reads as *immediate*, not slow.

| moment | spec |
|---|---|
| tap feedback | scale `0.97`, `snappy` spring, no opacity change |
| like/save burst | `pop` spring, icon overshoots to `1.25` then settles; particle burst ≤ 400ms |
| card → closeup | shared-element hero on the cover, `emphasized` curve, `hero` duration |
| closeup → fullscreen | cross-fade + scale to fit, chrome fades out first (`fast`) |
| sheet | `sheet` spring, drag-to-dismiss with velocity carry |
| grid item entry | staggered fade+rise, `stagger` per index, capped at 8 items |
| count change | roll the digit vertically; never fade the whole number |

**Reduced motion:** honour `MediaQuery.disableAnimations` / `prefers-reduced-motion`.
Replace transforms with a 90ms opacity fade. Never disable feedback entirely — remove *travel*, keep
*confirmation*.

---

## 4. The gesture contract

This is the product. It is identical on mobile and web (web maps long-press → right-click / hover menu).

| gesture on a surf card | result |
|---|---|
| **single tap** | **Closeup** — organised detail: every image in the set, full metadata, live counts, owner, breadcrumb, siblings, comments |
| **double tap** | **Immersive** — fullscreen viewer, pinch/pan, swipe between images, chrome auto-hides after 2s |
| **long press** | **Peek** — radial quick actions: like · save · repost · share · report |

Implementation note: a naive `onTap` + `onDoubleTap` pair adds the double-tap delay (~260ms) to every
single tap, which destroys the feel. **Resolve it yourself:** on first tap start a `doubleTapMs`
timer and *optimistically* begin the closeup transition; if a second tap arrives inside the window,
cancel and escalate to immersive. The user perceives zero delay.

### "Hidden but easily accessible"

Secondary actions are never a visible row of buttons. At rest a card shows **the photo and nothing
else** — counts and actions fade in on hover (web) or live behind long-press (mobile). The closeup
shows one action bar; everything rarer lives in the overflow sheet. The rule: **the most common
action is one gesture away, the rest are two, nothing is three.**

---

## 5. Components

**Masonry tile** — reserve the tile from `width`/`height` *before* the image loads, paint `blurhash`,
cross-fade the photo in over `fast`. The grid must never reflow. Columns: 2 / 2 / 3 / 4 / 5 by breakpoint.

**Count pill** — tabular digits, icon left, colour only when the viewer has acted. Inactive = `textSecondary`.

**Closeup** — on mobile a draggable sheet from 55% → full; on web a centred modal with the URL updated
(deep-linkable, back-button correct). Both share the same payload from `get_closeup`.

**Empty states** — display-serif headline + one sentence + one action. Never an illustration-only dead end.

**Skeletons** — shimmer between `skeleton.base` and `skeleton.shimmer`. Match the real layout's shape
exactly, or the swap-in flashes.

---

## 6. Accessibility floor (non-negotiable)

- Body text ≥ 4.5:1, large text and icons ≥ 3:1, on **both** themes.
  **Verified for the oxblood rebrand:** `text.onAccent` ivory `#FFF6EC` clears **4.5:1 on every
  accent step it sits on** — 6.24:1 on dark `accent.default` `#A6323F`, 4.75:1 on dark hover
  `#BE4450`, 9.07:1 on light `#7C2531`. Dark `border.focus`/`match.peak` use the hover step
  because it clears **3:1 on every surface tier** (3.75 on `bg.base` → 3.09 on `surface3`);
  the dark default itself is 2.95:1 on `bg.base`, so **oxblood is never body-text on dark** —
  it appears as a fill under ivory, or as an icon tint where the fill-state change (not hue) is
  the signal. On light, `accent.default` is 9.38:1 against `bg.base` and may be used as text.
  If you change a colour, re-check the ratio before committing — the floor is the contract,
  not the hex.
- Every interactive target ≥ 44×44 including hit-slop.
- Every image field accepts `alt_text`; the closeup surfaces it; screen readers announce
  "photo 2 of 5" in the immersive viewer.
- Focus ring: `border.focus` oxblood, 2px, always visible on keyboard nav — never `outline: none`.
- Colour is never the only signal: the like state also changes icon fill, not just hue.
