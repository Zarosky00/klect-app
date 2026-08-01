# KLECT — Operations

Everything that needs a human with dashboard access, and everything that runs on a schedule.

---

## 1. Things you must click (nothing else can do these)

### a. Enable leaked-password protection
The only unresolved security advisor finding. It is an Auth setting, not SQL.

> Supabase dashboard → **Authentication → Providers → Email** → enable
> **"Prevent use of leaked passwords"**

### b. Give the demo accounts a password (optional)
The 8 demo users were seeded straight into `auth.users` and have no usable password.
To sign in as one: **Authentication → Users** → pick the user → *Reset password*.
Or just sign up fresh — the `handle_new_user` trigger creates the profile automatically.

`klectmod` (`mod@klect.test`) holds the `moderator` role and is the account that can see `/admin`.

### c. Authorize the Figma MCP connector (optional)
Not authorized in the session that built this. Design values live in `packages/tokens/tokens.json`;
if you connect Figma later, push them with the `figma-generate-library` skill rather than
re-authoring values by hand.

---

## 2. Push notifications

**✅ LIVE as of 2026-07-30.** Configured and verified end to end — no action required.

**Edge function:** `push-fanout` v5 (deployed, `verify_jwt = false`)
Handles FCM v1 for both Android and iOS, composes per-type copy, respects muted conversations,
emits a `klect://` deep link, and prunes tokens FCM reports as permanently dead.

Call rows are the exception to the normal display notification: v5 sends a versioned,
high-priority **data-only** Android payload. `KlectFirebaseMessagingService` validates the call,
expiry and payload version, then starts the native Core-Telecom foreground service and CallStyle
surface before Flutter is warm. Routine notifications continue through the `social` channel.

### How it is wired (for reference / disaster recovery)

**Firebase project:** `klect-b776a` (project number `412736900783`), owned by
`2023cse29.gpv@gmail.com`. Android app `1:412736900783:android:98a901f20c45ca83d6ce5a`,
package `com.klect.klect`, with the permanent release cert SHA-256
`460d934b…f11b334f` registered.

`mobile/android/app/google-services.json` is **gitignored** — it is app-config, not a secret, but
it is project-specific. Regenerate it for a new environment with the Firebase MCP
(`firebase_get_sdk_config`) or `Project Settings → Your apps` in the console. The
`com.google.gms.google-services` Gradle plugin in `android/settings.gradle.kts` +
`android/app/build.gradle.kts` consumes it. **Note:** `firebase_messaging` pulls in a dependency
that requires **Android SDK Platform 34** to be installed alongside 36.

GitHub Actions stores the same file as the encrypted repository secret
`GOOGLE_SERVICES_JSON`; both `ci.yml` and `release-android.yml` materialize it only inside the
runner before building. Update that secret whenever the Firebase Android app config changes.

**Secrets set on `new_klect`** (`npx supabase secrets list --project-ref dikhuygcwxnrsckqglzg`):

| secret | source |
|---|---|
| `FCM_SERVICE_ACCOUNT` | Firebase console → Project Settings → Service Accounts → generate private key |
| `PUSH_WEBHOOK_SECRET` | 32 random bytes, hex |

Setting a multi-line JSON secret via `--env-file` avoids the shell-quoting failure you get
passing it inline (`Invalid secret pair: PRIVATE`):

```bash
npx supabase secrets set --project-ref dikhuygcwxnrsckqglzg --env-file .secrets.env.tmp
```

⚠ The service-account JSON and the raw webhook secret are **not kept in this repo**. Both were
deleted after being set. Re-download from Firebase if you ever need them again.

**The webhook is a migration, not a dashboard click.** `notifications_push_fanout_webhook`
creates `public.notify_push_fanout()` + an `after insert` trigger on `public.notifications` that
`net.http_post`s to `push-fanout` (async, so it never blocks the insert). The shared secret is
read at call time from **Supabase Vault** (`vault.decrypted_secrets`, name `push_webhook_secret`)
rather than hardcoded — a literal in the trigger body would sit in plaintext in migration history
forever. `pg_net` is enabled by `enable_pg_net_and_vault_secret`.

If the secret is ever missing from Vault the trigger **skips silently** instead of failing the
insert — a notification must never be lost because push is misconfigured.

### Client side
`lib/core/notifications/push_notifications.dart` (`PushNotifications`) initialises Firebase,
requests permission, and calls the `register_push_token` RPC — plus `onTokenRefresh`, since a
token rotates on reinstall or Play Services update. `RootShell.initState` triggers it;
`AuthController.signOut` calls `unregister()` so a signed-out phone stops receiving the previous
account's push. `Firebase.initializeApp` failures are caught, so a build with no
`google-services.json` degrades to "no push" rather than crashing.

### Verifying it still works

```bash
# 401 — the auth boundary
curl -s -o /dev/null -w "%{http_code}\n" -X POST \
  https://dikhuygcwxnrsckqglzg.supabase.co/functions/v1/push-fanout -d '{}'
```

```sql
-- what the trigger actually got back, last 6 hours
select status_code, content, error_msg from net._http_response order by created desc limit 5;
```

A reply of `{"sent":0,"pruned":1}` against a deliberately invalid token is the strongest cheap
signal: it can only happen if the RSA key imported and the Google OAuth2 exchange succeeded.
`{"sent":0,"reason":"no-devices"}` just means no real phone has registered a token yet.

> ⚠ **`execute_sql` via the Supabase MCP rolls back writes.** A test row inserted that way will
> not exist a moment later. Use `apply_migration` (or the CLI) when a write must persist.

### Notification channels the client must create
`calls` (high priority, ringtone) and `social` (normal). The function already targets them.

### Real-device delivery — verified 2026-07-30

Confirmed on an attached RMX3771 (Android 15) running `1.6.4+14`: a genuine 142-char FCM token
registered into `push_tokens`, `net._http_response` recorded `200 {"sent":1,"pruned":0}`, and the
handset rendered the notification with `tag=FCM-Notification:…`, `channel=social`,
title = actor display name, body = "started following you". That tag is emitted by the Firebase
SDK, so it proves real push rather than the app's stage-1 local-notification path.

> ⚠ **Do not test push with `adb shell am force-stop`.** Force-stop puts the app in Android's
> *stopped state*, and the OS withholds FCM messages until the user manually relaunches the app.
> FCM will still answer `sent:1` while nothing appears in the tray, which looks like a broken
> integration but is not — the queued message is delivered the moment the app is reopened.
> Swiping an app away from recents does **not** set that flag, so ordinary use is unaffected.
> To test a not-running app, use `adb shell am kill` (no stopped flag), or just background it.

---

## 3. Reliable Android calling

The production flag remains globally disabled while physical QA is incomplete. Migration
`android_reliable_calling_v170` adds a private `qa_allowlist` to the existing `reliable_calls`
configuration; use only the two test account UUIDs there. Do not enable the global boolean until
the complete phone matrix is recorded.

`turn-credentials` is JWT-protected and issues one-hour Cloudflare TURN credentials. Store only
these two names in **Supabase Dashboard → Edge Functions → Secrets** (or with a temporary local
`--env-file` that is deleted immediately):

| secret | source |
|---|---|
| `CLOUDFLARE_TURN_KEY_ID` | The TURN key `uid`/ID shown when the Cloudflare TURN key is created (32 characters) |
| `CLOUDFLARE_TURN_API_TOKEN` | The TURN key's generated `key`/Bearer token (the long secret, not a browser/client key) |

Never put either raw value in source, documentation, shell history, a GitHub secret intended for
the client, or chat. Verify only the secret **names** with:

```bash
npx supabase secrets list --project-ref dikhuygcwxnrsckqglzg
```

As of the v1.7.0 implementation pass, these two names were not yet present, so TURN and forced-relay
physical QA remain blocked. FCM secrets are present and `push-fanout` v5 is ACTIVE.

For the mandatory relay-only case, build the same release source with the compile-time QA switch:

```bash
flutter build apk --release --target-platform android-arm64 \
  --dart-define=KLECT_FORCE_TURN_RELAY=true
```

That candidate sets WebRTC `iceTransportPolicy` to `relay`; normal production builds omit the
define and accept direct or relayed candidates. The switch is compile-time only and is not exposed
to users or remote notification payloads.

## 4. Scheduled work

The existing `klect-nightly` job remains at **03:17 UTC**. Calling also owns two additive jobs:

- `klect-call-expiry` every 15 seconds → `public.expire_ringing_calls()`;
- `klect-call-signal-cleanup` every 15 minutes → `public.cleanup_call_signals()`.

Nightly maintenance continues to perform:

| step | why |
|---|---|
| refresh taste + matches for users seen in the last 7 days | keeps `get_matches` instant instead of computing on open |
| delete `call_signals` older than 1 day | WebRTC signalling is ephemeral and would grow unbounded |
| mark calls stuck in `ringing` > 2 min as `missed` | crashed clients otherwise leave calls ringing forever |
| delete read notifications older than 60 days | table hygiene |
| lift expired suspensions | `suspended_until` is only meaningful if something acts on it |

Inspect or change it:

```sql
select jobname, schedule, active from cron.job;
```

---

## 5. Before you go live

- [ ] Enable leaked-password protection (§1a)
- [x] Configure FCM + the webhook (§2) — **done 2026-07-30**, verified end to end
- [x] Real-device delivery confirmed on RMX3771 / Android 15 with `1.6.4+14` (§2)
- [ ] Store both Cloudflare TURN secrets, verify a short-lived credential response, and pass forced
      relay on two physical Android phones before globally enabling `reliable_calls`.
- [ ] Record foreground/background/swiped-away/locked, Wi-Fi/cellular, audio/video, decline/missed/
      cancel/busy, permission denial, Bluetooth and network-handoff evidence for both QA accounts.
- [ ] Set Auth → URL Configuration → Site URL and redirect allow-list to your real domains
- [ ] Remove the demo content: `delete from auth.users where email like '%@klect.test';`
- [ ] Re-run `get_advisors` for both `security` and `performance` and re-check the `unused_index`
      list against real traffic before dropping anything
- [ ] Rotate the publishable key if this repo was ever public
