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
  supabaseUrl: "",

  // The "anon / public" API key from Supabase → Settings → API.
  // (It is safe-ish to publish for a demo, but anyone who finds it
  // can read/write the shared data — see README caveats.)
  supabaseAnonKey: "",

  // Optional: require this PIN to open the Chef view, so campers
  // can't wander into the kitchen controls. Empty = no PIN.
  chefPin: "",
};
