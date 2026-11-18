// JARVIS — IL FILO TRA I DISPOSITIVI (18 nov, 13.1 (2); scelta del signore: «Supabase»). Si comincia sul Mac e si finisce sul
// telefono, con lo stesso filo: ogni dispositivo lascia qui le ultime battute e quello che aspetta il sì; l'altro, riaprendo
// JARVIS, le legge e riprende il discorso.
// POST, header x-jarvis-token (l'app) o x-chiave-interna (le prove dal database).
//   { dispositivo: "iphone"|"mac", salva: { battute: [...], attesa: {...}|null, piano: {...}|null, domanda: "..." } } → { ok }
//   { dispositivo: "iphone"|"mac", leggi: true } → { altro: { dispositivo, stato, aggiornato } | null }  (l'altro dispositivo, ultime 12 ore)
// Tabella jarvis_filo_app (RLS senza regole: solo il service role). Il cervello non cambia.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { "content-type": "application/json" } });
function uguali(a: string, b: string) {
  if (!a || a.length !== b.length) return false;
  let x = 0; for (let k = 0; k < a.length; k++) x |= a.charCodeAt(k) ^ b.charCodeAt(k);
  return x === 0;
}
const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
const VALE_MS = 12 * 3600_000;
const MASSIMO = 64_000;   // un filo è testo: oltre, qualcosa non va

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ errore: "solo POST" }, 405);
  const segreto = Deno.env.get("JARVIS_TOKEN") ?? "";
  let ammesso = !!segreto && uguali(req.headers.get("x-jarvis-token") ?? "", segreto);
  if (!ammesso) {
    const interna = req.headers.get("x-chiave-interna") ?? "";
    const { data } = interna ? await db.rpc("verifica_chiave_interna", { p: interna }) : { data: false };
    ammesso = data === true;
  }
  if (!ammesso) return json({ errore: "parola d'ordine errata" }, 401);
  const corpo = await req.json().catch(() => null);
  const dispositivo = corpo?.dispositivo === "mac" ? "mac" : corpo?.dispositivo === "iphone" ? "iphone" : "";
  if (!dispositivo) return json({ errore: "dispositivo non valido" }, 400);

  if (corpo?.salva && typeof corpo.salva === "object" && !Array.isArray(corpo.salva)) {
    if (JSON.stringify(corpo.salva).length > MASSIMO) return json({ errore: "filo troppo lungo" }, 413);
    const { error } = await db.from("jarvis_filo_app").upsert({ dispositivo, stato: corpo.salva, aggiornato: new Date().toISOString() });
    if (error) return json({ errore: error.message }, 500);
    return json({ ok: true });
  }
  if (corpo?.leggi === true) {
    const da = new Date(Date.now() - VALE_MS).toISOString();
    const { data, error } = await db.from("jarvis_filo_app").select("dispositivo, stato, aggiornato")
      .neq("dispositivo", dispositivo).gte("aggiornato", da).order("aggiornato", { ascending: false }).limit(1).maybeSingle();
    if (error) return json({ errore: error.message }, 500);
    return json({ altro: data ?? null });
  }
  return json({ errore: "richiesta non valida" }, 400);
});
