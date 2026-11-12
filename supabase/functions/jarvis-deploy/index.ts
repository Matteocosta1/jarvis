// jarvis-deploy: ricompone il codice di una funzione dalle parti salvate in jarvis_deploy_parti e lo pubblica
// con l'API di gestione di Supabase. Serve a caricare il cervello a pezzi piccoli invece che in un colpo solo.
// Segreti: JARVIS_SUPABASE_TOKEN (token personale), JARVIS_TOKEN (la parola d'ordine, nell'header x-jarvis-token), GITHUB_TOKEN (con ?da=github).
// Uso: ?funzione=jarvis&da=github[&verifica=1][&sha=<impronta attesa>] e la chiave (header x-jarvis-token o un ?codice= usa-e-getta).
import { createClient } from "npm:@supabase/supabase-js@2";

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
const REF = (Deno.env.get("SUPABASE_URL") || "").match(/https:\/\/([a-z0-9]+)\.supabase\.co/)?.[1] || "";
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { "content-type": "application/json" } });

function uguali(a: string, b: string) {
  if (!a || a.length !== b.length) return false;
  let x = 0; for (let k = 0; k < a.length; k++) x |= a.charCodeAt(k) ^ b.charCodeAt(k);
  return x === 0;
}

Deno.serve(async (req) => {
  const segreto = Deno.env.get("JARVIS_TOKEN") ?? "";
  const url = new URL(req.url);
  const dato = req.headers.get("x-jarvis-token") ?? "";   // solo nell'header: mai nell'indirizzo, dove finirebbe nei log
  // in alternativa: un codice usa-e-getta (tabella jarvis_deploy_codici, scade da solo). Si consuma subito, in un colpo solo:
  // due richieste con lo stesso codice non passano mai entrambe.
  const codice = url.searchParams.get("codice") ?? "";
  let conCodice = false;
  if (/^[a-f0-9]{32,64}$/.test(codice)) {
    const { data: c } = await db.from("jarvis_deploy_codici").delete().eq("codice", codice).gt("scade", new Date().toISOString()).select("codice");
    conCodice = (c?.length ?? 0) > 0;
  }
  if (!conCodice && (!segreto || !uguali(dato, segreto))) return json({ errore: "parola d'ordine errata" }, 401);
  const token = Deno.env.get("JARVIS_SUPABASE_TOKEN") ?? "";
  if (!token) return json({ errore: "manca JARVIS_SUPABASE_TOKEN" }, 500);

  // pulizia: ?elimina=<funzione> toglie una funzione di JARVIS non più usata (mai quelle vive)
  const elimina = (url.searchParams.get("elimina") ?? "").replace(/[^a-z0-9\-]/g, "");
  if (elimina) {
    if (!elimina.startsWith("jarvis-") || PROTETTE.has(elimina)) return json({ errore: `«${elimina}» non si può eliminare da qui` }, 400);
    return json(await togli(elimina, token));
  }
  const funzione = (url.searchParams.get("funzione") || "jarvis").replace(/[^a-z0-9\-]/g, "");
  const verifica = url.searchParams.get("verifica") === "1";
  const files: Record<string, string> = {};
  let data: any[] = [];
  if (url.searchParams.get("da") === "github") {
    // il sorgente si prende direttamente dal repository privato di JARVIS (con il token GitHub già nei segreti)
    const repo = "Matteocosta1/jarvis";   // sempre e solo il repository di JARVIS
    const ref = (url.searchParams.get("ref") || "main").replace(/[^A-Za-z0-9._\/-]/g, "");
    const r = await fetch(`https://api.github.com/repos/${repo}/contents/supabase/functions/${funzione}/index.ts?ref=${ref}`, {
      headers: { authorization: `Bearer ${Deno.env.get("GITHUB_TOKEN") ?? ""}`, accept: "application/vnd.github.raw", "user-agent": "jarvis-deploy" },
    });
    if (!r.ok) return json({ errore: `GitHub ${r.status}: ${(await r.text()).slice(0, 200)}` }, 502);
    files["index.ts"] = await r.text();
    data = [{ file: "index.ts" }];
  } else {
    const q = await db.from("jarvis_deploy_parti").select("file, parte, contenuto").eq("funzione", funzione).order("file").order("parte");
    if (q.error) return json({ errore: q.error.message }, 500);
    data = q.data ?? [];
    if (!data.length) return json({ errore: "nessuna parte salvata per " + funzione }, 400);
    for (const p of data) files[p.file] = (files[p.file] ?? "") + p.contenuto;
  }
  const riassunto: Record<string, { byte: number; sha256: string }> = {};
  for (const [nome, testo] of Object.entries(files)) {
    const h = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(testo));
    riassunto[nome] = { byte: new TextEncoder().encode(testo).length, sha256: [...new Uint8Array(h)].map((b) => b.toString(16).padStart(2, "0")).join("") };
  }
  if (verifica) return json({ funzione, file: riassunto, parti: data.length });
  // sicurezza in più: se si indica l'impronta attesa, si pubblica solo se il file è esattamente quello
  const attesa = url.searchParams.get("sha") ?? "";
  if (attesa && riassunto["index.ts"]?.sha256 !== attesa) return json({ errore: "impronta diversa da quella attesa: non pubblico", file: riassunto }, 409);

  // Prova generale: prima si pubblica una copia («<funzione>-prova») e la si mette alla prova; solo se passa si sostituisce quella vera.
  // Il cervello risponde anche a tre domande vere (pochi centesimi); le altre funzioni devono solo accendersi e difendersi.
  if (url.searchParams.get("salta_prova") !== "1") {
    const copia = await pubblica(`${funzione}-prova`, files, token);
    if (!copia.ok) return json({ errore: `la copia di prova non si pubblica: ${copia.errore}`, file: riassunto }, 502);
    const esito = funzione === "jarvis" ? await provaCervello(`${funzione}-prova`) : await provaAccensione(`${funzione}-prova`);
    await togli(`${funzione}-prova`, token);   // la copia di prova non resta in giro, comunque sia andata
    if (!esito.ok) return json({ errore: "prova generale NON superata: la funzione vera resta quella di prima", prova: esito.dettagli, file: riassunto }, 409);
  }
  const vera = await pubblica(funzione, files, token);
  if (!vera.ok) return json({ errore: `deploy ${vera.errore}` }, 502);
  return json({ ok: true, funzione, versione: vera.versione, stato: vera.stato, file: riassunto, prova: url.searchParams.get("salta_prova") === "1" ? "saltata" : "superata" });
});

const PROTETTE = new Set(["jarvis", "jarvis-deploy", "jarvis-bea-sos", "jarvis-allarme", "jarvis-briefing", "jarvis-ascolto", "jarvis-systems"]);

async function togli(slug: string, token: string) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/functions/${slug}`, { method: "DELETE", headers: { authorization: `Bearer ${token}` } });
  const t = await r.text();
  return r.ok || r.status === 404 ? { ok: true, eliminata: slug } : { ok: false, errore: `${r.status}: ${t.slice(0, 200)}` };
}

async function pubblica(slug: string, files: Record<string, string>, token: string) {
  const form = new FormData();
  form.append("metadata", JSON.stringify({ name: slug, entrypoint_path: "index.ts", verify_jwt: false }));
  for (const [nome, testo] of Object.entries(files)) form.append("file", new Blob([testo], { type: "text/typescript" }), nome);
  const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/functions/deploy?slug=${slug}`, {
    method: "POST", headers: { authorization: `Bearer ${token}` }, body: form,
  });
  const testo = await r.text();
  if (!r.ok) return { ok: false, errore: `${r.status}: ${testo.slice(0, 400)}` };
  let esito: any = {}; try { esito = JSON.parse(testo); } catch { /* testo semplice */ }
  return { ok: true, versione: esito.version ?? null, stato: esito.status ?? null };
}

const BASE = Deno.env.get("SUPABASE_URL") ?? "";

/// La funzione appena pubblicata si accende e respinge chi non ha la chiave (401/405): non è andata in crash.
async function provaAccensione(slug: string) {
  let ultimo = "";
  for (let i = 0; i < 6; i++) {   // la copia nuova può metterci qualche secondo ad arrivare
    try {
      const r = await fetch(`${BASE}/functions/v1/${slug}`, { method: "POST", headers: { "content-type": "application/json" }, body: "{}", signal: AbortSignal.timeout(20_000) });
      await r.body?.cancel();
      if (r.status === 401 || r.status === 405) return { ok: true, dettagli: [`risponde ${r.status}`] };
      ultimo = `risponde ${r.status}`;
    } catch (e) { ultimo = (e as Error).message; }
    await new Promise((ok) => setTimeout(ok, 3000));
  }
  return { ok: false, dettagli: [ultimo] };
}

/// Tre domande vere al cervello di prova: una semplice, una con uno strumento (meteo), una che legge il database (Bea);
/// e due prove del dialogo (11 nov): la conversazione di ieri non entra, la risposta anticipata sospesa riparte e finisce.
async function provaCervello(slug: string) {
  const acceso = await provaAccensione(slug);
  if (!acceso.ok) return acceso;
  const domande = [
    "Prova generale del sistema: rispondi soltanto «Tutto in ordine».",
    "Prova generale: che tempo farà domani a Milano? Una frase sola.",
    "Prova generale: guarda la scheda di Bea e dimmi solo quante date ci sono segnate.",
  ];
  const esiti = await Promise.all(domande.map(async (q) => {
    try {
      const r = await fetch(`${BASE}/functions/v1/${slug}`, {
        method: "POST", signal: AbortSignal.timeout(70_000),
        headers: { "content-type": "application/json", "x-jarvis-token": Deno.env.get("JARVIS_TOKEN") ?? "" },
        body: JSON.stringify({ messaggi: [{ role: "user", content: q }], dispositivo: "iphone", prova_generale: true }),
      });
      if (!r.ok) return { ok: false, d: `${q.slice(16, 50)}… → HTTP ${r.status}` };
      const righe = (await r.text()).split("\n").filter(Boolean).map((l) => { try { return JSON.parse(l); } catch { return null; } });
      const errore = righe.find((x) => x?.t === "errore");
      const fine = righe.find((x) => x?.t === "fine");
      const testo = String(fine?.testo ?? "").trim();
      const ok = !errore && !!testo && !/mi sono perso|non ho trovato nulla da dire|fiato che ho/i.test(testo);
      return { ok, d: `${q.slice(16, 50)}… → ${errore ? `errore: ${String(errore.tecnico ?? errore.d).slice(0, 120)}` : testo.slice(0, 120) || "nessuna risposta"}` };   // il dettaglio tecnico, non la frase per il signore
    } catch (e) {
      return { ok: false, d: `${q.slice(16, 50)}… → ${(e as Error).message.slice(0, 120)}` };
    }
  }));
  // 11 nov (#15): due prove del dialogo, oltre alle tre domande; 12 nov (P7): le prove del dialogo umano (le «avvisi» non fermano
  // la pubblicazione: un modello può sbagliare una volta un giudizio; le altre sì)
  const dialogo = await Promise.all([provaFinestraVecchia(slug), provaAnticipo(slug)]);
  const umano = await provaDialogo(slug);
  const tutte = [...esiti, ...dialogo, ...umano.filter((e) => e.bloccante)];
  const avvisi = umano.filter((e) => !e.bloccante);
  return { ok: tutte.every((e) => e.ok), dettagli: [...tutte.map((e) => `${e.ok ? "✓" : "✗"} ${e.d}`), ...avvisi.map((e) => `${e.ok ? "✓" : "⚠"} ${e.d}`)] };
}

/// Una richiesta al cervello di prova: le righe NDJSON della risposta.
async function chiedi(slug: string, corpo: Record<string, unknown>): Promise<any[]> {
  const r = await fetch(`${BASE}/functions/v1/${slug}`, {
    method: "POST", signal: AbortSignal.timeout(70_000),
    headers: { "content-type": "application/json", "x-jarvis-token": Deno.env.get("JARVIS_TOKEN") ?? "" },
    body: JSON.stringify({ dispositivo: "iphone", prova_generale: true, ...corpo }),
  });
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  return (await r.text()).split("\n").filter(Boolean).map((l) => { try { return JSON.parse(l); } catch { return null; } });
}

/// Le battute di più di 8 ore fa non entrano nella conversazione (il caso Pierpaolo): un arrivo di ieri non è un arrivo di adesso.
async function provaFinestraVecchia(slug: string) {
  const ora = Date.now(), ieri = ora - 26 * 3600_000;
  try {
    const righe = await chiedi(slug, { messaggi: [
      { role: "user", content: "È appena arrivato Gualtierino, salutalo.", quando: ieri },
      { role: "assistant", content: "Benvenuto, Gualtierino.", quando: ieri + 4000 },
      { role: "user", content: "Prova generale: chi è appena arrivato qui? Se non lo sai dillo in una frase.", quando: ora },
    ] });
    const errore = righe.find((x) => x?.t === "errore"), testo = String(righe.find((x) => x?.t === "fine")?.testo ?? "").trim();
    const ok = !errore && !!testo && !/gualtierin/i.test(testo);
    return { ok, d: `finestra di ieri → ${errore ? `errore: ${String(errore.tecnico ?? errore.d).slice(0, 120)}` : testo.slice(0, 120) || "nessuna risposta"}` };
  } catch (e) { return { ok: false, d: `finestra di ieri → ${(e as Error).message.slice(0, 120)}` }; }
}

/// La risposta anticipata: con uno strumento si ferma («sospeso»), poi l'app la fa ripartire (continua con «esegui») e arriva in fondo.
async function provaAnticipo(slug: string) {
  try {
    const righe = await chiedi(slug, { a_voce: true, anticipo: true,
      messaggi: [{ role: "user", content: "Prova generale: che tempo fa adesso a Milano? Una frase sola.", quando: Date.now() }] });
    const errore = righe.find((x) => x?.t === "errore");
    if (errore) return { ok: false, d: `anticipo → errore: ${String(errore.tecnico ?? errore.d).slice(0, 120)}` };
    if (righe.some((x) => x?.t === "no_anticipo")) return { ok: true, d: "anticipo → spento (ANTICIPO=off)" };
    let fine = righe.find((x) => x?.t === "fine");
    const sosp = righe.find((x) => x?.t === "sospeso");
    if (!fine && sosp) {
      const dopo = await chiedi(slug, { messaggi: [], continua: { lavoro: sosp.lavoro, modello: sosp.modello, azioni: sosp.azioni, detto: sosp.detto, esegui: true } });
      const e2 = dopo.find((x) => x?.t === "errore");
      if (e2) return { ok: false, d: `anticipo ripreso → errore: ${String(e2.tecnico ?? e2.d).slice(0, 120)}` };
      fine = dopo.find((x) => x?.t === "fine");
    }
    const testo = String(fine?.testo ?? "").trim();
    return { ok: !!testo, d: `anticipo${sosp ? " (sospeso e ripreso)" : ""} → ${testo.slice(0, 120) || "nessuna risposta"}` };
  } catch (e) { return { ok: false, d: `anticipo → ${(e as Error).message.slice(0, 120)}` }; }
}

/// 12 nov (P7, revisione del dialogo): il dialogo umano. Frase a metà → «[aspetto]»; domanda intera → risposta (mai «aspetto»);
/// frase detta a un'altra persona dal microfono sempre acceso → «[silenzio]»; con «Jarvis» dentro → mai silenzio; frase a metà e poi
/// silenzio (dopo_aspetto) → risposta o domanda sul punto; «Sir» mai in due risposte brevi di fila.
async function provaDialogo(slug: string): Promise<{ ok: boolean; d: string; bloccante: boolean }[]> {
  const ora = Date.now();
  type Caso = { nome: string; bloccante: boolean; atteso: "aspetto" | "silenzio" | "risposta" | "senza_sir"; corpo: Record<string, unknown> };
  const casi: Caso[] = [
    { nome: "frase a metà → aspetto", bloccante: false, atteso: "aspetto",
      corpo: { a_voce: true, capisce_aspetto: true, messaggi: [{ role: "user", content: "Gli ho detto che", quando: ora }] } },
    { nome: "domanda intera → risposta", bloccante: true, atteso: "risposta",
      corpo: { a_voce: true, capisce_aspetto: true, messaggi: [{ role: "user", content: "Prova generale: quanto fa due più due? Una parola.", quando: ora }] } },
    { nome: "a un'altra persona → silenzio", bloccante: false, atteso: "silenzio",
      corpo: { a_voce: true, capisce_silenzio: true, ascolto_libero: true, messaggi: [{ role: "user", content: "Bea, mi passi il sale per favore?", quando: ora }] } },
    { nome: "con «Jarvis» → mai silenzio", bloccante: true, atteso: "risposta",
      corpo: { a_voce: true, capisce_silenzio: true, ascolto_libero: true, messaggi: [{ role: "user", content: "Jarvis, prova generale: quanto fa tre più tre? Una parola.", quando: ora }] } },
    { nome: "frase a metà poi silenzio → domanda sul punto", bloccante: true, atteso: "risposta",
      corpo: { a_voce: true, capisce_aspetto: true, dopo_aspetto: true, messaggi: [{ role: "user", content: "Gli ho detto che", quando: ora }] } },
    { nome: "«Sir» non in due risposte brevi di fila", bloccante: false, atteso: "senza_sir",
      corpo: { messaggi: [
        { role: "user", content: "Accendi la torcia.", quando: ora - 20_000 },
        { role: "assistant", content: "Accesa, Sir.", quando: ora - 18_000 },
        { role: "user", content: "Grazie.", quando: ora },
      ] } },
  ];
  return await Promise.all(casi.map(async (c) => {
    try {
      const righe = await chiedi(slug, c.corpo);
      const errore = righe.find((x) => x?.t === "errore");
      if (errore) return { ok: false, bloccante: c.bloccante, d: `${c.nome} → errore: ${String(errore.tecnico ?? errore.d).slice(0, 120)}` };
      const segnale = righe.find((x) => x?.t === "aspetto" || x?.t === "silenzio")?.t as string | undefined;
      const testo = String(righe.find((x) => x?.t === "fine")?.testo ?? "").trim();
      const visto = segnale ? `«${segnale}»` : testo.slice(0, 100) || "nessuna risposta";
      const ok = c.atteso === "aspetto" || c.atteso === "silenzio" ? segnale === c.atteso
        : c.atteso === "senza_sir" ? !segnale && !!testo && !/\bsir\b/i.test(testo)
        : !segnale && !!testo && !/^\s*\[\s*(aspett|silenz)/i.test(testo);
      return { ok, bloccante: c.bloccante, d: `${c.nome} → ${visto}` };
    } catch (e) { return { ok: false, bloccante: c.bloccante, d: `${c.nome} → ${(e as Error).message.slice(0, 120)}` }; }
  }));
}
