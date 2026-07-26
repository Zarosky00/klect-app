# KLECT

**A social network where the unit of content is a collection.**

X for the social graph. Pinterest for the surfing. A three-level curation hierarchy nobody else has.

```
Collection            "Anime"                    ← a shelf you own
  └── Subcollection   "JJK" · "One Piece"        ← a themed set inside it
        └── Item      "Gojo — Vol.11 cover"      ← a thing, with 1..n photos
```

Every one of those three levels is independently **likeable, saveable, repostable, commentable,
shareable, reportable and view-counted**. That symmetry is the product.

---

## Two feeds

| | modelled on | behaviour |
|---|---|---|
| **Surf** | Pinterest | masonry grid of recommended + followed collections, subcollections and items — ranked, per-user shuffled, infinite |
| **Pulse** | X | chronological stream of posts, reposts and quotes from people you follow |

## Three gestures

| on any card | opens |
|---|---|
| single tap | **Closeup** — every image in the set, full metadata, live counts, breadcrumb, siblings, comments |
| double tap | **Immersive** — fullscreen viewer, pinch/pan, swipe between images, chrome auto-hides |
| long press | **Peek** — like · save · repost · share · report |

Implemented without the usual double-tap delay penalty. See [`docs/DESIGN_SYSTEM.md`](docs/DESIGN_SYSTEM.md) §4.

---

## Stack — deliberately different per surface

| surface | stack | why |
|---|---|---|
| iOS + Android | **Flutter / Dart** | Impeller is the default renderer in 2026 — pre-compiled shaders, no shader-compile jank, real 120fps for the masonry scroll and hero transitions |
| Web + Admin | **Next.js 15 / TypeScript** | RSC streaming, genuine SEO for public collection pages, and a dense data-grid admin that is native to the web |
| Backend | **Postgres / SQL** on Supabase | all business rules live in RLS + triggers + RPCs, so both clients stay thin and can never disagree about permissions or counts |

## Layout

```
klect/
├── AGENTS.md              ← start here if you are an AI agent
├── docs/
│   ├── PROJECT_STATE.md   ← ★ live status board
│   ├── BACKEND_API.md     ← the API contract both clients code against
│   ├── DESIGN_SYSTEM.md   ← "Editorial Noir"
│   └── CHECKLIST.md       ← what "done" means
├── packages/tokens/       ← tokens.json → Dart + CSS + TS. Never hand-edit the generated files.
├── supabase/              ← migrations + schema notes
├── mobile/                ← Flutter
└── web/                   ← Next.js (app + /admin)
```

## Running it

```bash
node packages/tokens/build.mjs
```

```bash
export PATH="/c/src/flutter/bin:$PATH" && cd mobile && flutter pub get && flutter run
```

```bash
cd web && npm install && npm run dev
```

> Building iOS needs a Mac; building Android needs a JDK + Android SDK. Neither is installed on this
> machine — `flutter analyze`, `flutter test` and `flutter build web` are the verification path here.

## Three things to know before changing anything

1. **Counts are columns, not queries.** Triggers maintain every `*_count`. Clients read the column,
   apply an optimistic delta, then reconcile with the `{active, count}` the RPC returns. Clients
   physically cannot write those columns — `UPDATE` is revoked at the column level.
2. **Social tables are polymorphic** over `(entity_type, entity_id)`. One code path serves likes on a
   collection, a subcollection, an item, a post or a comment.
3. **Never hand-write a colour, size, radius, duration or curve.** Import from the generated tokens.
   A raw hex in a widget or component is a bug.
