# Design QA — Follow outcome panel

## Evidence

- Source visual truth: `C:\Users\trial\Downloads\WhatsApp Image 2026-07-27 at 12.35.33 PM.jpeg`
- Rendered implementation: `D:\D drive\coding\Ideas\hackathon\klect\mobile\test\goldens\follow_panel_358x800.png`
- State: dark theme, confirmed follow outcome, panel fully settled below a 44 logical-pixel safe area
- Viewport: 358 × 800 logical pixels
- Source pixels: 716 × 1600 at approximately 2× density, normalized to 358 × 800
- Implementation pixels: 358 × 800 at device-pixel ratio 1

## Full-view comparison

The normalized source and implementation use the same phone width, height, safe-area offset, black background, and top-overlay state. The source contains the surrounding Pinterest profile while the implementation golden intentionally isolates the reusable notification component, so the profile content below the overlay was excluded from fidelity judgments.

The panel matches the source’s near-full-width composition, 16-pixel screen margins, 12-pixel safe-area gap, light inverse surface, dark text, 40-pixel circular avatar slot, two-line message, large rounded corners, and soft elevation. The shipped copy intentionally uses KLECT’s Pulse language rather than Pinterest’s Pins/home-feed wording.

## Focused region comparison

The top notification region was compared at equal normalized size. This focused pass was required because panel height, corner radius, avatar scale, typography wrapping, and internal padding are too small to judge reliably from the full profile screenshot.

### Fidelity surfaces

- Fonts and typography: KLECT’s Instrument Sans remains the product font. The 15/22 body-strong style produces the same two-line density and hierarchy as the reference without clipping.
- Spacing and layout rhythm: 16-pixel outer margins, 12-pixel horizontal content padding, 8-pixel vertical padding, 12-pixel avatar-to-copy gap, and a 20-pixel radius closely reproduce the source proportions.
- Colors and tokens: the dark-screen/light-panel contrast follows the source while using KLECT’s `inverseSurface` and `onInverseSurface` theme tokens for light/dark accessibility.
- Image quality and asset fidelity: production renders the followed person’s real avatar URL; the golden deliberately exercises the required initials fallback because remote images are not stable golden-test inputs.
- Copy and content: all confirmed, unfollowed, queued, and failed messages use the approved KLECT-specific text. The visible confirmed state contains no generic status icon.
- Motion and accessibility: normal motion uses downward slide, fade, and restrained scale settle; reduced motion uses fade only. The panel is a live region, includes the person’s name in its announcement, and supports tap/upward/horizontal dismissal.

## Findings and comparison history

### Iteration 1

- [P2] The first rendered panel was visibly taller and more pill-like than the reference.
  - Evidence: the first capture used 12-pixel vertical padding and a 28-pixel radius, producing a roughly 68-pixel panel against the source’s approximately 60-pixel normalized height.
  - Fix: changed vertical padding to 8 pixels and radius to 20 pixels while preserving the 40-pixel avatar and two-line text.

### Iteration 2

- Post-fix evidence: `mobile/test/goldens/follow_panel_358x800.png`
- No actionable P0, P1, or P2 mismatch remains.

## Follow-up polish

- [P3] A deterministic photographic avatar fixture could make the golden closer to the supplied example, but the current initials state intentionally verifies the production fallback and does not affect live rendering.

## Final result

final result: passed
