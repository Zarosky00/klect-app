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
3. **The photo is the hero.** Chrome is quiet: `textSecondary` for metadata, one brass accent
   (`#F0B429`) reserved for the user's own intent — save, primary CTA, focus ring. Everything else
   in the UI is greyscale so that user photography is the only source of colour.

The 60/30/10 split: 60% graphite neutrals, 30% surface/border structure, 10% brass + action colours.

### Action colours are semantic and never swapped

| action | colour | why |
|---|---|---|
| like | `#FF4D6D` rose | affection, not urgency |
| save | `#F0B429` brass | the brand action — collecting is the point |
| repost | `#2DD4A7` mint | circulation |
| comment | `#4C9AFF` azure | conversation |
| share | `#A5ACBA` grey | utility, not an achievement |

---

## 2. Type

- **Display** — `Instrument Serif`. Only for collection names, profile display names, and empty-state
  headlines. A serif at large size is what separates "gallery" from "admin panel".
- **UI** — `Inter`. Everything else.
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
  **Verified:** every text and action colour in `tokens.json` clears **4.5:1** against its theme's
  `bg.base` — worst case is `light/action.repost` at 4.51:1. Three tokens were darkened to reach
  this (`text.tertiary` in both themes, plus `accent.default` and `action.repost` in light). If you
  change a colour, re-check the ratio before committing — the floor is the contract, not the hex.
- Every interactive target ≥ 44×44 including hit-slop.
- Every image field accepts `alt_text`; the closeup surfaces it; screen readers announce
  "photo 2 of 5" in the immersive viewer.
- Focus ring: `border.focus` brass, 2px, always visible on keyboard nav — never `outline: none`.
- Colour is never the only signal: the like state also changes icon fill, not just hue.
