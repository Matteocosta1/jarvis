// JARVIS — BROWSER · VIDEO (MARK X): cerca i video su YouTube per il visore olografico del Browser.
// POST, header x-jarvis-token. Corpo: { q: string }  →  { video: [{ id, titolo, canale, miniatura, quando }] }
// Segreti: JARVIS_TOKEN, YOUTUBE_API_KEY (YouTube Data API v3, progetto Google Cloud «JARVIS», gratis: 100 unità a ricerca, 10.000 al giorno).
// La chiave resta qui: l'app non la vede mai. Il video si guarda nel lettore ufficiale di YouTube (embed).
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { "content-type": "application/json" } });
const env = (k: string) => Deno.env.get(k) ?? "";
function uguali(a: string, b: string) {
  if (!a || a.length !== b.length) return false;
  let x = 0; for (let k = 0; k < a.length; k++) x |= a.charCodeAt(k) ^ b.charCodeAt(k);
  return x === 0;
}
const testo = (s: string) => s.replace(/&#39;/g, "'").replace(/&quot;/g, '"').replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">");

Deno.serve(async (req) => {
  const segreto = env("JARVIS_TOKEN");
  if (!segreto || !uguali(req.headers.get("x-jarvis-token") ?? "", segreto)) return json({ errore: "parola d'ordine errata" }, 401);
  const chiave = env("YOUTUBE_API_KEY");
  if (!chiave) return json({ errore: "manca la chiave di YouTube nel cervello" }, 500);
  const { q } = await req.json().catch(() => ({ q: "" }));
  const cerca = String(q ?? "").trim().slice(0, 200);
  if (!cerca) return json({ errore: "manca cosa cercare" }, 400);
  const u = new URL("https://www.googleapis.com/youtube/v3/search");
  for (const [k, v] of Object.entries({ part: "snippet", type: "video", maxResults: "12", q: cerca, relevanceLanguage: "it", safeSearch: "moderate", videoEmbeddable: "true", key: chiave })) u.searchParams.set(k, v);
  try {
    const r = await fetch(u);
    const d = await r.json();
    if (!r.ok) return json({ errore: "YouTube: " + (d?.error?.message ?? r.status) }, 502);
    const video = (d.items ?? []).filter((i: any) => i?.id?.videoId).map((i: any) => ({
      id: i.id.videoId, titolo: testo(i.snippet?.title ?? ""), canale: testo(i.snippet?.channelTitle ?? ""),
      miniatura: i.snippet?.thumbnails?.high?.url ?? i.snippet?.thumbnails?.medium?.url ?? "", quando: i.snippet?.publishedAt ?? "",
    }));
    return json({ video });
  } catch (e) { return json({ errore: "YouTube non risponde: " + String(e) }, 502); }
});
