// JARVIS — SOCIAL › RIVALI: il ritorno dal login di Facebook (8 nov 2026).
// Meta mostra gli altri account Instagram (Business Discovery) solo con una chiave di Facebook, non con quella di Instagram Login.
// Il giro: l'app chiede a «social» (azione "fbLink") l'indirizzo del login → il signore entra con Facebook una volta sola →
// Facebook torna QUI (GET ?code&state) → si controlla il codice monouso, si cambia il code in una chiave da 60 giorni, si trova
// l'account Instagram legato alla pagina, si salva tutto in social_facebook → si torna all'app (jarvis://rivali?ok=1).
// Pubblica senza JWT (ci arriva il browser del login): la protezione è il codice monouso «state», valido 10 minuti.
// Segreto: FACEBOOK_APP_SECRET (lo mette il signore in Supabase); l'ID dell'app JARVIS KR (1670395291165844) non è segreto. La chiave non esce mai da qui.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const URL_DB = Deno.env.get("SUPABASE_URL")!, KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const db = createClient(URL_DB, KEY, { auth: { persistSession: false } });
const FB = "https://graph.facebook.com/v23.0";
const env = (k: string) => Deno.env.get(k) ?? "";
const RITORNO = `${URL_DB}/functions/v1/social-facebook`;
const app = (q: Record<string, string>) => new Response(null, { status: 302, headers: { location: "jarvis://rivali?" + new URLSearchParams(q) } });
function uguali(a: string, b: string) {
  if (!a || a.length !== b.length) return false;
  let x = 0; for (let k = 0; k < a.length; k++) x |= a.charCodeAt(k) ^ b.charCodeAt(k);
  return x === 0;
}
async function fb(percorso: string, params: Record<string, string>) {
  const u = new URL(FB + percorso);
  for (const [k, v] of Object.entries(params)) u.searchParams.set(k, v);
  const r = await fetch(u);
  const d = await r.json().catch(() => ({}));
  if (!r.ok || d.error) throw new Error(d?.error?.message ?? `Facebook ${r.status}`);
  return d;
}

Deno.serve(async (req) => {
  if (req.method !== "GET") return new Response("no", { status: 405 });
  const q = new URL(req.url).searchParams;
  if (q.get("error")) return app({ errore: q.get("error_description") || "login annullato" });
  const code = q.get("code") ?? "", state = q.get("state") ?? "";
  const { data: riga } = await db.from("social_facebook").select("attesa,attesa_fino").eq("id", 1).maybeSingle();
  if (!riga?.attesa || !uguali(state, riga.attesa) || new Date(riga.attesa_fino ?? 0).getTime() < Date.now() || !code)
    return app({ errore: "il login è scaduto: ritocchi COLLEGA" });
  await db.from("social_facebook").update({ attesa: null, attesa_fino: null }).eq("id", 1);   // monouso
  const id = (env("FACEBOOK_APP_ID") || "1670395291165844"), seg = env("FACEBOOK_APP_SECRET");
  if (!id || !seg) return app({ errore: "mancano le chiavi dell'app Facebook nel cervello" });
  try {
    const corta = await fb("/oauth/access_token", { client_id: id, client_secret: seg, redirect_uri: RITORNO, code });
    const lunga = await fb("/oauth/access_token", { grant_type: "fb_exchange_token", client_id: id, client_secret: seg, fb_exchange_token: corta.access_token });
    const pagine = (await fb("/me/accounts", { fields: "name,instagram_business_account{id,username}", limit: "50", access_token: lunga.access_token })).data ?? [];
    const p = pagine.find((x: any) => x.instagram_business_account?.id);
    if (!p) return app({ errore: "nessuna pagina Facebook collegata a un account Instagram professionale" });
    const scade = new Date(Date.now() + (Number(lunga.expires_in) || 60 * 86400) * 1000).toISOString();
    await db.from("social_facebook").upsert({ id: 1, token: lunga.access_token, scade, ig_id: p.instagram_business_account.id, pagina: p.name, aggiornato: new Date().toISOString() });
    return app({ ok: "1", pagina: p.name });
  } catch (e) {
    return app({ errore: String(e instanceof Error ? e.message : e).slice(0, 160) });
  }
});
