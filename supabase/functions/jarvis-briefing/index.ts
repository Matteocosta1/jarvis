// JARVIS parla per primo: il briefing del mattino come notifica push sull'iPhone (e quindi sull'Apple Watch).
// Chi lo sveglia: pg_cron (alle 7 e alle 8 UTC, con x-chiave-interna) oppure l'app/il signore (x-jarvis-token) per una prova.
// Segreti: JARVIS_TOKEN, JARVIS_BUNDLE_ID (identificatore dell'app JARVIS in Xcode), APNS_KEY_P8, APNS_KEY_ID, APNS_TEAM_ID.
// Corpo facoltativo: { forza: true } manda subito, a qualunque ora; { testo: "..." } manda questo avviso invece del briefing;
// { promesse: true } (pg_cron ogni 15 minuti) manda le promesse della seconda memoria in scadenza;
// { diario: true } (pg_cron alle 23:30 di Roma) manda la domanda della sera del diario;
// { radar: true } (pg_cron ogni 10 minuti) manda l'avviso di pioggia quando il cervello dice che sta per piovere (una volta per pioggia).
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { SignJWT, importPKCS8 } from "npm:jose@5";

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { "content-type": "application/json" } });
const ORA_BRIEFING = Number(Deno.env.get("BRIEFING_ORA") || 9);

function uguali(a: string, b: string) {
  if (!a || a.length !== b.length) return false;
  let x = 0; for (let k = 0; k < a.length; k++) x |= a.charCodeAt(k) ^ b.charCodeAt(k);
  return x === 0;
}

/// Una domanda sola ogni sera, mai la stessa nell'ultimo mese: da maggiordomo, non da questionario.
const DOMANDE_SERA = [
  "Cosa l'ha fatta sorridere oggi?",
  "C'è qualcosa che si porta a letto stasera?",
  "Qual è stato il momento migliore della giornata?",
  "Com'è andata con le persone a cui tiene, oggi?",
  "Se dovesse dare un colore a questa giornata, quale sarebbe?",
  "C'è stato un momento in cui si è sentito stanco davvero?",
  "Di cosa è orgoglioso, oggi, anche se piccolo?",
  "Cosa la sta preoccupando in questi giorni?",
  "Ha creato qualcosa oggi, anche solo un'idea?",
  "Con chi le ha fatto bene parlare oggi?",
  "C'è qualcosa che avrebbe voluto dire e non ha detto?",
  "Come sta il suo corpo stasera?",
  "Cosa vorrebbe che domani andasse diversamente?",
  "Cosa ha imparato oggi, su di sé o sugli altri?",
  "C'è stato un momento di calma, oggi?",
  "Che musica le ha tenuto compagnia oggi?",
  "Cosa le ha tolto energia, e cosa gliel'ha data?",
  "Come sta andando con Beatrice in questi giorni?",
  "Se domani fosse una giornata libera, cosa farebbe?",
  "C'è qualcuno a cui vorrebbe dire grazie?",
  "Cosa le ha fatto perdere la pazienza oggi?",
  "Si è preso un po' di tempo per sé, oggi?",
  "Qual è la cosa che rimanda da troppo?",
  "Che cosa la fa sentire a casa, in questo periodo?",
  "Ha dipinto o disegnato qualcosa ultimamente, o le è venuta voglia di farlo?",
  "In una parola, com'è andata?",
  "Cosa si dice da solo quando le cose vanno storte?",
  "C'è qualcosa che le manca, in questo periodo?",
  "Chi l'ha sorpresa oggi, in bene o in male?",
  "Cosa vorrebbe ricordare di oggi tra un anno?",
];

function oraRoma() {
  return Number(new Intl.DateTimeFormat("en-GB", { timeZone: "Europe/Rome", hour: "2-digit", hourCycle: "h23" }).format(new Date()));
}

// ───────── Il briefing lo scrive il cervello (jarvis), con la sua personalità e i suoi strumenti ─────────
async function chiediAlCervello(richiesta: string) {
  const r = await fetch(`${Deno.env.get("SUPABASE_URL")}/functions/v1/jarvis`, {
    method: "POST", signal: AbortSignal.timeout(80_000),
    headers: { "content-type": "application/json", "x-jarvis-token": Deno.env.get("JARVIS_TOKEN") ?? "" },
    body: JSON.stringify({ messaggi: [{ role: "user", content: richiesta }], dispositivo: "iphone", strumenti_client: [], senza_filo: true }),   // il briefing non tocca il filo della chat
  });
  if (!r.ok || !r.body) throw new Error(`cervello: ${r.status}`);
  let testo = "", resto = "";
  for await (const pezzo of r.body.pipeThrough(new TextDecoderStream())) {
    resto += pezzo;
    let k;
    while ((k = resto.indexOf("\n")) >= 0) {
      const riga = resto.slice(0, k).trim(); resto = resto.slice(k + 1);
      if (!riga) continue;
      let e: any; try { e = JSON.parse(riga); } catch { continue; }
      if (e.t === "fine") testo = String(e.testo ?? "");
      if (e.t === "errore") throw new Error(String(e.d ?? "errore del cervello"));
    }
  }
  if (!testo.trim()) throw new Error("il cervello non ha scritto nulla");
  return testo.trim();
}

// ───────── Notifiche push Apple (stesse chiavi dell'app delle serate: valgono per tutto il team) ─────────
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

// controllo 24 ott: con i toni della voce accesi (VOCE_TONI=on) il cervello può aprire una frase con «[whispers]» o «[sarcastic]».
// Sulla notifica (schermata di blocco) non si devono vedere: si tolgono dal testo mostrato. In jarvis_testo restano, perché
// l'app (build 22 in poi) li toglie dallo schermo da sé e li fa dire alla voce. Stessa forma dei toni del cervello.
const senzaToni = (t: string) => t.replace(/(^|\s)\[[a-z][a-z \-]{0,23}\](?!\()[ \t]*/g, "$1").replace(/[ \t]+([.,;:!?…])/g, "$1").replace(/[ \t]{2,}/g, " ").trim();

async function push(host: string, jwt: string, token: string, titolo: string, testo: string, azione: string) {
  const r = await fetch(`${host}/3/device/${token}`, {
    method: "POST",
    headers: { authorization: `bearer ${jwt}`, "apns-topic": Deno.env.get("JARVIS_BUNDLE_ID") ?? "", "apns-push-type": "alert", "apns-priority": "10", "content-type": "application/json" },
    body: JSON.stringify({
      aps: { alert: { title: titolo, body: senzaToni(testo).slice(0, 1500) }, sound: "default", "interruption-level": "active" },
      jarvis_azione: azione, jarvis_testo: testo.slice(0, 3000),
    }),
  });
  let motivo = "";
  if (!r.ok) { try { motivo = (await r.json()).reason ?? ""; } catch { /* vuoto */ } }
  return { ok: r.ok, stato: r.status, motivo };
}

async function mandaATutti(titolo: string, testo: string, azione: string) {
  const jwt = await jwtApple();
  if (!jwt) return { errore: "chiavi Apple per le notifiche (APNS_KEY_P8, APNS_KEY_ID, APNS_TEAM_ID) non configurate" };
  if (!Deno.env.get("JARVIS_BUNDLE_ID")) return { errore: "manca il segreto JARVIS_BUNDLE_ID (identificatore dell'app in Xcode)" };
  const { data } = await db.from("jarvis_dispositivi").select("token");
  const tokens = (data ?? []).map((d: any) => String(d.token));
  if (!tokens.length) return { errore: "nessun iPhone registrato: aprire l'app JARVIS una volta e accettare le notifiche" };
  let inviate = 0; const esiti: string[] = [];
  for (const t of tokens) {
    let e = await push("https://api.push.apple.com", jwt, t, titolo, testo, azione);
    if (!e.ok && e.motivo === "BadDeviceToken") e = await push("https://api.sandbox.push.apple.com", jwt, t, titolo, testo, azione);  // build di sviluppo da Xcode
    if (!e.ok && (e.stato === 410 || e.motivo === "BadDeviceToken" || e.motivo === "Unregistered")) await db.from("jarvis_dispositivi").delete().eq("token", t);
    if (e.ok) inviate++; else esiti.push(`${e.stato} ${e.motivo}`.trim());
  }
  return { inviate, dispositivi: tokens.length, ...(esiti.length ? { errori: esiti } : {}) };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ errore: "metodo non ammesso" }, 405);
  // o la parola d'ordine di JARVIS (app, prova manuale) o la chiave interna del database (pg_cron)
  const segreto = Deno.env.get("JARVIS_TOKEN") ?? "";
  const daApp = !!segreto && uguali(req.headers.get("x-jarvis-token") ?? "", segreto);
  let daCron = false;
  if (!daApp) {
    const interna = req.headers.get("x-chiave-interna") ?? "";
    const { data } = interna ? await db.rpc("verifica_chiave_interna", { p: interna }) : { data: false };
    daCron = data === true;
  }
  if (!daApp && !daCron) return json({ errore: "non autorizzato" }, 401);

  let corpo: any = {};
  try { corpo = await req.json(); } catch { /* corpo vuoto: va bene */ }

  if (corpo.promesse === true) {                                                     // promesse in scadenza: una notifica ciascuna
    const adesso = new Date();
    const { data } = await db.from("jarvis_ricordi").select("id, testo, persona, quando").eq("tipo", "promessa").eq("fatto", false).is("avvisato", null)
      .lte("quando", adesso.toISOString()).gte("quando", new Date(adesso.getTime() - 6 * 3600_000).toISOString()).order("quando").limit(5);
    let inviate = 0;
    for (const r of data ?? []) {
      const testo = `Sir, aveva detto${r.persona ? ` a ${r.persona}` : ""}: ${r.testo}`;
      const e = await mandaATutti("Promemoria di JARVIS", testo, "leggi");
      await db.from("jarvis_ricordi").update({ avvisato: adesso.toISOString() }).eq("id", r.id);
      if (!(e as any).errore) inviate++;
    }
    return json({ promesse: (data ?? []).length, inviate });
  }
  if (corpo.radar === true) {                                                        // RADAR (pg_cron ogni 10 minuti): il cervello decide, qui si avvisa
    try {
      const r = await fetch(`${Deno.env.get("SUPABASE_URL")}/functions/v1/jarvis`, {
        method: "POST", signal: AbortSignal.timeout(20_000),
        headers: { "content-type": "application/json", "x-jarvis-token": Deno.env.get("JARVIS_TOKEN") ?? "" },
        body: JSON.stringify({ radar_avviso: true }),
      });
      const d: any = await r.json().catch(() => ({}));
      if (!d.manda || typeof d.testo !== "string") return json({ inviata: false, motivo: d.motivo ?? d.errore ?? `cervello ${r.status}` });
      return json({ ...(await mandaATutti(String(d.titolo || "Radar"), d.testo, "radar")), testo: d.testo });
    } catch (e) { return json({ inviata: false, errore: (e as Error).message }); }
  }
  if (corpo.diario === true) {                                                       // il diario della sera, alle 23:30 di Roma
    if (daCron && !corpo.forza && oraRoma() !== 23) return json({ saltato: true, ora_roma: oraRoma() });
    const oggi = new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Rome" }).format(new Date());
    const { data: gia } = await db.from("jarvis_diario").select("id").eq("giorno", oggi).limit(1);
    if (gia?.length && !corpo.forza) return json({ saltato: true, motivo: "il diario di oggi è già scritto" });
    const { data: fatte } = await db.from("jarvis_domande_sera").select("domanda").order("giorno", { ascending: false }).limit(30);
    const usate = new Set((fatte ?? []).map((d: any) => d.domanda));
    const libere = DOMANDE_SERA.filter((d) => !usate.has(d));
    const domanda = (libere.length ? libere : DOMANDE_SERA)[Math.floor(Math.random() * (libere.length || DOMANDE_SERA.length))];
    await db.from("jarvis_domande_sera").upsert({ giorno: oggi, domanda });
    const testo = `Diario della sera, Sir. ${domanda}`;
    return json({ ...(await mandaATutti("Diario della sera", testo, "diario")), domanda });
  }
  if (typeof corpo.testo === "string" && corpo.testo.trim()) {                      // un avviso qualsiasi, già scritto
    return json(await mandaATutti(String(corpo.titolo || "JARVIS"), corpo.testo.trim(), "leggi"));
  }
  if (daCron && !corpo.forza && oraRoma() !== ORA_BRIEFING) return json({ saltato: true, ora_roma: oraRoma(), motivo: `il briefing si manda alle ${ORA_BRIEFING}` });

  try {
    const testo = await chiediAlCervello(
      "Buongiorno Jarvis. Preparami il briefing del mattino per una notifica sul telefono: meteo di oggi a Milano, email importanti arrivate da ieri sera, " +
      "note aperte o in scadenza, prossima serata se nota. Al massimo quattro frasi brevi, da maggiordomo al mattino, senza elenchi. " +
      "Non hai calendario né dati di salute in questo momento: non nominarli.");
    const esito = await mandaATutti("Buongiorno, signore", testo, "briefing");
    await db.from("jarvis_azioni").insert({ dispositivo: "cervello", strumento: "briefing_push", dettagli: JSON.stringify({ ora: oraRoma() }), esito: JSON.stringify(esito).slice(0, 200), errore: !!(esito as any).errore }).then(() => {}, () => {});
    return json({ ...esito, testo });
  } catch (e) {
    return json({ errore: (e as Error).message }, 500);
  }
});
