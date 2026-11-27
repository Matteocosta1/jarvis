// JARVIS parla per primo: il briefing del mattino come notifica push sull'iPhone (e quindi sull'Apple Watch).
// Chi lo sveglia: pg_cron (alle 7 e alle 8 UTC, con x-chiave-interna) oppure l'app/il signore (x-jarvis-token) per una prova.
// Segreti: JARVIS_TOKEN, JARVIS_BUNDLE_ID (identificatore dell'app JARVIS in Xcode), APNS_KEY_P8, APNS_KEY_ID, APNS_TEAM_ID.
// Corpo facoltativo: { forza: true } manda subito, a qualunque ora; { testo: "..." } manda questo avviso invece del briefing;
// { promesse: true } (pg_cron ogni 15 minuti) manda le promesse della seconda memoria in scadenza;
// { diario: true } (pg_cron alle 23:30 di Roma) manda la domanda della sera del diario;
// { radar: true } (pg_cron ogni 10 minuti) manda l'avviso di pioggia quando il cervello dice che sta per piovere (una volta per pioggia);
//   26 ott sera: insieme alla notifica accende anche la Dynamic Island PIOGGIA sull'iPhone, anche ad app chiusa (push-to-start);
// { isola_gettone: "…" } (dall'app) il gettone push-to-start dell'iPhone per l'isola della PIOGGIA (tabella jarvis_isola);
// { notte: true } (pg_cron, alle 4 di Roma) rilegge le frasi del giorno e trova gli impegni detti di passaggio: il briefing li chiede.
// { novita: true } (pg_cron, alle 5 di Roma) il giro delle novità: Haiku cerca sul web sui temi del signore, ne tiene al massimo 3
//   (jarvis_novita) e il briefing delle 9:30 le dice con le parole di JARVIS. Il cervello non si tocca (26 nov, via del signore).
//   27 nov: nello stesso giro le USCITE MUSICALI degli artisti della sua lista (jarvis_artisti) da Apple Music, a costo zero.
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
    body: JSON.stringify({ messaggi: [{ role: "user", content: richiesta }], dispositivo: "iphone", strumenti_client: [], senza_filo: true, briefing: true }),   // il briefing non tocca il filo della chat
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

// ───────── La notte di JARVIS (25 ott, approvata dal signore) ─────────
// Le frasi del giorno (jarvis_giornata, le scrive il cervello: mai le modalità riservate) si rileggono di notte con Sonnet e si
// cercano gli impegni che il signore ha detto di passaggio senza chiedere di ricordarli («domani chiamo Matteo»). Non si salvano
// da soli: diventano proposte (jarvis_impegni) che il briefing del mattino gli chiede; col suo sì il cervello le segna come promesse.
const MODELLO_NOTTE = Deno.env.get("MODELLO_NOTTE") || "claude-sonnet-5-5";
const giornoRoma = (d = new Date()) => new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Rome" }).format(d);
const oraLeggibile = (iso: string) => new Intl.DateTimeFormat("it-IT", { timeZone: "Europe/Rome", weekday: "long", day: "numeric", month: "long", hour: "2-digit", minute: "2-digit" }).format(new Date(iso));

async function leggiNotte() {
  const adesso = new Date();
  // pulizia: le frasi oltre 3 giorni si cancellano; le proposte senza risposta da 2 giorni scadono.
  // 12 nov (revisione del dialogo, errore 6): solo quelle già diventate un ricordo (jarvis_episodi) o del Mac (che non fa ricordi):
  // prima si cancellavano anche le conversazioni non ancora riassunte, e quei ricordi andavano persi per sempre
  const tre = new Date(adesso.getTime() - 3 * 86_400_000).toISOString();
  const { data: ricordato } = await db.from("jarvis_episodi").select("fine").order("fine", { ascending: false }).limit(1).maybeSingle();
  await db.from("jarvis_giornata").delete().eq("dispositivo", "mac").lt("creato", tre);
  if (ricordato?.fine) await db.from("jarvis_giornata").delete().lt("creato", tre).lte("creato", ricordato.fine);
  await db.from("jarvis_impegni").update({ stato: "scaduto" }).eq("stato", "proposto").lt("giorno", giornoRoma(new Date(adesso.getTime() - 86_400_000)));
  const { data: frasi, error } = await db.from("jarvis_giornata").select("id, creato, signore, jarvis").eq("letto", false).order("creato").limit(400);
  if (error) throw error;
  if (!frasi?.length) return { frasi: 0, impegni: 0 };
  // quello che è già segnato non si ripropone: promesse aperte, note aperte, proposte ancora in attesa
  const [promesse, note, attesa] = await Promise.all([
    db.from("jarvis_ricordi").select("testo, persona, quando").eq("tipo", "promessa").eq("fatto", false).limit(60),
    db.from("jarvis_note").select("testo, scadenza").eq("fatta", false).limit(60),
    db.from("jarvis_impegni").select("testo").eq("stato", "proposto").limit(30),
  ]);
  const gia = [
    ...(promesse.data ?? []).map((r: any) => `- promessa: ${r.testo}${r.persona ? ` (${r.persona})` : ""}${r.quando ? `, ${oraLeggibile(r.quando)}` : ""}`),
    ...(note.data ?? []).map((r: any) => `- nota: ${r.testo}${r.scadenza ? `, entro ${r.scadenza}` : ""}`),
    ...(attesa.data ?? []).map((r: any) => `- già proposto: ${r.testo}`),
  ].join("\n") || "(niente)";
  const diario = frasi.map((f: any) => `[${oraLeggibile(f.creato)}] SIGNORE: ${String(f.signore).slice(0, 700)}${f.jarvis ? `\n   JARVIS: ${String(f.jarvis).slice(0, 300)}` : ""}`).join("\n");
  const sistema = `Leggi le frasi che il signore ha detto a JARVIS, il suo assistente, nelle ultime ore. Trova SOLO gli impegni concreti che il signore ha detto di dover fare LUI, nel futuro, detti di passaggio: chiamare o scrivere a qualcuno, comprare, pagare, portare, prenotare, consegnare, un appuntamento preso («domani chiamo Matteo», «sabato devo portare Bea a cena», «lunedì pago l'affitto»).
NON sono impegni: le richieste fatte a JARVIS e che JARVIS ha eseguito nella stessa conversazione (messaggi mandati, promemoria o note create, ricordi salvati); le domande; le prove dell'app e i comandi; i desideri vaghi senza un'azione («prima o poi vorrei…»); le cose che dice qualcun altro; le cose già fatte; quello che è già nella lista GIÀ SEGNATO, anche se detto con altre parole.
Nel dubbio NON metterlo: è molto meglio non proporre niente che proporre una cosa sbagliata. Al massimo 5 impegni.
Per «quando» calcola la data dal momento in cui la frase è stata detta (fuso di Roma): «domani» detto lunedì sera è martedì. Se è indicato solo il giorno, metti le 10:00; se non c'è un tempo, null.
Rispondi SOLO con un array JSON (vuoto [] se non c'è niente), oggetti {"testo": "frase breve all'infinito, es. Chiamare Matteo per il preventivo", "persona": "nome o null", "quando": "AAAA-MM-GGTHH:MM:00+01:00 o +02:00, o null", "frase": "le parole del signore, al massimo 120 caratteri"}.`;
  const richiesta = (conSforzo: boolean) => fetch("https://api.anthropic.com/v1/messages", {
    method: "POST", signal: AbortSignal.timeout(60_000),
    headers: { "content-type": "application/json", "x-api-key": Deno.env.get("ANTHROPIC_API_KEY") ?? "", "anthropic-version": "2023-06-01" },
    body: JSON.stringify({
      model: MODELLO_NOTTE, max_tokens: 1500, system: sistema,
      ...(conSforzo ? { output_config: { effort: "low" } } : {}),
      messages: [{ role: "user", content: `ADESSO: ${oraLeggibile(adesso.toISOString())} (${giornoRoma(adesso)})\n\nGIÀ SEGNATO:\n${gia}\n\nFRASI:\n${diario}` }],
    }),
  });
  let r = await richiesta(true);
  if (r.status === 400) r = await richiesta(false);       // se lo sforzo non fosse accettato, si riprova senza
  if (!r.ok) throw new Error(`Anthropic ${r.status}: ${(await r.text()).slice(0, 200)}`);
  const d = await r.json();
  const u = d.usage ?? {};
  await db.from("jarvis_consumi").insert({ servizio: "notte", modello: MODELLO_NOTTE, token_in: u.input_tokens ?? 0, token_cache: u.cache_read_input_tokens ?? 0,
    token_cache_scrittura: u.cache_creation_input_tokens ?? 0, token_out: u.output_tokens ?? 0, esito: "fine" }).then(() => {}, () => {});
  const out = (d.content ?? []).filter((b: any) => b.type === "text").map((b: any) => b.text).join("").trim();
  const a = out.indexOf("["), b = out.lastIndexOf("]");
  let trovati: any[] = [];
  if (a >= 0 && b > a) { try { const x = JSON.parse(out.slice(a, b + 1)); if (Array.isArray(x)) trovati = x; } catch { /* risposta non leggibile: niente impegni */ } }
  const oggi = giornoRoma(adesso);
  const righe = trovati.slice(0, 5).map((t) => {
    const q = t?.quando ? new Date(String(t.quando)) : null;
    return {
      giorno: oggi,
      testo: String(t?.testo ?? "").trim().slice(0, 160),
      persona: t?.persona && String(t.persona) !== "null" ? String(t.persona).slice(0, 80) : null,
      quando: q && !isNaN(q.getTime()) && q.getTime() > adesso.getTime() - 86_400_000 ? q.toISOString() : null,
      frase: t?.frase ? String(t.frase).slice(0, 200) : null,
    };
  }).filter((x) => x.testo.length >= 4);
  if (righe.length) { const ins = await db.from("jarvis_impegni").insert(righe); if (ins.error) throw ins.error; }
  // lette: la notte dopo non si rileggono (restano ancora 3 giorni, poi si cancellano)
  await db.from("jarvis_giornata").update({ letto: true }).in("id", frasi.map((f: any) => f.id));
  return { frasi: frasi.length, impegni: righe.length, trovati: righe.map((x) => x.testo) };
}

// ───────── Il giro delle novità (26 nov, via del signore alle 03:41) ─────────
// Una volta a notte Haiku cerca sul web le novità sui temi del signore e ne tiene al massimo 3, di temi diversi, graffiti prima di tutto
// (26 nov, 03:47: «carino che tratti più argomenti, soprattutto i graffiti»).
// Tetto fisso: 8 ricerche a giro (circa 1 centesimo l'una) e un giro solo al giorno, anche se pg_cron chiama due volte.
// Quelle già dette non tornano: le ultime 40 si passano a Haiku come «già dette» e il briefing segna quelle che usa.
const MODELLO_NOVITA = Deno.env.get("MODELLO_NOVITA") || "claude-haiku-5-5";
const RICERCHE_MAX = 8;
const TEMI_NOVITA = `- graffiti e writing: la scena old school di New York (Kaws, Part, la crew The Death Squad), writer famosi, mostre e festival di graffiti e street art, nuove vernici spray;
- musica: punk inglese (Clash, Sex Pistols, Iggy Pop), jazz, hip hop americano, trap italiana (Sfera Ebbasta, Tony Boy), musica elettronica: dischi e tracce nuove, concerti a Milano;
- cinema e serie: Marvel (film, serie, annunci), serie crime (Mr. Robot, Prison Break, Breaking Bad, Romanzo Criminale), film nuovi nel genere;
- tecnologia: computer, iPhone, Apple Watch e strumenti nuovi per creativi e programmatori (Mac, Xcode, intelligenza artificiale);
- Milano: mostre, eventi e occasioni per un artista e writer con molti follower.`;

async function giroNovita(forza: boolean) {
  const oggi = giornoRoma();
  if (!forza) {
    const { data: fatto } = await db.from("jarvis_novita").select("id").eq("giorno", oggi).limit(1);
    if (fatto?.length) return { saltato: true, motivo: "il giro di oggi è già fatto" };
  }
  let musica: { giorno: string; titolo: string; perche: string | null; fonte: string | null }[] = [];
  try { musica = await usciteMusica(oggi); } catch (e) { console.error("uscite musicali:", (e as Error).message); }   // 27 nov: se Apple Music non risponde, il giro va avanti
  const { data: gia } = await db.from("jarvis_novita").select("titolo").order("creato", { ascending: false }).limit(40);
  const giaDette = [...(gia ?? []).map((r: any) => `- ${r.titolo}`), ...musica.map((m) => `- ${m.titolo}`)].join("\n") || "(niente)";
  const sistema = `Sei il servizio notizie di JARVIS, l'assistente personale di Alessandro (King Rusto): writer di graffiti molto famoso in Italia (quasi 150.000 follower), artista, programmatore di app, socio di Discosizer (serate di musica elettronica a Milano).
Cerca sul web le NOVITÀ degli ultimi giorni che potrebbero interessargli davvero, su questi temi:
${TEMI_NOVITA}
Regole:
- solo fatti veri e recenti (ultimi 7 giorni, o annunci di cose in arrivo), con una fonte affidabile; niente voci, niente pubblicità, niente notizie generiche;
- gli piace la varietà: cerca su più temi diversi e scegli fino a 3 novità di temi DIVERSI (mai due dello stesso tema);
- i graffiti sono il tema che gli sta più a cuore: almeno 2 ricerche sui graffiti, e se c'è una novità di graffiti che vale, mettila sempre; poi la musica, poi il resto;
- solo quello che a lui farebbe dire «questa è bella»: una novità debole non la metti; se non c'è niente che valga, rispondi [];
- mai una novità già nella lista GIÀ DETTE, anche se scritta con altre parole;
- usa al massimo ${RICERCHE_MAX} ricerche, mirate e spalmate sui temi.
Rispondi SOLO con un array JSON di al massimo 3 oggetti: {"titolo": "la novità in una frase breve, in italiano", "perche": "perché interessa a lui, in poche parole", "fonte": "l'indirizzo web della fonte"}.`;
  const messaggi: any[] = [{ role: "user", content: `OGGI: ${oraLeggibile(new Date().toISOString())}\n\nGIÀ DETTE:\n${giaDette}\n\nCerca le novità di oggi per lui.` }];
  const uso = { in: 0, cache: 0, scrittura: 0, out: 0, ricerche: 0 };
  let finale: any = null;
  for (let giro = 0; giro < 3; giro++) {                       // «pause_turn»: le ricerche lunghe si riprendono, al massimo 3 volte
    const r = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST", signal: AbortSignal.timeout(110_000),
      headers: { "content-type": "application/json", "x-api-key": Deno.env.get("ANTHROPIC_API_KEY") ?? "", "anthropic-version": "2023-06-01" },
      body: JSON.stringify({
        model: MODELLO_NOVITA, max_tokens: 2000, system: sistema, messages: messaggi,
        tools: [{ type: "web_search_20250305", name: "web_search", max_uses: RICERCHE_MAX,
          user_location: { type: "approximate", city: "Milano", country: "IT", timezone: "Europe/Rome" } }],
      }),
    });
    if (!r.ok) throw new Error(`Anthropic ${r.status}: ${(await r.text()).slice(0, 200)}`);
    const d = await r.json();
    const u = d.usage ?? {};
    uso.in += u.input_tokens ?? 0; uso.cache += u.cache_read_input_tokens ?? 0; uso.scrittura += u.cache_creation_input_tokens ?? 0;
    uso.out += u.output_tokens ?? 0; uso.ricerche += u.server_tool_use?.web_search_requests ?? 0;
    finale = d;
    if (d.stop_reason !== "pause_turn" || uso.ricerche >= RICERCHE_MAX) break;
    messaggi.push({ role: "assistant", content: d.content });
  }
  await db.from("jarvis_consumi").insert({ servizio: "novita", modello: MODELLO_NOVITA, token_in: uso.in, token_cache: uso.cache,
    token_cache_scrittura: uso.scrittura, token_out: uso.out, esito: finale?.stop_reason ?? null, app: { ricerche: uso.ricerche } }).then(() => {}, () => {});
  const out = (finale?.content ?? []).filter((b: any) => b.type === "text").map((b: any) => b.text).join("").trim();
  const a = out.lastIndexOf("[", out.indexOf("{") >= 0 ? out.indexOf("{") : out.length), b = out.lastIndexOf("]");
  let trovate: any[] = [];
  if (a >= 0 && b > a) { try { const x = JSON.parse(out.slice(a, b + 1)); if (Array.isArray(x)) trovate = x; } catch { /* risposta non leggibile: niente novità */ } }
  if (!trovate.length && out.trim().startsWith("[")) { try { const x = JSON.parse(out); if (Array.isArray(x)) trovate = x; } catch { /* vuoto */ } }
  const righe = trovate.slice(0, 3).map((t) => ({
    giorno: oggi,
    titolo: String(t?.titolo ?? "").trim().slice(0, 240),
    perche: t?.perche ? String(t.perche).trim().slice(0, 240) : null,
    fonte: /^https?:\/\//.test(String(t?.fonte ?? "")) ? String(t.fonte).slice(0, 500) : null,
  })).filter((x) => x.titolo.length >= 8);
  const tutte = [...righe, ...musica];                         // prima le novità del web (i graffiti davanti), poi le uscite
  if (tutte.length) { const ins = await db.from("jarvis_novita").insert(tutte); if (ins.error) throw ins.error; }
  else await db.from("jarvis_novita").insert({ giorno: oggi, titolo: "(nessuna novità che valga)", detta: true });   // il giro di oggi è fatto
  return { ricerche: uso.ricerche, novita: righe.length, uscite: musica.length, trovate: tutte };
}

// ───────── 27 nov · USCITE MUSICALI (issue #19, pezzo 2): Apple Music, gli artisti della sua lista (tabella jarvis_artisti) ─────────
// Ogni mattina, dentro il giro delle novità: per ogni artista l'ultima uscita (album, EP o singolo) dal catalogo italiano; se è
// uscita negli ultimi 7 giorni e non è già stata detta, diventa una novità. Nessun modello: costo zero (l'API è inclusa nel
// Developer Program). Segreti: MUSICKIT_KEY_P8, MUSICKIT_KEY_ID (chiave MusicKit del portale) e APNS_TEAM_ID (lo stesso team).
// Senza la chiave non fa niente.
const AM = "https://api.music.apple.com/v1/catalog/it";
let cacheJwtMusica: { token: string; creato: number } | null = null;
async function jwtMusica() {
  const p8 = Deno.env.get("MUSICKIT_KEY_P8"), keyId = Deno.env.get("MUSICKIT_KEY_ID"), teamId = Deno.env.get("APNS_TEAM_ID");
  if (!p8 || !keyId || !teamId) return null;
  if (cacheJwtMusica && Date.now() - cacheJwtMusica.creato < 40 * 60_000) return cacheJwtMusica.token;
  const chiave = await importPKCS8(p8.replace(/\\n/g, "\n").trim(), "ES256");
  const token = await new SignJWT({}).setProtectedHeader({ alg: "ES256", kid: keyId }).setIssuer(teamId).setIssuedAt()
    .setExpirationTime("1h").sign(chiave);
  cacheJwtMusica = { token, creato: Date.now() };
  return token;
}
async function am(token: string, percorso: string) {
  const r = await fetch(AM + percorso, { headers: { authorization: `Bearer ${token}` }, signal: AbortSignal.timeout(15_000) });
  if (r.status === 404) return { data: [] };
  if (!r.ok) throw new Error(`Apple Music ${r.status}`);
  return await r.json();
}
const visteInProva: string[] = [];
async function usciteMusica(oggi: string, prova = false) {
  const token = await jwtMusica();
  if (!token) { if (prova) throw new Error("manca la chiave MusicKit (MUSICKIT_KEY_P8, MUSICKIT_KEY_ID o APNS_TEAM_ID)"); return []; }
  const { data: artisti } = await db.from("jarvis_artisti").select("id, nome, am_id, ultima_uscita").eq("attivo", true).order("id");
  const limite = new Date(Date.now() - (prova ? 120 : 7) * 86_400_000).toISOString().slice(0, 10);   // in prova: 4 mesi, per vedere che legge
  const nuove: { giorno: string; titolo: string; perche: string | null; fonte: string | null }[] = [];
  let richieste = 0;
  for (const a of (artisti ?? []) as any[]) {
    try {
      let id: string | null = a.am_id;
      if (!id) {                                                // la prima volta: si cerca l'artista nel catalogo e si ricorda
        richieste++;
        const s = await am(token, `/search?types=artists&limit=1&term=${encodeURIComponent(a.nome)}`);
        id = s?.results?.artists?.data?.[0]?.id ?? null;
        if (!id) continue;
        await db.from("jarvis_artisti").update({ am_id: id }).eq("id", a.id);
      }
      richieste++;
      const u = (await am(token, `/artists/${id}/view/latest-release`))?.data?.[0];
      const at = u?.attributes;
      if (prova) visteInProva.push(`${a.nome} (${id}): ${at?.name ?? "nessuna uscita recente"} ${at?.releaseDate ?? ""}`.trim());
      if (!u?.id || !at?.releaseDate || at.releaseDate < limite || at.releaseDate > oggi || (!prova && u.id === a.ultima_uscita)) continue;
      const tipo = at.isSingle ? "il singolo" : (at.trackCount ?? 0) <= 6 ? "l'EP" : "l'album";
      const quando = new Intl.DateTimeFormat("it-IT", { day: "numeric", month: "long" }).format(new Date(at.releaseDate + "T12:00:00Z"));
      nuove.push({ giorno: oggi, titolo: `È uscito ${tipo} «${String(at.name).slice(0, 120)}» di ${String(at.artistName ?? a.nome).slice(0, 80)}, il ${quando}`,
        perche: "È uno degli artisti della sua lista su Apple Music.", fonte: /^https:\/\//.test(at.url ?? "") ? at.url : null });
      if (!prova) await db.from("jarvis_artisti").update({ ultima_uscita: u.id }).eq("id", a.id);
    } catch (e) { if (prova) throw e; console.error(`uscite musicali, ${a.nome}:`, (e as Error).message); }
  }
  if (!prova) await db.from("jarvis_consumi").insert({ servizio: "uscite", modello: "apple-music", token_in: 0, token_out: 0, esito: "fine",
    app: { artisti: (artisti ?? []).length, richieste, uscite: nuove.length } }).then(() => {}, () => {});
  return nuove;
}

/// Al mattino: le novità del giro di stanotte (non ancora dette), da passare al cervello per il briefing.
async function novitaDaDire() {
  const da = giornoRoma(new Date(Date.now() - 2 * 86_400_000));
  const { data } = await db.from("jarvis_novita").select("id, titolo, perche").eq("detta", false).gte("giorno", da).order("id").limit(3);
  return (data ?? []) as { id: number; titolo: string; perche: string | null }[];
}

/// Al mattino: la domanda sugli impegni trovati stanotte, da mettere in fondo al briefing (vuota se non ce ne sono).
async function domandaImpegni() {
  const { data } = await db.from("jarvis_impegni").select("testo").eq("stato", "proposto").eq("giorno", giornoRoma()).order("id").limit(5);
  const lista = (data ?? []).map((r: any) => String(r.testo).replace(/[.\s]+$/, ""));
  if (!lista.length) return "";
  const minuscola = (t: string) => t.charAt(0).toLowerCase() + t.slice(1);
  return lista.length === 1
    ? ` Ieri ha detto di dover ${minuscola(lista[0])}: lo segno tra le promesse?`
    : ` Ieri ha detto di dover: ${lista.map(minuscola).join("; ")}. Li segno tra le promesse?`;
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

// ───────── 26 ott sera: la Dynamic Island della PIOGGIA, accesa dal cervello anche ad app chiusa (push-to-start, iOS 17.2+) ─────────
// La notifica resta quella di sempre (arriva anche all'orologio); l'isola mostra il conto alla rovescia, i millimetri, Radar e Ok.
// Le date del contenuto sono in secondi dal 1° gennaio 2001 (come le legge iOS), non dal 1970.
const DAL_2001 = 978_307_200;

async function isolaPioggia(titolo: string, testo: string, d: any) {
  const jwt = await jwtApple();
  const bundle = Deno.env.get("JARVIS_BUNDLE_ID");
  if (!jwt || !bundle) return { isola: "chiavi Apple o JARVIS_BUNDLE_ID mancanti" };
  const { data } = await db.from("jarvis_isola").select("gettone");
  const gettoni = (data ?? []).map((r: any) => String(r.gettone));
  if (!gettoni.length) return { isola: "nessun iPhone con l'isola (aprire JARVIS una volta dopo la build 10.0 (7))" };
  const minuti = Number(d?.inizia_min ?? d?.minuti ?? senzaToni(testo).match(/(\d+)\s*min/)?.[1] ?? 0) || 0;
  const mm = d?.mm_30 ?? senzaToni(testo).match(/(\d+(?:[.,]\d+)?)\s*mm/)?.[1];
  const ora = Math.floor(Date.now() / 1000), comincia = ora + minuti * 60;
  const corpo = JSON.stringify({
    aps: {
      timestamp: ora, event: "start",
      "attributes-type": "AttivitaJarvis", attributes: { meta: "Radar" },
      "content-state": { tipo: "pioggia", esci: comincia - DAL_2001, riga: `${mm ? `${String(mm).replace(".", ",")} mm nella prossima mezz'ora · ` : ""}dove si trova` },
      "stale-date": comincia + 45 * 60,
      alert: { title: titolo, body: senzaToni(testo).slice(0, 300) },
    },
  });
  let accese = 0; const esiti: string[] = [];
  for (const g of gettoni) {
    const manda = (host: string) => fetch(`${host}/3/device/${g}`, {
      method: "POST", body: corpo,
      headers: { authorization: `bearer ${jwt}`, "apns-topic": `${bundle}.push-type.liveactivity`, "apns-push-type": "liveactivity", "apns-priority": "10", "content-type": "application/json" },
    });
    let r = await manda("https://api.push.apple.com");
    let motivo = r.ok ? "" : ((await r.json().catch(() => ({}))) as any).reason ?? "";
    if (!r.ok && motivo === "BadDeviceToken") { r = await manda("https://api.sandbox.push.apple.com"); motivo = r.ok ? "" : ((await r.json().catch(() => ({}))) as any).reason ?? ""; }
    if (!r.ok && (r.status === 410 || motivo === "BadDeviceToken" || motivo === "Unregistered")) await db.from("jarvis_isola").delete().eq("gettone", g);
    if (r.ok) accese++; else esiti.push(`${r.status} ${motivo}`.trim());
  }
  return { isola_accese: accese, ...(esiti.length ? { isola_errori: esiti } : {}) };
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

  if (daApp && typeof corpo.isola_gettone === "string") {                          // 26 ott sera: il gettone dell'isola della PIOGGIA
    const g = corpo.isola_gettone.replace(/[^0-9a-f]/gi, "").slice(0, 400);
    if (!g) return json({ errore: "gettone vuoto" }, 400);
    await db.from("jarvis_isola").upsert({ gettone: g, creato: new Date().toISOString() });
    return json({ ok: true });
  }
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
  if (corpo.episodi === true) {                                                      // 12 nov: le conversazioni finite diventano ricordi (pg_cron ogni 10 minuti)
    try {
      const r = await fetch(`${Deno.env.get("SUPABASE_URL")}/functions/v1/jarvis`, {
        method: "POST", signal: AbortSignal.timeout(100_000),
        headers: { "content-type": "application/json", "x-jarvis-token": Deno.env.get("JARVIS_TOKEN") ?? "" },
        body: JSON.stringify({ episodi_chiudi: true }),
      });
      return json(await r.json().catch(() => ({ errore: `cervello ${r.status}` })));
    } catch (e) { return json({ errore: (e as Error).message }); }
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
      const titolo = String(d.titolo || "Radar");
      const esito = await mandaATutti(titolo, d.testo, "radar");
      const isola = await isolaPioggia(titolo, d.testo, d).catch((e) => ({ isola: (e as Error).message }));   // 26 ott sera
      return json({ ...esito, ...isola, testo: d.testo });
    } catch (e) { return json({ inviata: false, errore: (e as Error).message }); }
  }
  if (corpo.uscite_prova === true) {                                                 // 27 nov: prova delle uscite musicali, senza dirle né segnarle
    try { visteInProva.length = 0; const uscite = await usciteMusica(giornoRoma(), true); return json({ uscite, lette: visteInProva }); } catch (e) { return json({ errore: (e as Error).message }, 500); }
  }
  if (corpo.novita === true) {                                                       // il giro delle novità, alle 5 di Roma (26 nov)
    if (daCron && !corpo.forza && oraRoma() !== 5) return json({ saltato: true, ora_roma: oraRoma() });
    try { return json(await giroNovita(daApp && corpo.forza === true)); } catch (e) { return json({ errore: (e as Error).message }, 500); }
  }
  if (corpo.notte === true) {                                                        // la notte di JARVIS, alle 4 di Roma
    if (daCron && !corpo.forza && oraRoma() !== 4) return json({ saltato: true, ora_roma: oraRoma() });
    try { return json(await leggiNotte()); } catch (e) { return json({ errore: (e as Error).message }, 500); }
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
    // 26 nov: le novità del giro di stanotte, se ci sono: il cervello le dice con le sue parole, in una frase in più
    const novita = await novitaDaDire().catch(() => []);
    const conNovita = novita.length
      ? " In più, con parole tue e in una sola frase, digli le novità trovate stanotte per lui (lascia fuori quelle che non ti sembrano all'altezza): " +
        novita.map((n) => n.titolo + (n.perche ? ` (${n.perche})` : "")).join("; ") + "."
      : "";
    const testoCervello = await chiediAlCervello(
      "Buongiorno Jarvis. Preparami il briefing del mattino per una notifica sul telefono: meteo di oggi a Milano, email importanti arrivate da ieri sera, " +
      `note aperte o in scadenza, prossima serata se nota. Al massimo ${novita.length ? "cinque" : "quattro"} frasi brevi, da maggiordomo al mattino, senza elenchi. ` +
      "Non hai calendario né dati di salute in questo momento: non nominarli. Non nominare gli impegni da confermare: li aggiungo io in fondo." + conNovita);
    if (novita.length) await db.from("jarvis_novita").update({ detta: true }).in("id", novita.map((n) => n.id)).then(() => {}, () => {});
    const testo = testoCervello + await domandaImpegni().catch(() => "");   // la notte di JARVIS: gli impegni trovati, da confermare
    const esito = await mandaATutti("Buongiorno, Sir", testo, "briefing");   // decisione 13 (24 ott): «Sir», come le altre frasi fisse
    await db.from("jarvis_azioni").insert({ dispositivo: "cervello", strumento: "briefing_push", dettagli: JSON.stringify({ ora: oraRoma() }), esito: JSON.stringify(esito).slice(0, 200), errore: !!(esito as any).errore }).then(() => {}, () => {});
    return json({ ...esito, testo });
  } catch (e) {
    return json({ errore: (e as Error).message }, 500);
  }
});
