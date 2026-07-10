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

**Pilot-grade caveats, on purpose:**
- The anon key in `config.js` is public. Anyone who finds the URL can read
  and write the shared data. Fine for a campground pilot; not for real money.
- The `chefPin` is a courtesy gate to keep campers out of the Chef view, not
  real security.
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
