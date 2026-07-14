# 🏕️ Campfire Kitchen

A summertime camping food-ordering and pickup app for a home chef, built as a
static web page — no build step, no dependencies.

## Run it locally

Open `index.html` in any browser. That's it.

Without a backend configured (see below), the app runs in **device-only demo
mode**: meals, orders, and notifications are stored in the browser's
`localStorage`, so they survive reloads but each device sees its own copy.
Use **↺ Reset demo data** at the bottom to restore the sample data. The pill
in the header always shows which mode you're in.

## Deploy to the web (GitHub Pages)

The repo has a GitHub Actions workflow
(`.github/workflows/deploy-camping-app.yml`) that publishes this directory to
GitHub Pages on every push that touches `camping-food-app/`. Once it has run,
the app is live at:

**https://devtator.github.io/SmartThingsPublic/**

Notes:
- If the workflow doesn't run, enable Actions for the repo (GitHub → Actions
  tab → enable) — workflows can start disabled on forks.
- If deployment is rejected with an environment-protection error, allow the
  deploying branch under Settings → Environments → `github-pages` →
  Deployment branches, or set Settings → Pages → Source to "GitHub Actions".

## Make it multi-user (live sync)

Out of the box the deployed page still uses device-only storage — fine for
showing the UI around, but a camper's order won't reach the chef's phone.
To test with real users, plug in a free [Supabase](https://supabase.com)
project as the shared store:

1. Create a Supabase account and a new project (free tier is plenty).
2. In the project's **SQL Editor**, paste and run
   [`supabase-setup.sql`](supabase-setup.sql). It creates one `campfire_state`
   table that holds the whole app state as JSON with a version counter.
3. In **Settings → API**, copy the *Project URL* and the *anon public* key.
4. Paste both into [`config.js`](config.js), optionally set a `chefPin`,
   commit, and push — the workflow redeploys automatically.

The header pill flips to **🟢 Live sync**: every phone now sees the same
menu, orders, and notifications. The app polls for changes every 4 seconds
and pushes writes with optimistic concurrency (conflicting writes are retried
against the latest state, so two campers ordering at once both get through).
Per-device things — which view you're in, your camper name — stay local.

## Camp sites

Each **camp site** is its own kitchen: its own menu, orders, and
notifications. The seeded breakfast data lives in the permanent
**Demo Campground** site, so there's always something to play with.

- **Camp sites are members-only.** The picker shows the camps you belong
  to: you're a member if you were invited (phone/email on the contact
  list), arrived via the site's invite link (auto-enrolled — the link is
  the ticket in), or are one of its chefs. Non-members can't open a site,
  and its data is unreadable to them at the database level. The **Demo
  Campground stays open to everyone**.
- **Each site can have multiple chefs.** Global chefs (the
  `campfire_chefs` table) see and run every site. Additionally, a site
  can name **site chefs** — set at creation ("Co-chefs") or later via
  **⚙️ Site settings** (which also edits the contact list); the creator
  is always implicitly a chef. Site chefs get full chef powers for their
  site only — menu, orders, day cycle, invites, notes — enforced
  server-side, and the Chef view automatically closes when they visit a
  site that isn't theirs. Only global chefs create new camp sites.
- **Chefs create camp sites**: name, emoji, and the cell numbers and/or
  emails of all campers (one per line). Creating the site opens the
  **invite panel**, which sends the welcome note by text or email.
- **Invites are text messages with a join link** (`…?site=N`). The invite
  panel offers two ways to send them, and can be reopened anytime via
  💬 Invites in the site bar. A camper who taps the link signs in with
  their number and lands directly in that camp site.
  - **🚀 Send to everyone automatically** — sends the welcome note
    server-side via the `send-invites` Edge Function: texts through Twilio
    and emails through Resend (credentials stay in Supabase secrets, never
    in this public page). Requires the one-time Edge Function setup below;
    only chefs may call it. Each channel works independently — missing
    secrets fail only that channel, with per-recipient results.
  - **Tap-to-send fallback** — per-camper (and "everyone") buttons that
    open the chef's own Messages or Mail app pre-filled; hit send. Works
    with zero setup, plus "Copy link".
- Device-only demo mode is single-site (camp sites need the shared
  backend).

### One-time setup for automatic invite texts (Edge Function)

1. In the Supabase dashboard: **Edge Functions → Deploy a new function**,
   name it exactly `send-invites`, paste the contents of
   [`supabase/functions/send-invites/index.ts`](supabase/functions/send-invites/index.ts),
   and deploy. (CLI users: `supabase functions deploy send-invites`.)
2. Under **Edge Functions → Secrets** add:
   - For invite **texts**: `TWILIO_ACCOUNT_SID` and `TWILIO_AUTH_TOKEN`
     (Twilio console), plus `TWILIO_FROM` (your Twilio number, `+1…`) — or
     `TWILIO_MESSAGING_SERVICE_SID` instead.
   - For invite **emails**, pick one provider:
     - **Your own SMTP server** (e.g. the same credentials you gave
       Supabase Auth's SMTP settings — note Supabase Auth's SMTP config is
       *not* shared with functions, so set them here too): `SMTP_HOST`,
       `SMTP_PORT` (465 for implicit TLS, 587 for STARTTLS), `SMTP_USER`,
       `SMTP_PASS`, and `SMTP_FROM` (e.g.
       `Campfire Kitchen <chef@yourdomain.com>`).
     - **or Resend**: `RESEND_API_KEY` (free at resend.com) and
       `RESEND_FROM` (e.g. `Campfire Kitchen <onboarding@resend.dev>`).
     SMTP is used when `SMTP_HOST` is set; otherwise Resend. These same
     secrets are shared with the `send-reminders` function.
3. Done — the 🚀 button in the invite panel now sends real texts. The
   function verifies the caller is a chef (via `campfire_is_chef`) before
   sending, caps each call at 25 numbers, and reports per-number results.
   Until it's deployed, the button explains itself and the tap-to-text
   fallback keeps working.

## Chef notes & automatic cutoff reminders

- **📣 Message campers** (chef view, Order window panel): the chef writes
  a note and picks the audience — **everyone**, **those who ordered**, or
  **those who haven't ordered** (computed from the current day's orders
  vs. the site's invited contacts). The note lands as an in-app
  notification and is also sent by **email — or by text for campers with
  no email on file** — through the `send-invites` Edge Function.
- **⏰ Automatic cutoff reminders**: the `send-reminders` Edge Function
  runs on a schedule and, when a camp site's cutoff is less than an hour
  away, reminds every invited contact who hasn't ordered tomorrow's
  breakfast yet (email first, text when there's no email). Each cutoff is
  reminded once. Setup:
  1. Deploy `supabase/functions/send-reminders/index.ts` as an Edge
     Function named exactly `send-reminders`, and turn OFF "Enforce JWT
     verification" in its settings.
  2. Add secrets: `CRON_SECRET` (any random string) and `SITE_URL`
     (`https://devtator.github.io/SmartThingsPublic/`), alongside the
     Twilio/Resend secrets above.
  3. Put the same secret into [`supabase-cron.sql`](supabase-cron.sql)
     and run it in the SQL Editor — it schedules a check every 10 minutes
     (pg_cron + pg_net).
  Timezone note: reminders use the timezone recorded from the chef's
  device when the cutoff was set or the day was wrapped, so run those
  from the phone you actually use at camp.

## Sign-in: texted code or emailed one-time link

In live-sync mode everyone — chef and campers — signs in with **either**
their cell number (texted verification code) or their email (one-time
magic link). Powered by Supabase Auth; no extra backend.

- **Phone path**: enter the number, get a 6-digit code by text, type it in.
- **Email path**: enter the address, get a one-time sign-in link by email —
  tap it and land back in the app, signed in. (The link should be opened
  on the device you want to use.)
- **One account, up to two identifiers**: a user needs only one of the
  two, and can link the other later via the **Account** panel (next to
  Sign out) — add an email (confirmation link) or add a phone (verification
  code). Orders and notifications match whichever identity was used.
- The **verified phone/email is the user's identity**: orders and
  notifications are keyed to it, so two campers named "Sam" can't collide
  or read each other's notifications. The name in the "Ordering as" bar is
  just the display name.
- **A sign-in is good for 7 days per device**: sessions persist across
  visits and refresh automatically in the background (a flaky connection
  won't log anyone out — refresh just retries later). A week after signing
  in, the app asks for a fresh code/link. There's also a **Sign out** link
  next to the (masked) identity.
- The database policies (see `supabase-setup.sql`) only allow signed-in
  users to read — the public anon key alone is no longer enough.

### Server-side chef checks (v3)

Who counts as a chef is decided **by the database**, not the page:

- Chefs are the phone numbers in the **`campfire_chefs`** table. Add one:
  `insert into public.campfire_chefs (phone) values ('+1XXXXXXXXXX');`
  (run in the SQL Editor; remove with a `delete`). The list itself is not
  readable by clients.
- **All writes go through validating database functions**
  (`campfire_write` / `campfire_seed`) — direct table writes are disabled.
  Campers can only add/change/cancel **their own** orders (matched to
  their verified phone); only chefs can change menus, confirm/serve
  orders, edit the camp-site directory, or create camp sites. A tampered
  client gets a polite refusal from the server.
- The Chef toggle in the UI asks the server (`campfire_is_chef`) — the
  `chefPhones`/`chefPin` values in `config.js` are only legacy fallbacks
  for a pre-v3 database or the offline demo.

### One-time Supabase setup for sign-in

1. Run (or re-run) `supabase-setup.sql` in the SQL Editor.
2. **Phone codes:** under **Authentication → Sign In / Providers**, enable
   the **Phone** provider. Supabase doesn't send SMS itself — connect a
   provider under the Phone settings (Twilio is the usual choice: create a
   free trial account at twilio.com, buy/claim a number, then paste the
   Account SID, Auth Token, and Messaging Service/From number into
   Supabase). **To try it before Twilio:** add a **Test OTP** — a phone
   number with a fixed code (e.g. `+15555550100` → `123456`) — and sign in
   with that; no SMS is sent.
3. **Email links:** the **Email** provider is enabled by default. Two
   things to check:
   - **Authentication → URL Configuration → Site URL** must be set to
     `https://devtator.github.io/SmartThingsPublic/` — the magic link
     redirects there. (Without it, links land on `localhost`.)
   - Supabase's built-in mailer is heavily rate-limited (a couple of
     emails per hour) and for dev only. For real campers, plug in custom
     SMTP under **Authentication → Emails / SMTP settings** (Resend,
     Postmark, Gmail app password, etc.).

Note: Supabase's shortest SMS code length is **6 digits** (configurable in
the Phone settings; 4 is below its minimum).

**Pilot-grade caveats, on purpose:**
- Any signed-in user can still *read* everything (all sites, all orders),
  and campers can freely edit their own orders' fields. Writes are
  validated server-side, but this is still a pilot, not a bank.
- SMS sign-in proves possession of a phone number — good enough to know
  you're dealing with real people, not strong security.
- Notifications appear when the app polls (in-app), they are not push
  notifications to a closed phone.
- In live sync the **Reset demo data** button only appears in the Chef view,
  so a camper can't wipe the shared state.

## How it works

The app has two roles, switchable with the toggle in the header:

### 👨‍🍳 Chef
- **Sets the meals** — name, description, category, price, and whether it's
  on the menu today.
- **Adds camper options in groups** — e.g. *Bread: Bagel, Wrap, Toast*
  (pick one) or *Add-ons: Cheese, Bacon, Hash browns* (pick any). Each
  group is a name, a pick-one/pick-any switch, and a comma-separated list
  of choices. Campers' selections show as chips on each incoming order.
- **Uploads a photo of the dish (optional)** — chosen in the meal editor;
  images are downscaled in the browser (max 640px wide JPEG) and stored
  locally, and show on the meal cards in both views.
- **Sets cook times** — the time slots they're willing to cook each meal
  (7:00 AM–9:30 AM in half-hour slots).
- **Reviews orders** — pending orders are grouped by meal, with a tally bar
  showing how many servings prefer each time slot.
- **Confirms one pickup time per meal** — picking a time and hitting
  *"Confirm time & notify campers"* locks it in and sends a notification to
  every camper who ordered that meal.
- **Marks meals served** — after handout, *"Mark served & request reviews"*
  notifies every camper who picked it up to rate the meal and send
  compliments.
- **Runs the day cycle** — orders are always placed **the day before the
  meal** (no same-day ordering). The *Order window* panel sets an
  **evening cutoff** (5 PM–midnight, chef's preference); ordering locks
  automatically once it passes, with manual *Close now / Reopen*
  overrides. After serving breakfast, **🌅 Wrap up breakfast & open
  tomorrow** archives the day's orders into **📜 Past mornings** — a
  browsable history with servings and revenue per day — reopens ordering
  for the next morning, and notifies campers to get their orders in.
  Ratings survive archiving, so meal stars keep accumulating across days.
  Day-cycle settings are chef-only, enforced server-side.
- **Collects kudos** — camper ratings and compliments land on the
  💛 *Compliments & ratings* board, and each meal shows its average rating.

### 🎒 Camper
- **Browses the menu** of available meals with photos, prices, ratings, and
  offered time slots.
- **Places an order** — chooses a preferred pickup time from the chef's
  offered slots, configures the meal with simple tap-able choices
  (pick-one groups preselect their first choice; pick-any groups work
  like checkboxes), plus a quantity and optional notes.
- **Gets notified** — the 🔔 bell shows when the chef confirms the actual
  pickup time. Orders show *Awaiting chef* until then, and the confirmed
  pickup time after.
- **Orders the day before** — the menu is always *tomorrow's* breakfast.
  Once the evening cutoff passes (or the chef closes ordering), the menu
  shows a "🌙 Ordering for tomorrow's breakfast is closed" banner and the
  Order buttons disappear until the chef wraps up the next morning's
  service.
- **Rates & thanks the chef** — after the chef marks a meal served, the
  camper gets a notification and a ⭐ *Rate & thank the chef* button on the
  order: a 1–5 star rating plus optional compliments, delivered straight to
  the chef's notifications and kudos board.

Change the name in the "Ordering as" bar to act as a different camper.

## Sample data

The seed data is breakfast-focused (the predominant use case):

| Meal | Category | Price |
|---|---|---|
| Eggs & Bacon Breakfast Sandwich | Sandwich | $8.00 |
| Sausage, Egg & Cheese Croissant | Sandwich | $8.50 |
| Smoked Ham & Egg Bagel | Sandwich | $8.00 |
| Campfire Breakfast Bowl | Bowl | $9.50 |
| Veggie Sunrise Bowl | Bowl | $9.00 |
| Pancake Stack & Bacon Plate | Plate | $9.00 (off-menu, to demo availability) |

It also seeds several pending camper orders (Riley, Sam, Dana, Alex, Jordan)
with different preferred times, so the chef's review-and-confirm flow is
demonstrable immediately. To demo the feedback loop it includes one served
order awaiting a rating (Morgan — switch the camper name to Morgan to try
the ⭐ rate flow) and one completed 5-star review with a compliment (Dana's
pancakes), already visible on the chef's kudos board.

The same data set is available as machine-readable JSON in
[`sample-data.json`](sample-data.json) for when this grows a real backend.

## Files

- `index.html` — the entire app (markup, styles, and logic)
- `config.js` — deployment settings: Supabase URL/key for live sync, chef PIN
- `supabase-setup.sql` — one-time table setup for the live-sync backend
- `sample-data.json` — the sample breakfast data set as standalone JSON
- `../.github/workflows/deploy-camping-app.yml` — auto-deploy to GitHub Pages
