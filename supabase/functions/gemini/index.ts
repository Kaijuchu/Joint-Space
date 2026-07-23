// Supabase Edge Function: "gemini"
// Spacey (the in-app AI) calls this. The Gemini API key stays server-side here —
// it is NEVER shipped to the browser.
//
// Deploy:   supabase functions deploy gemini
// Secret:   supabase secrets set GEMINI_API_KEY=your_key_here
// Optional: supabase secrets set GEMINI_MODEL=gemini-2.5-flash
//
// Request body (sent by the app):  { prompt: string, images?: [{ mime, data }] }
// Response body:                    { text: string }   or   { error: string }

const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY") ?? "";
const GEMINI_MODEL = Deno.env.get("GEMINI_MODEL") ?? "gemini-2.5-flash";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "content-type": "application/json" },
  });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  if (!GEMINI_API_KEY) return json({ error: "GEMINI_API_KEY not set" }, 500);

  try {
    const { prompt, images } = await req.json().catch(() => ({}));

    const parts: Array<Record<string, unknown>> = [];
    if (prompt) parts.push({ text: String(prompt) });
    if (Array.isArray(images)) {
      for (const im of images) {
        if (im && im.data) {
          parts.push({
            inlineData: { mimeType: im.mime || "image/png", data: im.data },
          });
        }
      }
    }
    if (parts.length === 0) return json({ error: "empty prompt" }, 400);

    const url =
      `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}`;

    const r = await fetch(url, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ contents: [{ role: "user", parts }] }),
    });

    const data = await r.json();
    if (!r.ok) {
      return json({ error: data?.error?.message || "Gemini request failed" }, 502);
    }

    const text: string =
      (data?.candidates?.[0]?.content?.parts ?? [])
        .map((p: { text?: string }) => p.text || "")
        .join("") || "";

    return json({ text });
  } catch (e) {
    return json({ error: (e as Error)?.message || String(e) }, 500);
  }
});
