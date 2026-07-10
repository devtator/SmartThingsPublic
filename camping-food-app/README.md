# 🏕️ Campfire Kitchen

A summertime camping food-ordering and pickup app for a home chef, built as a
single self-contained web page — no build step, no server, no dependencies.

## Run it

Open `index.html` in any browser. That's it.

State (meals, orders, notifications) is stored in the browser's
`localStorage`, so it survives reloads. Use **↺ Reset demo data** at the
bottom of either view to restore the sample data.

## How it works

The app has two roles, switchable with the toggle in the header:

### 👨‍🍳 Chef
- **Sets the meals** — name, description, category, price, and whether it's
  on the menu today.
- **Sets cook times** — the time slots they're willing to cook each meal
  (7:00 AM–9:30 AM in half-hour slots).
- **Reviews orders** — pending orders are grouped by meal, with a tally bar
  showing how many servings prefer each time slot.
- **Confirms one pickup time per meal** — picking a time and hitting
  *"Confirm time & notify campers"* locks it in and sends a notification to
  every camper who ordered that meal.

### 🎒 Camper
- **Browses the menu** of available meals with prices and offered time slots.
- **Places an order** — chooses a preferred pickup time from the chef's
  offered slots, a quantity, and optional notes (e.g. "no cheese").
- **Gets notified** — the 🔔 bell shows when the chef confirms the actual
  pickup time. Orders show *Awaiting chef* until then, and the confirmed
  pickup time after.

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
demonstrable immediately, plus one already-confirmed order (Morgan) to show
the notification flow.

The same data set is available as machine-readable JSON in
[`sample-data.json`](sample-data.json) for when this grows a real backend.

## Files

- `index.html` — the entire app (markup, styles, and logic)
- `sample-data.json` — the sample breakfast data set as standalone JSON
