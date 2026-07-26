# CHAT UPGRADE PLAN — WhatsApp-parity features

> **STATUS: ✅ SHIPPED 2026-07-26.** All six items below are implemented; 0017 is applied to the
> live DB and smoke-tested; the full `verify.sh` sweep is green. Only the "deliberately deferred"
> list remains open. Kept for the contract details and deferred-work record.
>
> Written 2026-07-26 after a file-level audit of both clients + schema.
> Scope: close the gaps found in the chat audit. Mobile-first (chat is a mobile-led surface);
> web already renders groups and will pick up management UI in a later pass.

## Feature status going in

Already shipped: edit/delete message, reply+quote, reactions (6 quick + double-tap ❤), report from
chat, profile-from-header, pin/mute/archive conversation, block from thread, typing, sent/seen ticks,
photo messages, entity-share cards, unread badges, `allow_messages_from` enforcement.

Gaps to close now:

| # | Feature | Layer | Status before |
|---|---|---|---|
| 1 | Swipe-to-reply gesture on bubbles | mobile UI only | ABSENT |
| 2 | Tap a quoted reply → jump to original | mobile UI only | broken (callback never wired) |
| 3 | Forward a message | mobile UI + storage copy | ABSENT |
| 4 | Search within a conversation | mobile UI + query | ABSENT |
| 5 | Group chats: create + manage | **DB migration** + mobile UI | schema-ready, no RPC, no UI |
| 6 | Report-sheet `p_message` uuid bug | mobile | **fixed** (details now → `p_details`) |

Deliberately deferred (recorded, not forgotten): per-message delete-for-me, "delivered" tick tier
(needs push receipts), last-seen outside an open thread, full emoji picker for reactions, web
management parity (edit/pin/mute/archive/group admin on web).

---

## 5. Group chats — the contract

**Migration `supabase/migrations/0017_group_chats.sql`** (cannot be applied from this machine —
no `SUPABASE_ACCESS_TOKEN` and the Supabase MCP is unauthorized. Apply via dashboard SQL editor or
`supabase db push` from an authorized session. Clients compile and degrade to a server-error toast
until it lands.)

Schema already supports groups: `conversations.kind='group'` + `title/description/avatar_path`,
`conversation_members.role owner|admin|member`, `is_conversation_admin(uuid)` helper,
`message_kind='system'`. The migration adds only the RPC surface (all `security definer`,
`search_path` pinned, `execute` granted to `authenticated` only — matching the 0012 hardening):

- `create_group(p_title text, p_members uuid[], p_description text default null, p_avatar_path text default null) returns uuid`
  — title trimmed 1..80 chars; members deduped, self-excluded, capped at 64; drop anyone in a
  `blocks` pair with the caller; error `group_needs_members` if none remain. Caller → `owner`,
  rest → `member`. Inserts a `system` message "created the group". Returns conversation id.
- `add_group_members(p_conversation uuid, p_members uuid[])` — group + `is_conversation_admin`
  required; skips blocked pairs and current members; **re-joins** rows with `left_at` set (clears
  `left_at`, resets `unread_count`/`last_read_at`); `system` message per join.
- `remove_group_member(p_conversation uuid, p_member uuid)` — self-removal (leave) always allowed;
  otherwise caller admin/owner, and admins cannot remove the owner. Sets `left_at`. If the **owner**
  leaves, ownership auto-transfers to the earliest-joined admin, else earliest member; if the group
  empties, it is simply left dormant. `system` message ("left" / "was removed").
- `update_group_info(p_conversation uuid, p_title text default null, p_description text default null, p_avatar_path text default null)`
  — admin only; null args mean "keep"; rename emits a `system` message.
- `set_group_member_role(p_conversation uuid, p_member uuid, p_role member_role)` — owner only;
  granting `owner` transfers it (previous owner becomes `admin`).

Error convention follows `start_dm`: `raise exception` with stable snake_case messages
(`not_admin`, `not_group`, `not_member`, `group_needs_members`, `title_required`) which the mobile
error mapper surfaces as human copy.

**Mobile UI**
- Inbox app bar gains **New group** → member picker (people you follow + `search_all` people
  results, multi-select chips) → name/description step → `create_group` → push the thread.
- Group thread header tap → **Group info screen** (replaces profile push for groups): avatar/title/
  description, member list with role badges; admins add members / remove members / rename; owner
  promotes/demotes; anyone leaves. Mute/report already exist in the overflow.
- `ChatApi` gains thin wrappers for the five RPCs; roles come from the already-parsed
  `ConversationMember.role`.

## 1–4. Client-only features (no schema change)

- **Swipe-to-reply**: right-drag on any non-deleted, non-system bubble; translate with resistance,
  reply glyph fades/fills, trigger at ~56–64 px with a light haptic, then arm the composer reply
  target (same path as the long-press action). Must not fight horizontal paging or the photo viewer.
- **Quote-jump**: wire the existing `MessageBubble.onReplyTap` in `conversation_screen.dart` —
  scroll to the quoted id if loaded; otherwise page older history until found (cap ~10 pages) then
  scroll + brief highlight pulse.
- **Forward**: long-press sheet gains **Forward** on any non-deleted message → conversation picker
  sheet (reuses inbox entries, multi-select) → for each target: text/entity-share forwarded as a new
  message (`reply_to_id` NOT carried); image attachments are **copied** in Storage
  (`chat` bucket `.copy()` to `{me}/{target_conversation}/{uuid}`) so recipients can actually read
  them — never reference the source conversation's path. Toast on success.
- **In-conversation search**: search icon in the thread app bar → inline search field; server-side
  `ilike` on `messages.body` scoped to the conversation (deleted excluded), newest-first, limit 50;
  results overlay with highlighted snippets; tap → same jump-and-pulse as quote-jump.

## Acceptance

`bash scripts/verify.sh` fully green (tokens + `flutter analyze`/`test`/`build web` +
`tsc`/`next lint`/`next build`), zero new analyzer issues, existing tests untouched or extended,
tokens only — no hand-written colours/durations. `PROJECT_STATE.md` updated when done.
