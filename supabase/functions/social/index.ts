// JARVIS — SOCIAL (MARK X): Instagram di @kingrusto con l'API ufficiale (Instagram API with Instagram Login, app Meta «JARVIS KR»).
// POST. Chi chiama: l'app (header x-jarvis-token) oppure pg_cron (header x-chiave-interna, solo «giro»).
// Corpo: { azione: "stato" | "rispondi" | "pubblica" | "annulla" | "auto" | "giro", ... }
//  · stato     → profilo, report 7 giorni, posta (commenti + messaggi, con la bozza di JARVIS), calendario, automazione
//  · rispondi  → { tipo: "commento"|"dm", id, a?, testo }  risposta pubblica al commento o messaggio in DM (solo col sì del signore, dall'app)
//  · pubblica  → { formato: "POST"|"STORIA"|"REEL", quando: "ORA"|"LUN12", didascalia, media (base64), mime }
//  · annulla   → { id } toglie un post programmato
//  · auto      → { on, parola, testo } l'automazione «commenta PAROLA → link in DM»
//  · giro      → (pg_cron ogni 10 minuti) pubblica i programmati scaduti e fa girare l'automazione
// Il token sta nella tabella social_token (rinnovato ogni lunedì da «social-token»); non esce mai da qui.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const URL_DB = Deno.env.get("SUPABASE_URL")!, KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const db = createClient(URL_DB, KEY, { auth: { persistSession: false } });
const G = "https://graph.instagram.com/v23.0";
const BUCKET = "social-media";
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { "content-type": "application/json" } });
const env = (k: string) => Deno.env.get(k) ?? "";
function uguali(a: string, b: string) {
  if (!a || a.length !== b.length) return false;
  let x = 0; for (let k = 0; k < a.length; k++) x |= a.charCodeAt(k) ^ b.charCodeAt(k);
  return x === 0;
}

async function token(): Promise<string> {
  const { data } = await db.from("social_token").select("token").eq("id", 1).maybeSingle();
  return data?.token ?? env("INSTAGRAM_TOKEN");
}
async function ig(t: string, percorso: string, params: Record<string, string> = {}, metodo = "GET", corpo?: Record<string, unknown>) {
  const u = new URL(G + percorso);
  for (const [k, v] of Object.entries(params)) u.searchParams.set(k, v);
  u.searchParams.set("access_token", t);
  const r = await fetch(u, metodo === "GET" ? {} : { method: metodo, headers: { "content-type": "application/json" }, body: JSON.stringify(corpo ?? {}) });
  const d = await r.json().catch(() => ({}));
  if (!r.ok || d.error) throw new Error(d?.error?.message ?? `Instagram ${r.status}`);
  return d;
}
const k = (n: number) => n >= 1e6 ? (n / 1e6).toFixed(1).replace(".", ",") + "M" : n >= 1e4 ? (n / 1e3).toFixed(1).replace(".", ",") + "K" : n.toLocaleString("it-IT");
const giornoRoma = (d: Date) => d.toLocaleDateString("it-IT", { timeZone: "Europe/Rome", weekday: "short" }).slice(0, 3).toUpperCase();
const oraRoma = (d: Date) => d.toLocaleTimeString("it-IT", { timeZone: "Europe/Rome", hour: "2-digit", minute: "2-digit" });
const quandoTesto = (d: Date) => {
  const oggi = new Date(), ieri = new Date(Date.now() - 864e5), f = (x: Date) => x.toLocaleDateString("it-IT", { timeZone: "Europe/Rome" });
  return (f(d) === f(oggi) ? "OGGI" : f(d) === f(ieri) ? "IERI" : giornoRoma(d)) + " " + oraRoma(d);
};
/** Il prossimo lunedì alle 12 a Roma (l'orario migliore del mockup), in UTC. */
function prossimoLunedi12(): Date {
  const ora = new Date();
  for (let g = 0; g < 8; g++) {
    const d = new Date(ora.getTime() + g * 864e5);
    const giorno = d.toLocaleDateString("en-GB", { timeZone: "Europe/Rome", weekday: "short" });
    if (giorno !== "Mon") continue;
    const [gg, mm, aa] = d.toLocaleDateString("en-GB", { timeZone: "Europe/Rome" }).split("/").map(Number);
    for (const off of [1, 2]) {                                       // ora solare (+1) o legale (+2)
      const c = new Date(Date.UTC(aa, mm - 1, gg, 12 - off, 0));
      if (oraRoma(c) === "12:00" && c > ora) return c;
    }
  }
  return new Date(ora.getTime() + 7 * 864e5);
}

/** Le bozze di JARVIS per commenti e messaggi (una chiamata sola, modello rapido). */
async function bozze(voci: { tipo: string; testo: string }[]): Promise<string[]> {
  if (!voci.length || !env("ANTHROPIC_API_KEY")) return voci.map(() => "");
  const prompt = `Sei JARVIS e prepari le risposte che King Rusto (@kingrusto, writer di graffiti, custom su denim, stampa 3D, tono diretto, amichevole, breve, italiano) manderà ai suoi follower su Instagram.
Per ogni voce scrivi UNA risposta breve (massimo 2 frasi), naturale, senza hashtag, al massimo un'emoji. Se è una domanda su prezzi o commissioni, invita a scrivere in DM con i dettagli.
Voci:\n${voci.map((v, i) => `${i + 1}. [${v.tipo}] ${v.testo}`).join("\n")}
Rispondi SOLO con un array JSON di stringhe, nello stesso ordine.`;
  try {
    const r = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST", headers: { "x-api-key": env("ANTHROPIC_API_KEY"), "anthropic-version": "2023-06-01", "content-type": "application/json" },
      body: JSON.stringify({ model: env("MODELLO_RAPIDO") || "claude-haiku-5-5", max_tokens: 1200, messages: [{ role: "user", content: prompt }] }),
    });
    const d = await r.json();
    const t = (d.content ?? []).map((c: any) => c.text ?? "").join("");
    const a = JSON.parse(t.match(/\[[\s\S]*\]/)?.[0] ?? "[]");
    return voci.map((_, i) => typeof a[i] === "string" ? a[i] : "");
  } catch { return voci.map(() => ""); }
}

async function stato(t: string, leggero = false) {
  const me = await ig(t, "/me", { fields: "user_id,username,followers_count,media_count,profile_picture_url,account_type" });
  const media = (await ig(t, "/me/media", { fields: "id,caption,media_type,media_product_type,timestamp,like_count,comments_count,permalink", limit: "12" })).data ?? [];
  // REPORT: copertura giorno per giorno (7 giorni), follower guadagnati, interazioni
  const ora = Math.floor(Date.now() / 1000), da = ora - 7 * 86400;
  let giorni: number[] = [], etichette: string[] = [], copertura = 0, nuovi: number | null = null, interazioni: number | null = null;
  try {
    const r = await ig(t, "/me/insights", { metric: "reach", period: "day", since: String(da), until: String(ora) });
    const v = r.data?.[0]?.values ?? [];
    giorni = v.map((x: any) => x.value ?? 0); etichette = v.map((x: any) => giornoRoma(new Date(x.end_time)).slice(0, 1));
    copertura = giorni.reduce((a, b) => a + b, 0);
  } catch { /* metrica non disponibile: resta vuota */ }
  try {
    const r = await ig(t, "/me/insights", { metric: "follower_count", period: "day", since: String(da), until: String(ora) });
    nuovi = (r.data?.[0]?.values ?? []).reduce((a: number, x: any) => a + (x.value ?? 0), 0);
  } catch { /* sotto i 100 follower o non disponibile */ }
  try {
    const r = await ig(t, "/me/insights", { metric: "total_interactions", period: "day", metric_type: "total_value", since: String(da), until: String(ora) });
    interazioni = r.data?.[0]?.total_value?.value ?? null;
  } catch { /* non disponibile */ }
  const top = [...media].filter((m) => new Date(m.timestamp).getTime() > Date.now() - 30 * 864e5)
    .sort((a, b) => (b.like_count ?? 0) + (b.comments_count ?? 0) - (a.like_count ?? 0) - (a.comments_count ?? 0))[0] ?? media[0];
  const tipo = (m: any) => m?.media_product_type === "REELS" ? "REEL" : m?.media_product_type === "STORY" ? "STORIA" : "POST";
  const titolo = (m: any) => (m?.caption ?? "").split("\n")[0].replace(/[<>&"]/g, "").slice(0, 60) || "Senza didascalia";   // va in pagina: niente marcatori

  // POSTA: commenti degli ultimi 5 post (senza risposta del signore) e messaggi diretti
  const posta: any[] = [];
  for (const m of media.slice(0, 5)) {
    if (!m.comments_count) continue;
    try {
      const c = (await ig(t, `/${m.id}/comments`, { fields: "id,text,username,timestamp,replies{username}", limit: "20" })).data ?? [];
      for (const x of c) {
        if (x.username === me.username) continue;
        const risposto = (x.replies?.data ?? []).some((r: any) => r.username === me.username);
        posta.push({ tipo: "commento", id: x.id, chi: x.username, testo: x.text ?? "", su: `${tipo(m) === "REEL" ? "Reel" : "Post"} · ${titolo(m).slice(0, 30)}`, quando: x.timestamp, fatto: risposto });
      }
    } catch { /* commenti non leggibili: si salta quel post */ }
  }
  try {
    const conv = (await ig(t, "/me/conversations", { platform: "instagram", fields: "participants,messages.limit(1){id,message,from,created_time}", limit: "10" })).data ?? [];
    for (const c of conv) {
      const msg = c.messages?.data?.[0]; if (!msg) continue;
      const altro = (c.participants?.data ?? []).find((p: any) => p.username !== me.username);
      if (!altro || msg.from?.username === me.username) continue;           // l'ultimo l'ha scritto il signore: niente da rispondere
      const ore = (Date.now() - new Date(msg.created_time).getTime()) / 36e5;
      posta.push({ tipo: "dm", id: msg.id, a: altro.id, chi: altro.username, testo: msg.message ?? "", su: `Messaggio · ${quandoTesto(new Date(msg.created_time))}`, quando: msg.created_time, scaduto: ore > 24 });
    }
  } catch { /* messaggi non disponibili */ }
  posta.sort((a, b) => new Date(b.quando).getTime() - new Date(a.quando).getTime());
  const daFare = posta.filter((p) => !p.fatto && !p.scaduto).slice(0, 12);
  const b = leggero ? [] : await bozze(daFare.map((p) => ({ tipo: p.tipo, testo: p.testo })));   // l'orologio non le mostra: niente bozze
  daFare.forEach((p, i) => (p.bozza = b[i] ?? ""));

  const { data: coda } = await db.from("social_coda").select("id,quando,formato,didascalia,stato").eq("stato", "programmato").order("quando");
  const { data: imp } = await db.from("social_impostazioni").select("auto_on,parola,testo").eq("id", 1).maybeSingle();
  return {
    profilo: { username: me.username, follower: me.followers_count ?? 0, followerTesto: k(me.followers_count ?? 0), post: me.media_count ?? 0, foto: me.profile_picture_url ?? null, tipo: me.account_type ?? "" },
    report: {
      numeri: [["FOLLOWER", k(me.followers_count ?? 0), nuovi == null ? "statistiche non disponibili" : `${nuovi >= 0 ? "+" : ""}${nuovi} in 7 giorni`],
               ["COPERTURA", copertura ? k(copertura) : "—", "account raggiunti · 7 giorni"],
               ["INTERAZIONI", interazioni == null ? "—" : k(interazioni), "like, commenti, salvataggi"],
               ["POST", String(me.media_count ?? 0), "pubblicati in tutto"]],
      giorni, etichette,
      top: top ? { tipo: tipo(top), titolo: titolo(top), dettaglio: `${k(top.like_count ?? 0)} like · ${top.comments_count ?? 0} commenti` } : null,
      riassunto: `Ultimi 7 giorni, Sir: ${copertura ? k(copertura) + " account raggiunti" : "la copertura non è disponibile"}${nuovi != null ? `, ${nuovi >= 0 ? "+" : ""}${nuovi} follower` : ""}${interazioni != null ? `, ${k(interazioni)} interazioni` : ""}.${top ? ` Il più visto: «${titolo(top)}», ${top.like_count ?? 0} like.` : ""}`,
    },
    posta,
    coda: (coda ?? []).map((c: any) => ({ id: c.id, quando: `${giornoRoma(new Date(c.quando))} ${oraRoma(new Date(c.quando))}`, titolo: (c.didascalia ?? "").split("\n")[0].slice(0, 60) || "Senza didascalia", tipo: c.formato })),
    pubblicati: media.slice(0, 6).map((m: any) => ({ quando: quandoTesto(new Date(m.timestamp)), titolo: titolo(m), tipo: tipo(m) })),
    auto: { on: imp?.auto_on ?? false, parola: imp?.parola ?? "LISTA", testo: imp?.testo ?? "Ecco il link 👉" },
  };
}

/** Pubblica un contenuto già caricato (URL pubblico): crea il contenitore, aspetta che Instagram l'abbia elaborato, pubblica. */
async function pubblicaOra(t: string, formato: string, url: string, mime: string, didascalia: string) {
  const video = mime.startsWith("video/");
  const corpo: Record<string, unknown> = formato === "STORIA" ? { media_type: "STORIES", [video ? "video_url" : "image_url"]: url }
    : video ? { media_type: "REELS", video_url: url, caption: didascalia, share_to_feed: true }   // un video nel feed è un Reel per Instagram
    : { image_url: url, caption: didascalia };
  const c = await ig(t, "/me/media", {}, "POST", corpo);
  for (let i = 0; i < 40; i++) {                                         // i video si elaborano: fino a 2 minuti
    const s = await ig(t, `/${c.id}`, { fields: "status_code" });
    if (s.status_code === "FINISHED" || (!video && !s.status_code)) break;
    if (s.status_code === "ERROR" || s.status_code === "EXPIRED") throw new Error("Instagram non ha accettato il file");
    await new Promise((r) => setTimeout(r, 3000));
  }
  const p = await ig(t, "/me/media_publish", {}, "POST", { creation_id: c.id });
  return p.id as string;
}

async function giro(t: string) {
  const esiti: string[] = [];
  const { data: dovuti } = await db.from("social_coda").select("*").eq("stato", "programmato").lte("quando", new Date().toISOString()).limit(3);
  for (const c of dovuti ?? []) {
    try { const id = await pubblicaOra(t, c.formato, c.media_url, c.mime, c.didascalia ?? ""); await db.from("social_coda").update({ stato: "pubblicato", media_id: id }).eq("id", c.id); esiti.push("pubblicato " + c.id); }
    catch (e) { await db.from("social_coda").update({ stato: "errore", errore: String(e) }).eq("id", c.id); esiti.push("errore " + c.id); }
  }
  const { data: imp } = await db.from("social_impostazioni").select("*").eq("id", 1).maybeSingle();
  if (imp?.auto_on && imp.parola) {
    const media = (await ig(t, "/me/media", { fields: "id,timestamp", limit: "5" })).data ?? [];
    for (const m of media) {
      const c = (await ig(t, `/${m.id}/comments`, { fields: "id,text,username", limit: "50" }).catch(() => ({ data: [] }))).data ?? [];
      for (const x of c) {
        if (!new RegExp(`\\b${imp.parola.replace(/[^\p{L}\p{N}]/gu, "")}\\b`, "iu").test(x.text ?? "")) continue;
        const { data: gia } = await db.from("social_auto_fatti").select("comment_id").eq("comment_id", x.id).maybeSingle();
        if (gia) continue;
        try { await ig(t, "/me/messages", {}, "POST", { recipient: { comment_id: x.id }, message: { text: imp.testo } }); esiti.push("dm a " + x.username); }
        catch (e) { esiti.push("dm non riuscito: " + String(e)); }
        await db.from("social_auto_fatti").insert({ comment_id: x.id });
      }
    }
  }
  return esiti;
}

Deno.serve(async (req) => {
  const segreto = env("JARVIS_TOKEN");
  const daApp = !!segreto && uguali(req.headers.get("x-jarvis-token") ?? "", segreto);
  let daCron = false;
  if (!daApp) {
    const interna = req.headers.get("x-chiave-interna") ?? "";
    const { data } = interna ? await db.rpc("verifica_chiave_interna", { p: interna }) : { data: false };
    daCron = data === true;
  }
  if (!daApp && !daCron) return json({ errore: "non autorizzato" }, 401);
  const c: any = await req.json().catch(() => ({}));
  const t = await token();
  if (!t) return json({ errore: "Instagram non è collegato: manca il token" }, 500);
  try {
    if (c.azione === "giro") return json({ ok: true, esiti: await giro(t) });
    if (c.azione === "stato" && (daApp || daCron)) return json(await stato(t, !!c.leggero));
    if (!daApp) return json({ errore: "non autorizzato" }, 401);
    if (c.azione === "rispondi") {
      const testo = String(c.testo ?? "").trim().slice(0, 1000);
      if (!testo) return json({ errore: "la risposta è vuota" }, 400);
      if (c.tipo === "commento") await ig(t, `/${c.id}/replies`, {}, "POST", { message: testo });
      else await ig(t, "/me/messages", {}, "POST", { recipient: { id: c.a }, message: { text: testo } });
      return json({ ok: true });
    }
    if (c.azione === "pubblica") {
      const formato = ["POST", "STORIA", "REEL"].includes(c.formato) ? c.formato : "POST";
      const mime = String(c.mime ?? "image/jpeg"), est = mime.includes("mp4") ? "mp4" : mime.includes("quicktime") ? "mov" : mime.includes("png") ? "png" : "jpg";
      const byte = Uint8Array.from(atob(String(c.media ?? "")), (x) => x.charCodeAt(0));
      if (!byte.length) return json({ errore: "manca il contenuto" }, 400);
      const nome = `${Date.now()}-${crypto.randomUUID().slice(0, 8)}.${est}`;
      const up = await fetch(`${URL_DB}/storage/v1/object/${BUCKET}/${nome}`, { method: "POST", headers: { apikey: KEY, Authorization: `Bearer ${KEY}`, "content-type": mime }, body: byte });
      if (!up.ok) return json({ errore: "caricamento non riuscito" }, 502);
      const url = `${URL_DB}/storage/v1/object/public/${BUCKET}/${nome}`;
      const didascalia = String(c.didascalia ?? "").slice(0, 2200);
      if (c.quando && c.quando !== "ORA") {
        const quando = prossimoLunedi12();
        await db.from("social_coda").insert({ quando: quando.toISOString(), formato, didascalia, media_url: url, mime, stato: "programmato" });
        return json({ ok: true, programmato: `${giornoRoma(quando)} ${oraRoma(quando)}` });
      }
      const id = await pubblicaOra(t, formato, url, mime, didascalia);
      return json({ ok: true, pubblicato: id });
    }
    if (c.azione === "annulla") { await db.from("social_coda").update({ stato: "annullato" }).eq("id", c.id); return json({ ok: true }); }
    if (c.azione === "auto") {
      await db.from("social_impostazioni").upsert({ id: 1, auto_on: !!c.on, parola: String(c.parola ?? "LISTA").toUpperCase().slice(0, 20), testo: String(c.testo ?? "").slice(0, 900) });
      return json({ ok: true });
    }
    return json({ errore: "azione sconosciuta" }, 400);
  } catch (e) { return json({ errore: String(e instanceof Error ? e.message : e) }, 502); }
});
