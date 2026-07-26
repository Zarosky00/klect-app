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

The delivery path is built and deployed. It is **inert until you add two secrets** — by design, so it
returns 200 and the webhook never retries in a loop.

**Edge function:** `push-fanout` (deployed, `verify_jwt = false`)
Handles FCM v1 for both Android and iOS, composes per-type copy, respects muted conversations,
emits a `klect://` deep link, and prunes tokens FCM reports as permanently dead.

### Wire it up

1. **Create the secrets** (dashboard → Edge Functions → Secrets, or CLI):

   ```bash
   npx supabase secrets set PUSH_WEBHOOK_SECRET="$(openssl rand -hex 32)" --project-ref dikhuygcwxnrsckqglzg
   ```

   ```bash
   npx supabase secrets set FCM_SERVICE_ACCOUNT="$(cat firebase-service-account.json | tr -d '\n')" --project-ref dikhuygcwxnrsckqglzg
   ```

2. **Create the Database Webhook** — dashboard → Database → Webhooks → *Create*:
   - table `public.notifications`, event **Insert**
   - type **HTTP Request**, method `POST`
   - URL `https://dikhuygcwxnrsckqglzg.supabase.co/functions/v1/push-fanout`
   - header `x-klect-secret: <the PUSH_WEBHOOK_SECRET value>`

3. **Client side** — on sign-in, register the FCM token into `push_tokens`
   (`{user_id, token, platform}`); on sign-out, delete it.

Verify it is reachable (should be `401` before the secret header is set):

```bash
curl -s -o /dev/null -w "%{http_code}\n" -X POST https://dikhuygcwxnrsckqglzg.supabase.co/functions/v1/push-fanout -d '{}'
```

### Notification channels the client must create
`calls` (high priority, ringtone) and `social` (normal). The function already targets them.

---

## 3. Scheduled work

One `pg_cron` job, `klect-nightly`, at **03:17 UTC** → `public.nightly_maintenance()`:

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

## 4. Before you go live

- [ ] Enable leaked-password protection (§1a)
- [ ] Configure FCM + the webhook (§2), or accept that push is silent
- [ ] Add a **TURN server** — WebRTC calls will fail across most mobile NATs with STUN alone.
      The ICE config location is marked in the mobile call service.
- [ ] Set Auth → URL Configuration → Site URL and redirect allow-list to your real domains
- [ ] Remove the demo content: `delete from auth.users where email like '%@klect.test';`
- [ ] Re-run `get_advisors` for both `security` and `performance` and re-check the `unused_index`
      list against real traffic before dropping anything
- [ ] Rotate the publishable key if this repo was ever public
