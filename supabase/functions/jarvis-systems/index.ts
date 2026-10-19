// JARVIS — Systems Check. Ogni ora (pg_cron) controlla che i sistemi di JARVIS siano vivi.
// Notifica al signore SOLO quando qualcosa non va (e quando torna a posto); alle 21 un riepilogo della giornata.
// Non usa l'intelligenza artificiale: costo zero. Chiamata da pg_cron con x-chiave-interna, o a mano con x-jarvis-token.
// Corpo facoltativo: { riepilogo: true } forza il riepilogo serale; { prova: true } manda comunque una notifica di prova.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { SignJWT, importPKCS8 } from "npm:jose@5";

const URL_BASE = Deno.env.get("SUPABASE_URL")!;
const db = createClient(URL_BASE, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { "content-type": "application/json" } });

function uguali(a: string, b: string) {
  if (!a || a.length !== b.length) return false;
  let x = 0; for (let k = 0; k < a.length; k++) x |= a.charCodeAt(k) ^ b.charCodeAt(k);
  return x === 0;
}

// ───────── I controlli ─────────
type Esito = { nome: string; ok: boolean; dettaglio?: string };

/// Una funzione è viva se risponde «non autorizzato» a chi bussa senza chiave (401): vuol dire che è accesa e si difende.
async function bussa(nome: string, slug: string, metodo = "POST"): Promise<Esito> {
  try {
    const r = await fetch(`${URL_BASE}/functions/v1/${slug}`, {
      method: metodo, signal: AbortSignal.timeout(20_000),
      ...(metodo === "POST" ? { headers: { "content-type": "application/json" }, body: "{}" } : {}),
    });
    const corpo = await r.text().catch(() => "");
    // 401 con il nostro messaggio d'errore: la funzione è accesa e si difende (non il cancello di Supabase davanti)
    return r.status === 401 && /"errore"/.test(corpo) ? { nome, ok: true } : { nome, ok: false, dettaglio: `risponde ${r.status}` };
  } catch (e) {
    return { nome, ok: false, dettaglio: `non risponde (${(e as Error).message.slice(0, 80)})` };
  }
}

/// Il cervello con la sua chiave: legge la scheda di Bea dal database. Prova chiave, cervello e database insieme, senza spendere.
async function cervelloVero(): Promise<Esito> {
  const nome = "Cervello (database)";
  try {
    const r = await fetch(`${URL_BASE}/functions/v1/jarvis`, {
      method: "POST", signal: AbortSignal.timeout(25_000),
      headers: { "content-type": "application/json", "x-jarvis-token": Deno.env.get("JARVIS_TOKEN") ?? "" },
      body: JSON.stringify({ bea: true }),
    });
    const d = await r.json().catch(() => null);
    return r.ok && d && !d.errore ? { nome, ok: true } : { nome, ok: false, dettaglio: `risponde ${r.status}${d?.errore ? `: ${String(d.errore).slice(0, 80)}` : ""}` };
  } catch (e) {
    return { nome, ok: false, dettaglio: `non risponde (${(e as Error).message.slice(0, 80)})` };
  }
}

async function controlla(): Promise<Esito[]> {
  return await Promise.all([
    bussa("Cervello", "jarvis"),
    cervelloVero(),
    bussa("Tocco d'aiuto di Bea", "jarvis-bea-sos"),
    bussa("Allarme battito", "jarvis-allarme"),
    bussa("Briefing del mattino", "jarvis-briefing"),
    bussa("Ascolto", "jarvis-ascolto"),
  ]);
}

// ───────── Notifiche (stesse chiavi Apple del resto di JARVIS) ─────────
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
async function push(host: string, jwt: string, token: string, corpo: unknown) {
  const r = await fetch(`${host}/3/device/${token}`, {
    method: "POST",
    headers: { authorization: `bearer ${jwt}`, "apns-topic": Deno.env.get("JARVIS_BUNDLE_ID") ?? "", "apns-push-type": "alert", "apns-priority": "10", "content-type": "application/json" },
    body: JSON.stringify(corpo),
  });
  let motivo = "";
  if (!r.ok) { try { motivo = (await r.json()).reason ?? ""; } catch { /* vuoto */ } }
  return { ok: r.ok, motivo };
}
async function avvisa(titolo: string, testo: string, urgente: boolean) {
  const jwt = await jwtApple();
  if (!jwt || !Deno.env.get("JARVIS_BUNDLE_ID")) return 0;
  const { data } = await db.from("jarvis_dispositivi").select("token");
  const corpo = { aps: { alert: { title: titolo, body: testo }, sound: "default", "interruption-level": urgente ? "time-sensitive" : "active" }, jarvis_testo: testo };
  let inviate = 0;
  for (const t of (data ?? []).map((d: any) => String(d.token))) {
    let e = await push("https://api.push.apple.com", jwt, t, corpo);
    if (!e.ok && e.motivo === "BadDeviceToken") e = await push("https://api.sandbox.push.apple.com", jwt, t, corpo);
    if (e.ok) inviate++;
  }
  return inviate;
}

const oraRoma = () => Number(new Intl.DateTimeFormat("it-IT", { timeZone: "Europe/Rome", hour: "2-digit", hour12: false }).format(new Date()));
const giornoRoma = (d = new Date()) => new Intl.DateTimeFormat("sv-SE", { timeZone: "Europe/Rome" }).format(d);   // AAAA-MM-GG

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ errore: "metodo non ammesso" }, 405);
  const segreto = Deno.env.get("JARVIS_TOKEN") ?? "";
  let ammesso = !!segreto && uguali(req.headers.get("x-jarvis-token") ?? "", segreto);
  if (!ammesso) {
    const interna = req.headers.get("x-chiave-interna") ?? "";
    const { data } = interna ? await db.rpc("verifica_chiave_interna", { p: interna }) : { data: false };
    ammesso = data === true;
  }
  if (!ammesso) return json({ errore: "non autorizzato" }, 401);
  let corpo: any = {};
  try { corpo = await req.json(); } catch { /* vuoto */ }

  const esiti = await controlla();
  const guasti = esiti.filter((e) => !e.ok);
  const { data: ultimi } = await db.from("jarvis_systems").select("ok, avvisato, creato").order("creato", { ascending: false }).limit(1);
  const prima = ultimi?.[0];
  let avvisato = false;

  if (guasti.length) {
    // si avvisa al primo guasto, e poi ogni 6 ore finché non torna a posto (non ogni ora)
    const ultimoAvviso = (await db.from("jarvis_systems").select("creato").eq("avvisato", true).is("riepilogo", null).order("creato", { ascending: false }).limit(1)).data?.[0]?.creato;
    const daRipetere = !ultimoAvviso || Date.now() - new Date(ultimoAvviso).getTime() > 6 * 3600_000;
    if (!prima || prima.ok || daRipetere) {
      const testo = guasti.map((g) => `${g.nome}: ${g.dettaglio}`).join(" · ");
      avvisato = (await avvisa("⚠️ JARVIS · Systems Check", testo, true).catch(() => 0)) > 0;
    }
  } else if (prima && !prima.ok) {
    avvisato = (await avvisa("JARVIS · Systems Check", "I sistemi che non andavano sono tornati a funzionare, Sir.", false).catch(() => 0)) > 0;
  }

  await db.from("jarvis_systems").insert({ ok: guasti.length === 0, esiti, avvisato });

  // riepilogo serale (alle 21, una volta sola) — o forzato
  let riepilogo: string | null = null;
  if (corpo?.riepilogo === true || oraRoma() === 21) {
    const oggi = giornoRoma();
    const { data: fatto } = await db.from("jarvis_systems").select("id").eq("riepilogo", oggi).limit(1);
    if (corpo?.riepilogo === true || !fatto?.length) {
      const da = new Date(Date.now() - 24 * 3600_000).toISOString();
      const { data: giro } = await db.from("jarvis_systems").select("ok, esiti, creato").is("riepilogo", null).gte("creato", da);
      const brutti = (giro ?? []).filter((r: any) => !r.ok);
      const nomi = [...new Set(brutti.flatMap((r: any) => (r.esiti ?? []).filter((e: any) => !e.ok).map((e: any) => e.nome)))];
      riepilogo = !brutti.length
        ? `Oggi tutti i sistemi sono andati, Sir. ${giro?.length ?? 0} controlli, nessun problema.`
        : `Oggi ${brutti.length} controll${brutti.length === 1 ? "o" : "i"} su ${giro?.length ?? 0} con problemi (${nomi.join(", ")}). ${guasti.length ? "Ancora da sistemare." : "Adesso è tutto a posto."}`;
      await avvisa("JARVIS · Systems Check · report", riepilogo, false);
      await db.from("jarvis_systems").insert({ ok: guasti.length === 0, esiti: [], avvisato: true, riepilogo: oggi });
    }
  }
  if (corpo?.prova === true) await avvisa("JARVIS · Systems Check (prova)", guasti.length ? `Guasti: ${guasti.map((g) => g.nome).join(", ")}` : "Tutti i sistemi rispondono, Sir.", false);

  // pulizia: si tiene un mese di storia
  await db.from("jarvis_systems").delete().lt("creato", new Date(Date.now() - 30 * 86400_000).toISOString());
  return json({ ok: guasti.length === 0, esiti, avvisato, riepilogo });
});
