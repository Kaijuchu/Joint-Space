# Joint Space — Setup (GitHub Pages + Supabase + Gemini)

This is `Joint Space.html`, a single-file app, plus a Supabase Edge Function that powers Spacey (the AI). Auth uses Supabase (Google + email/password). The Gemini key lives **server-side** in the edge function and is never exposed to the browser.

Files:
- `Joint Space.html` — the app (host this).
- `supabase/functions/gemini/index.ts` — the Spacey → Gemini proxy.

You'll do four things: create a Supabase project, deploy the edge function, host the HTML, then wire the two together.

---

## 1. Create a Supabase project

1. Go to supabase.com → **New project**. Pick a name and password; wait for it to provision.
2. In the dashboard, open **Project Settings → API** and copy two values:
   - **Project URL** (looks like `https://abcdxyz.supabase.co`)
   - **anon public** key (a long JWT — this one is safe to ship in the browser)

## 2. Paste those into the app

Open `Joint Space.html`, find this near the top, and fill it in:

```js
window.JOINT_CONFIG = {
  SUPABASE_URL: "https://abcdxyz.supabase.co",
  SUPABASE_ANON_KEY: "eyJ...your-anon-key..."
};
```

> If you leave these blank, the app still runs as a demo (local sign-in, and Spacey replies with a "not connected" note). Real accounts + AI only turn on once these are set.

## 3. Deploy the Gemini edge function

Install the Supabase CLI (once): https://supabase.com/docs/guides/cli

```bash
supabase login
supabase link --project-ref <your-project-ref>     # the abcdxyz part of your URL

# set the Gemini key as a server-side secret (get a key at aistudio.google.com/apikey)
supabase secrets set GEMINI_API_KEY=your_gemini_key
# optional — pick a model (default is gemini-2.5-flash)
supabase secrets set GEMINI_MODEL=gemini-2.5-flash

# deploy the function in supabase/functions/gemini/
supabase functions deploy gemini
```

That's it for Spacey — the app calls this function by name (`gemini`).

## 4. Enable Google sign-in

1. Supabase dashboard → **Authentication → Providers → Google** → enable it. It shows a **Callback URL** like `https://abcdxyz.supabase.co/auth/v1/callback`.
2. In **Google Cloud Console** → APIs & Services → Credentials → **Create OAuth client ID** (Web application):
   - **Authorized redirect URI**: paste the Supabase callback URL from step 1.
   - Copy the **Client ID** and **Client secret** back into Supabase's Google provider settings and save.
3. Supabase dashboard → **Authentication → URL Configuration**:
   - **Site URL**: your hosted page URL (from step 5, e.g. `https://<you>.github.io/joint-space/`)
   - **Redirect URLs**: add that same URL.

> Email/password signups work without any of step 4. Google login needs it because OAuth requires a registered https origin — it will **not** work from a double-clicked local file.

## 5. Host on GitHub Pages

1. Create a repo (e.g. `joint-space`) and add `Joint Space.html`. Renaming it to `index.html` makes the URL cleaner.
2. Repo **Settings → Pages** → Source: `Deploy from a branch` → `main` / root.
3. Your site goes live at `https://<you>.github.io/joint-space/`.
4. Put that exact URL into Supabase **Site URL** and **Redirect URLs** (step 4.3).

---

## How it's wired (for reference)

- **Spacey AI** — the app calls `window.claude.complete(prompt)`; a small shim forwards it to the `gemini` edge function, which calls Gemini and returns the text. Image prompts (Sketch Guess auto-guess) are passed through as `inlineData`.
- **Auth** — `authenticate()` uses `supabase.auth.signInWithPassword` / `signUp`; the Google button uses `supabase.auth.signInWithOAuth`; sign-out and session restore are wired to Supabase. On OAuth return, the app picks up the session automatically and drops you into the space picker.

## Notes / gotchas

- **New Google model names change often.** If Spacey errors with an "unknown model" message, set `GEMINI_MODEL` to a current one (e.g. `gemini-2.5-flash`, `gemini-2.5-pro`).
- **Email confirmation** is on by default in Supabase. A new signup won't be logged in until the emailed link is clicked. Turn it off under Authentication → Providers → Email if you want instant signup for testing.
- **Local testing:** open with a local server (e.g. `python -m http.server`) rather than `file://` so OAuth redirects resolve, and add `http://localhost:8000` to Supabase Redirect URLs.
- The **anon key is meant to be public**; the **Gemini key is not** and only lives in the edge function secret.
