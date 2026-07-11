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

- The bar at the top shows the current camp site; **⛺ Switch camp site**
  lists every site, and anyone can open any of them (no per-site access
  limits yet — by design for now).
- **Chefs create camp sites**: name, emoji, and the cell numbers of all
  campers (one per line). Creating the site opens the **invite panel**.
- **Invites are text messages with a join link** (`…?site=N`). Each button
  in the invite panel opens the chef's own Messages app pre-filled with the
  camper's number and the invite text — hit send and it's on its way. There
  are also "Text everyone" and "Copy link" options, and the panel can be
  reopened anytime via 💬 Invites in the site bar. A camper who taps the
  link signs in with their number and lands directly in that camp site.
- Invites come from the chef's own phone on purpose: sending them
  server-side would require exposing SMS credentials from a static site.
  If automatic sending becomes worth it, the upgrade path is a small
  Supabase Edge Function holding the Twilio secrets.
- Device-only demo mode is single-site (camp sites need the shared
  backend).

## Phone sign-in (texted verification codes)

In live-sync mode everyone — chef and campers — signs in with their cell
number: enter the number, receive a texted verification code, type it in.
Powered by Supabase Auth SMS OTP; no extra backend.

- The **verified phone number is the user's identity**: orders and
  notifications are keyed to it, so two campers named "Sam" can't collide
  or read each other's notifications. The name in the "Ordering as" bar is
  just the display name.
- Sessions persist on the device and refresh automatically; there's a
  **Sign out** link next to the (masked) phone number.
- The database policies (see `supabase-setup.sql`) only allow signed-in
  users to read/write — the public anon key alone is no longer enough.
- **`chefPhones`** in `config.js`: list the chef's number(s) there and only
  those signed-in phones can open the Chef view (no PIN prompt needed).
  If the list is empty, the `chefPin` gate applies instead.

### One-time Supabase setup for SMS sign-in

1. Run (or re-run) `supabase-setup.sql` in the SQL Editor — it now grants
   access to signed-in users only.
2. In the dashboard under **Authentication → Sign In / Providers**, enable
   the **Phone** provider.
3. Supabase doesn't send SMS itself — connect a provider under the Phone
   settings (Twilio is the usual choice: create a free trial account at
   twilio.com, buy/claim a number, then paste the Account SID, Auth Token,
   and Messaging Service/From number into Supabase).
4. **To try it before setting up Twilio:** in the Phone provider settings,
   add a **Test OTP** — a phone number with a fixed code (e.g.
   `+15555550100` → `123456`). Signing in with that number then works
   without any SMS being sent.

Note: Supabase's shortest code length is **6 digits** (configurable in the
Phone settings; 4 is below its minimum).

**Pilot-grade caveats, on purpose:**
- Reads/writes now require a phone-verified sign-in, but any verified user
  can see all orders and (by design of the single shared row) technically
  write anything. Fine for a campground pilot; not for real money.
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
- **Collects kudos** — camper ratings and compliments land on the
  💛 *Compliments & ratings* board, and each meal shows its average rating.

### 🎒 Camper
- **Browses the menu** of available meals with photos, prices, ratings, and
  offered time slots.
- **Places an order** — chooses a preferred pickup time from the chef's
  offered slots, a quantity, and optional notes (e.g. "no cheese").
- **Gets notified** — the 🔔 bell shows when the chef confirms the actual
  pickup time. Orders show *Awaiting chef* until then, and the confirmed
  pickup time after.
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
