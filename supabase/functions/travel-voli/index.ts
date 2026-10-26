// JARVIS — TRAVEL · VOLI (MARK X): lo stato del volo del signore («Jarvis, il volo AZ 2041 è in orario?»).
// POST, header x-jarvis-token (l'app) o x-chiave-interna (le prove dal database). Corpo: { volo: "AZ2041" }  →  { volo, compagnia, stato, partenza: {...}, arrivo: {...} }
// Segreti: JARVIS_TOKEN, AVIATIONSTACK_KEY (piano gratuito: 100 ricerche al mese, solo http: per questo passa da qui,
// la chiave resta nel cervello e l'iPhone non la vede mai). Le risposte si tengono 10 minuti per non sprecare ricerche.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { "content-type": "application/json" } });
const env = (k: string) => Deno.env.get(k) ?? "";
function uguali(a: string, b: string) {
  if (!a || a.length !== b.length) return false;
  let x = 0; for (let k = 0; k < a.length; k++) x |= a.charCodeAt(k) ^ b.charCodeAt(k);
  return x === 0;
}
const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
const tenuti = new Map<string, { quando: number; dati: unknown }>();

const oggiRoma = () => new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Rome" }).format(new Date());   // AAAA-MM-GG
const capo = (s: string) => s.toLowerCase().replace(/(^|[\s(\-/])(\p{L})/gu, (_, a, b) => a + b.toUpperCase());

function scalo(p: any) {
  return {
    aeroporto: capo(String(p?.airport ?? "")), iata: p?.iata ?? "", terminal: p?.terminal ?? null, gate: p?.gate ?? null,
    prevista: p?.scheduled ?? null, stimata: p?.estimated ?? null, effettiva: p?.actual ?? null, ritardo: p?.delay ?? null,
  };
}

Deno.serve(async (req) => {
  const segreto = env("JARVIS_TOKEN");
  let ammesso = !!segreto && uguali(req.headers.get("x-jarvis-token") ?? "", segreto);
  if (!ammesso) {
    const interna = req.headers.get("x-chiave-interna") ?? "";
    const { data } = interna ? await db.rpc("verifica_chiave_interna", { p: interna }) : { data: false };
    ammesso = data === true;
  }
  if (!ammesso) return json({ errore: "parola d'ordine errata" }, 401);
  const chiave = env("AVIATIONSTACK_KEY");
  if (!chiave) return json({ errore: "manca la chiave dei voli nel cervello" }, 500);
  const { volo } = await req.json().catch(() => ({ volo: "" }));
  const codice = String(volo ?? "").toUpperCase().replace(/[^A-Z0-9]/g, "").slice(0, 8);
  if (!/^[A-Z0-9]{2}\d{1,4}[A-Z]?$/.test(codice)) return json({ errore: "numero del volo non valido" }, 400);
  const t = tenuti.get(codice);
  if (t && Date.now() - t.quando < 10 * 60_000) return json(t.dati);
  const u = new URL("http://api.aviationstack.com/v1/flights");
  u.searchParams.set("access_key", chiave);
  u.searchParams.set("flight_iata", codice);
  try {
    const r = await fetch(u);
    const d = await r.json();
    if (d?.error) return json({ errore: "AviationStack: " + (d.error.message ?? d.error.code ?? r.status) }, 502);
    const lista: any[] = Array.isArray(d?.data) ? d.data : [];
    if (!lista.length) return json({ errore: "volo non trovato" }, 404);
    // il volo di oggi (ora di Roma); se non c'è, il più vicino nel tempo
    const oggi = oggiRoma();
    const ora = Date.now();
    const scelto = lista.find((f) => f?.flight_date === oggi)
      ?? lista.slice().sort((a, b) => Math.abs(Date.parse(a?.departure?.scheduled ?? 0) - ora) - Math.abs(Date.parse(b?.departure?.scheduled ?? 0) - ora))[0];
    const dati = {
      volo: scelto?.flight?.iata ?? codice, compagnia: scelto?.airline?.name ?? "", stato: scelto?.flight_status ?? "",
      data: scelto?.flight_date ?? "", partenza: scalo(scelto?.departure), arrivo: scalo(scelto?.arrival),
    };
    tenuti.set(codice, { quando: Date.now(), dati });
    return json(dati);
  } catch (e) { return json({ errore: "AviationStack non risponde: " + String(e) }, 502); }
});
