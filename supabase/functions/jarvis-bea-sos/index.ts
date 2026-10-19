// JARVIS — il «Tocco d'aiuto» di Bea. Sul suo iPhone un Comando rapido (triplo tocco sul retro) chiama qui con la sua posizione:
// a tutti gli iPhone di JARVIS (e quindi all'Apple Watch) arriva subito una notifica «Bea ha bisogno di lei», con Chiama e Portami da lei.
// POST, header x-bea-chiave = segreto BEA_SOS_CHIAVE (una chiave sola per questo: non apre nient'altro di JARVIS).
// Corpo (JSON): { lat?: number, lon?: number, prova?: boolean }
// Segreti: BEA_SOS_CHIAVE, JARVIS_BUNDLE_ID, APNS_KEY_P8, APNS_KEY_ID, APNS_TEAM_ID.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { SignJWT, importPKCS8 } from "npm:jose@5";

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { "content-type": "application/json" } });

function uguali(a: string, b: string) {
  if (!a || a.length !== b.length) return false;
  let x = 0; for (let k = 0; k < a.length; k++) x |= a.charCodeAt(k) ^ b.charCodeAt(k);
  return x === 0;
}

let cacheJwt: { token: string; creato: number } | null = null;
async function jwtApple() {
  const p8 = Deno.env.get("APNS_KEY_P8"), keyId = Deno.env.get("APNS_KEY_ID"), teamId = Deno.env.get("APNS_TEAM_ID");
  if (!p8 || !keyId || !teamId) return null;
  if (cacheJwt && Date.now() - cacheJwt.creato < 40 * 60_000) return cacheJwt.token;
  const chiave = await importPKCS8(p8.replace(/\\n/g, "\n").trim(), "ES256");
  const token = await new SignJWT({}).setProtectedHeader({ alg: "ES256", kid: keyId }).setIssuer(teamId).setIssuedAt().sign(chiave);
  cacheJwt = { token, creato: Date.now() };
  return token;
}

async function push(host: string, jwt: string, token: string, corpo: Record<string, unknown>) {
  const r = await fetch(`${host}/3/device/${token}`, {
    method: "POST",
    headers: { authorization: `bearer ${jwt}`, "apns-topic": Deno.env.get("JARVIS_BUNDLE_ID") ?? "", "apns-push-type": "alert", "apns-priority": "10", "content-type": "application/json" },
    body: JSON.stringify(corpo),
  });
  let motivo = "";
  if (!r.ok) { try { motivo = (await r.json()).reason ?? ""; } catch { /* vuoto */ } }
  return { ok: r.ok, stato: r.status, motivo };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ errore: "metodo non ammesso" }, 405);
  const segreto = Deno.env.get("BEA_SOS_CHIAVE") ?? "";
  if (!segreto || !uguali(req.headers.get("x-bea-chiave") ?? "", segreto)) return json({ errore: "non autorizzato" }, 401);

  let grezzo: any = {};
  try { grezzo = await req.json(); } catch { /* corpo vuoto: l'aiuto parte lo stesso, senza posizione */ }
  // il Comando rapido lo scrive una persona dal telefono: la tastiera mette maiuscole, spazi, «Ion» al posto di «lon».
  // Le chiavi si leggono senza badare a maiuscole e spazi.
  const c: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(grezzo ?? {})) {
    let chiave = k.trim().toLowerCase().replace(/\s+/g, "");
    if (chiave === "ion" || chiave === "long" || chiave === "lng" || chiave.startsWith("longit")) chiave = "lon";
    if (chiave.startsWith("latit")) chiave = "lat";
    c[chiave] = v;
  }
  const numero = (x: unknown) => { const v = Number(String(x ?? "").replace(",", ".")); return Number.isFinite(v) && v !== 0 ? v : null; };
  let lat = numero(c.lat), lon = numero(c.lon);
  if (lat === null || lon === null || Math.abs(lat) > 90 || Math.abs(lon) > 180) { lat = null; lon = null; }   // coordinate impossibili: si va senza posizione
  const prova = c.prova === true || c.prova === 1 || /^(true|vero|s[iì]|1)$/i.test(String(c.prova ?? "").trim());

  // freno contro la raffica: un allarme vero al minuto (il primo è già partito), al massimo 5 prove all'ora
  const finestra = new Date(Date.now() - (prova ? 3600_000 : 60_000)).toISOString();
  const { count: recenti } = await db.from("jarvis_bea_sos").select("id", { count: "exact", head: true }).eq("prova", prova).gt("inviate", 0).gte("creato", finestra);   // conta solo gli avvisi arrivati davvero: se il primo è fallito, il secondo passa
  if ((recenti ?? 0) >= (prova ? 5 : 1)) return json({ ok: true, gia_inviato: true });

  const titolo = prova ? "Prova · Bea ha bisogno di lei" : "Bea ha bisogno di lei";
  const testo = prova
    ? "È solo una prova del Tocco d'aiuto: funziona."
    : `Bea ha chiesto aiuto adesso${lat && lon ? ": tocchi per vedere dov'è e chiamarla." : ". Non è arrivata la posizione: la chiami subito."}`;

  const jwt = await jwtApple();
  if (!jwt || !Deno.env.get("JARVIS_BUNDLE_ID")) return json({ errore: "notifiche Apple non configurate" }, 500);
  const { data } = await db.from("jarvis_dispositivi").select("token");
  const tokens = (data ?? []).map((d: any) => String(d.token));
  // la riga c'è prima della notifica: l'app, aprendo l'avviso, la segna come vista
  const { data: riga } = await db.from("jarvis_bea_sos").insert({ lat, lon, prova, inviate: 0 }).select("id").single();
  const sosId = riga?.id ?? 0;
  const payload = {
    aps: { alert: { title: titolo, body: testo }, sound: "default", "interruption-level": "time-sensitive", "relevance-score": 1 },
    jarvis_azione: "bea_sos", jarvis_testo: testo, ...(lat && lon ? { lat, lon } : {}), prova, sos_id: sosId,
  };
  let inviate = 0;
  for (const t of tokens) {
    let e = await push("https://api.push.apple.com", jwt, t, payload);
    if (!e.ok && e.motivo === "BadDeviceToken") e = await push("https://api.sandbox.push.apple.com", jwt, t, payload);   // build da Xcode
    if (e.ok) inviate++;
  }
  if (sosId) await db.from("jarvis_bea_sos").update({ inviate }).eq("id", sosId);
  return json({ ok: inviate > 0, inviate });
});
