// JARVIS — STUDIO · CREA LIBERO (MARK X): il banco olografico chiede al cervello la ricetta dei pezzi per «qualsiasi cosa» descritta.
// POST, header x-jarvis-token. Corpo: { prompt: string }  →  { testo: string } (il JSON dei pezzi lo legge la pagina dello Studio)
// Segreti: JARVIS_TOKEN, ANTHROPIC_API_KEY. Facoltativo: MODELLO_STUDIO (predefinito Sonnet: buone proporzioni, costo basso).
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { "content-type": "application/json" } });
const env = (k: string) => Deno.env.get(k) ?? "";
function uguali(a: string, b: string) {
  if (!a || a.length !== b.length) return false;
  let x = 0; for (let k = 0; k < a.length; k++) x |= a.charCodeAt(k) ^ b.charCodeAt(k);
  return x === 0;
}

Deno.serve(async (req) => {
  const segreto = env("JARVIS_TOKEN");
  if (!segreto || !uguali(req.headers.get("x-jarvis-token") ?? "", segreto)) return json({ errore: "parola d'ordine errata" }, 401);
  const { prompt } = await req.json().catch(() => ({ prompt: "" }));
  const p = String(prompt ?? "").slice(0, 6000);
  if (!p) return json({ errore: "manca la descrizione" }, 400);
  try {
    const r = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "x-api-key": env("ANTHROPIC_API_KEY"), "anthropic-version": "2023-06-01", "content-type": "application/json" },
      body: JSON.stringify({ model: env("MODELLO_STUDIO") || "claude-sonnet-5-5", max_tokens: 2500, messages: [{ role: "user", content: p }] }),
    });
    const d = await r.json();
    if (!r.ok) return json({ errore: "cervello: " + (d?.error?.message ?? r.status) }, 502);
    const testo = (d.content ?? []).filter((c: any) => c.type === "text").map((c: any) => c.text).join("");
    return json({ testo });
  } catch (e) { return json({ errore: "il cervello non risponde: " + String(e) }, 502); }
});
