# KLECT — Agent Entry Point

> **Any Claude agent, any account, any session: read this file first, then `docs/PROJECT_STATE.md`.**
> `PROJECT_STATE.md` is the single source of truth for *what is done and what is next*.
> Update it before you finish a work session. Never leave it stale.

---

## What we are building

**Klect** — a social network where the *unit of content is a collection*, not a post.

> Twitter/X for the social graph and feed interactions.
> Pinterest for the visual surfing experience.
> A three-level curation hierarchy nobody else has.

### The hierarchy (this is the core idea — never flatten it)

```
Collection            e.g. "Anime"            ← top-level shelf a user owns
  └── Subcollection   e.g. "JJK", "One Piece" ← themed group inside the collection
        └── Item      e.g. "Gojo — Vol.11 cover" ← a thing, with 1..n photos
              └── Media (photos)
```

Every one of those three levels is independently **likeable, saveable, repostable, commentable, shareable, reportable, and viewable-with-counts**. That symmetry is the product. Do not implement it for items only.

### The two feeds

| Feed | Modelled on | Behaviour |
|---|---|---|
| **Surf** (home) | Pinterest | Masonry grid of recommended + followed collections/subcollections/items. Infinite. Mixed entity types. |
| **Pulse** (following) | X | Chronological/ranked stream of posts, reposts, quotes from people you follow. |

### The signature gesture contract (do not change without updating both apps)

| Gesture on a surf card | Result |
|---|---|
| **single tap** | opens the **Closeup** — the organised detail sheet: all images in the set, full metadata, views/likes/saves/reposts, owner, sibling items, parent collection breadcrumb, comments |
| **double tap** | **immersive fullscreen** image viewer — pinch/pan/swipe between images, chrome auto-hides |
| **long press** | radial quick-action peek: like / save / repost / share / report |

"Show when clicked, hidden but easily accessible" — chrome and secondary actions are hidden at rest and one gesture away. Never a wall of buttons.

---

## Repo layout & who owns what

```
klect/
├── AGENTS.md              ← you are here
├── CLAUDE.md              ← points at this file
├── docs/
│   ├── PROJECT_STATE.md   ← ★ LIVE STATUS BOARD — read + update every session
│   ├── ARCHITECTURE.md    ← system design, data flow, realtime strategy
│   ├── DESIGN_SYSTEM.md   ← "Editorial Noir" — colour/type/space/motion contract
│   ├── DATA_MODEL.md      ← every table, every RLS policy, every trigger, explained
│   └── CHECKLIST.md       ← the full acceptance checklist (supersedes the user's short list)
├── packages/tokens/       ← tokens.json = SINGLE SOURCE OF TRUTH for design values
│                            `node build.mjs` regenerates Dart + CSS. Never hand-edit outputs.
├── supabase/
│   ├── migrations/        ← numbered SQL. Applied to project `new_klect`.
│   └── functions/         ← Deno edge functions
├── mobile/                ← Flutter / Dart — iOS + Android
└── web/                   ← Next.js 15 / TypeScript — public web + /admin
```

### Why two languages (deliberate, not accidental)

- **mobile = Flutter/Dart.** Impeller is the default renderer in 2026; pre-compiled shaders mean the masonry scroll + hero transitions hold 120fps with no shader-compile jank. Dart's `AnimationController` composition is what makes the premium motion affordable.
- **web = Next.js/TypeScript.** Public collection pages need real SEO and streamed RSC payloads. Admin needs a dense data-grid UI that's native to the web.
- **shared = Postgres.** All business rules live in SQL (RLS + triggers + RPC), so both clients stay thin and can never disagree about permissions or counts.

---

## Hard rules for every agent

1. **Counts are never computed in the client.** Every likeable/saveable entity carries `like_count`, `save_count`, `repost_count`, `comment_count`, `view_count` columns kept correct by database triggers. Clients read the column and apply an optimistic delta. This is why counts feel instant.
2. **Every write goes through an RPC or a table with RLS.** No client ever holds the service-role key. Ever.
3. **Toggle actions are idempotent RPCs** (`toggle_like`, `toggle_save`, `toggle_repost`) that return the authoritative new state + count. Optimistic UI first, reconcile with the return value.
4. **`entity_type` enum is `('collection','subcollection','item','post','comment')`.** Polymorphic social tables use `(entity_type, entity_id)`. Add a new entity? Update the enum *and* the trigger dispatch.
5. **Never hand-write a colour, radius, duration, or spacing value.** Import from the generated token file. A raw hex in a widget/component is a bug.
6. **Design tokens change → run `node packages/tokens/build.mjs`** and commit the regenerated Dart + CSS together.
7. **Before you finish: update `docs/PROJECT_STATE.md`** — the Status Board table, the Session Log, and Next Actions.

## Rules specific to Kiro

These apply in addition to everything above, specifically when the agent is Kiro:

1. **Never delete anything without asking first.** This covers files, directories, database tables/rows, migrations, Supabase projects/branches, git branches/tags, GitHub repos, and Vercel projects/deployments. Always state what will be deleted and wait for explicit confirmation before running the delete.
2. This applies regardless of how reversible the action seems (e.g. files recoverable via git) — ask first, every time.

## Supabase target

| | |
|---|---|
| Project name | `new_klect` |
| Project ref | `dikhuygcwxnrsckqglzg` |
| Region | ap-southeast-2 |
| URL | `https://dikhuygcwxnrsckqglzg.supabase.co` |

An older project named **`Klecto`** (`qqfhtjxfbneanrvihstb`) holds a v1 schema of the same idea. It is the historical reference only — **do not write to it**. All work targets `new_klect`.
