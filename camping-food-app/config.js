/* ----------------------------------------------------------------
 * Campfire Kitchen deployment config.
 *
 * With supabaseUrl/supabaseAnonKey left empty, the app runs in
 * DEVICE-ONLY DEMO mode: every browser keeps its own copy of the
 * data in localStorage. Fine for trying it out, but campers'
 * orders won't reach the chef's phone.
 *
 * To make it truly multi-user (LIVE SYNC), create a free Supabase
 * project, run supabase-setup.sql in its SQL editor, then paste
 * the project's URL and anon/public key below and redeploy.
 * Full steps are in README.md.
 * ---------------------------------------------------------------- */
window.CAMPFIRE_CONFIG = {
  // e.g. "https://abcdefghijk.supabase.co"
  supabaseUrl: "https://ocqtujgxftdbjuuhrlxl.supabase.co",

  // The "anon / public" API key from Supabase → Settings → API.
  // (It is safe-ish to publish for a demo, but anyone who finds it
  // can read/write the shared data — see README caveats.)
  supabaseAnonKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9jcXR1amd4ZnRkYmp1dWhybHhsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODM3MTE0ODcsImV4cCI6MjA5OTI4NzQ4N30.qMnB01ce2UjocD_00xf-_blEEb3M9PMU8h8eBMaydJY",

  // NOTE: with the v3 database setup, WHO IS A CHEF is decided
  // server-side by the campfire_chefs table (see supabase-setup.sql)
  // — the database rejects chef-only writes from anyone else. The
  // two settings below are only legacy fallbacks, used when the v3
  // SQL hasn't been applied (chefPhones) or in device-only demo
  // mode (chefPin).
  chefPin: "0711",
  chefPhones: ["+16175298470", "brylong@gmail.com"],
};
