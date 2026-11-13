// friday-prova — la «Prova vera» dell'Armadio di FRIDAY (13 nov 2026).
// Veste una foto di Bea con le foto dei suoi capi, con il modello d'immagini di Google Gemini:
//   Normale → gemini-3.1-flash-image-preview (1K, circa 0,07 $)   ·   Alta → gemini-3-pro-image-preview (2K, circa 0,14 $)
// Le foto arrivano a pezzi nella tabella friday_foto_parti (impronta SHA-256); la prova è una riga di friday_prova.
// La avvia friday_prova_avvia() con pg_net dopo il commit: qui si risponde subito (202) e si lavora in sottofondo.
// Il risultato (PNG di Gemini) va nel bucket privato «friday-prove»; per la pagina se ne fa un'anteprima WebP leggera
// con le trasformazioni d'immagine di Supabase Storage (e una miniatura per i Look).
// «Dalle tue foto» (13 nov): da una foto di Bea, Claude riconosce i capi che indossa e Gemini li rifà come foto prodotto su fondo
// bianco; ogni capo finisce in friday_capi (miniatura WebP per il catalogo) e la sua foto grande in friday_foto_parti (per la Prova vera).
// Segreti: GEMINI_API_KEY (Google AI Studio, con fatturazione), ANTHROPIC_API_KEY. Parola d'ordine: friday_config.token (header x-friday-token).
import { createClient } from "npm:@supabase/supabase-js@2";
import { decodeBase64, encodeBase64 } from "jsr:@std/encoding@1/base64";

declare const EdgeRuntime: { waitUntil(p: Promise<unknown>): void };

const URL_SB = Deno.env.get("SUPABASE_URL")!;
const CHIAVE_SB = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const db = createClient(URL_SB, CHIAVE_SB, { auth: { persistSession: false } });
const BUCKET = "friday-prove";

// prezzi Google (nov 2026, in dollari): immagine in uscita a prezzo fisso, più i token in entrata e quelli di ragionamento
const MODELLI = {
  normale: { catena: ["gemini-3.1-flash-image-preview", "gemini-2.5-flash-image"], misura: "1K", immagine: 0.067, ingresso: 0.5, uscita: 3 },
  alta: { catena: ["gemini-3-pro-image-preview", "gemini-3.1-flash-image-preview"], misura: "2K", immagine: 0.134, ingresso: 2, uscita: 12 },
} as const;
const FORMATI = ["1:1", "2:3", "3:4", "4:5", "9:16"];

const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { "content-type": "application/json" } });
function uguali(a: string, b: string) {
  if (!a || a.length !== b.length) return false;
  let x = 0; for (let k = 0; k < a.length; k++) x |= a.charCodeAt(k) ^ b.charCodeAt(k);
  return x === 0;
}
let tokenMemo: { t: number; v: string } | null = null;
async function tokenFriday() {
  const env = Deno.env.get("FRIDAY_TOKEN") ?? "";
  if (env) return env;
  if (tokenMemo && Date.now() - tokenMemo.t < 5 * 60_000) return tokenMemo.v;
  const { data } = await db.from("friday_config").select("valore").eq("chiave", "token").maybeSingle();
  tokenMemo = { t: Date.now(), v: String(data?.valore ?? "") };
  return tokenMemo.v;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ errore: "metodo non ammesso" }, 405);
  const segreto = await tokenFriday();
  if (!segreto || !uguali(req.headers.get("x-friday-token") ?? "", segreto)) return json({ errore: "parola d'ordine errata" }, 401);
  let corpo: any;
  try { corpo = await req.json(); } catch { return json({ errore: "richiesta non valida" }, 400); }
  if (typeof corpo?.prova === "string" && /^[0-9a-f-]{36}$/.test(corpo.prova)) {
    EdgeRuntime.waitUntil(lavora(corpo.prova));
    return json({ ok: true }, 202);
  }
  if (typeof corpo?.estrai === "string" && /^[0-9a-f-]{36}$/.test(corpo.estrai)) {
    EdgeRuntime.waitUntil(estrai(corpo.estrai));
    return json({ ok: true }, 202);
  }
  if (typeof corpo?.elimina_file === "string" && /^[0-9a-f-]{36}\.(png|jpg|webp)$/.test(corpo.elimina_file)) {
    const { error } = await db.storage.from(BUCKET).remove([corpo.elimina_file]);
    return json({ ok: !error, errore: error?.message });
  }
  if (corpo?.campione && typeof corpo.campione === "object") {               // collaudo: un'immagine inventata (persona o capo), mai una foto vera
    EdgeRuntime.waitUntil(campione(corpo.campione));
    return json({ ok: true }, 202);
  }
  if (corpo?.diagnosi === true) {
    const { data: b } = await db.storage.getBucket(BUCKET);
    return json({ gemini: !!Deno.env.get("GEMINI_API_KEY"), bucket: !!b });
  }
  return json({ errore: "niente da fare" }, 400);
});

/* ───────────── la prova ───────────── */
const RUOLI: Record<string, [string, string]> = {
  sopra: ["TOP", "a top for the upper body (t-shirt, shirt, blouse, sweater or knit)"],
  sotto: ["BOTTOM", "a bottom for the lower body (trousers, jeans or skirt)"],
  vestito: ["DRESS", "a one-piece dress that replaces both her top and her bottom"],
  giacca: ["OUTERWEAR", "a jacket or coat worn over her other clothes"],
  scarpe: ["SHOES", "a pair of shoes, worn on both feet"],
  borsa: ["BAG", "a bag, carried in her hand or on her shoulder the way that bag is naturally carried"],
};
const pulisci = (s: unknown, n = 80) => String(s ?? "").replace(/[\u0000-\u001f"<>]/g, " ").replace(/\s+/g, " ").trim().slice(0, n);

function istruzioni(r: any, capi: any[]) {
  const ruoliUsati = new Set(capi.map((c) => c.ruolo));
  const righe = capi.map((c, k) => {
    const [nome, cosa] = RUOLI[c.ruolo] ?? ["GARMENT", "a garment"];
    const chi = [pulisci(c.nome, 40), pulisci(c.brand, 30), pulisci(c.colore, 30)].filter(Boolean).join(", ");
    const fonte = c.disegno
      ? "This image is only a simple drawing: render it as a real, photographed garment of that type, colour and shape."
      : "This is a photo of the real garment.";
    return `- IMAGE ${k + 2} is the ${nome}: ${cosa}${chi ? ` (${chi})` : ""}. ${fonte}`;
  });
  const come: string[] = [];
  const s = r.come ?? {};
  if (s.dentro === true && ruoliUsati.has("sopra") && ruoliUsati.has("sotto")) come.push("the top is tucked into the bottom");
  if (s.dentro === false && ruoliUsati.has("sopra") && ruoliUsati.has("sotto")) come.push("the top is worn loose over the bottom, not tucked in");
  if (s.aperta === true && ruoliUsati.has("giacca")) come.push("the outerwear is worn open");
  if (s.aperta === false && ruoliUsati.has("giacca")) come.push("the outerwear is closed (buttoned or zipped)");
  const nota = pulisci(r.nota, 200);
  const resta: string[] = [];
  if (!ruoliUsati.has("scarpe")) resta.push("her own shoes");
  if (!ruoliUsati.has("borsa")) resta.push("whatever she is holding or carrying");
  return [
    "Virtual try-on: a photorealistic fashion photo edit.",
    "IMAGE 1 shows Bea, a real woman. She stays exactly herself: identical face and facial features, expression, hair, skin tone, body shape, proportions and height, the same pose and hands, the same camera angle, framing, background and lighting. Only her clothes change.",
    "Dress Bea in these garments from her own wardrobe:",
    ...righe,
    "Reproduce every garment faithfully: the same colour and shade, fabric and texture, pattern and print scale, logos and lettering, buttons, zips, pockets, seams, collar, sleeve length and overall length as in its image.",
    "Make the fit realistic for her body and pose, with natural drape, folds, creases, shadows and contact with the body, lit exactly like the scene.",
    "Where a garment covers more of the body than her current clothes (long sleeves over bare arms, a longer skirt or trousers), draw it completely and naturally.",
    resta.length ? `Everything she wears that is not listed above stays exactly as it is, including ${resta.join(" and ")}.` : "Everything she wears that is not listed above stays exactly as it is.",
    come.length ? `Styling: ${come.join("; ")}.` : "",
    nota ? `Bea's styling note (in Italian): "${nota}".` : "",
    "Return one single photograph with the same framing as IMAGE 1, with her whole body visible from head to toe.",
  ].filter(Boolean).join("\n");
}

async function caricaFoto(impronte: string[]) {
  const uniche = [...new Set(impronte)];
  const { data, error } = await db.from("friday_foto_parti").select("hash, parte, tot, mime, dati").in("hash", uniche).order("hash").order("parte");
  if (error) throw new Error("foto non lette: " + error.message);
  const foto = new Map<string, { mime: string; dati: string }>();
  for (const h of uniche) {
    const pezzi = (data ?? []).filter((p: any) => p.hash === h);
    if (!pezzi.length || pezzi.length !== pezzi[0].tot) throw new Error("una foto è arrivata a metà: riprova");
    foto.set(h, { mime: pezzi[0].mime, dati: pezzi.map((p: any) => p.dati).join("") });
  }
  return foto;
}

/// Chiama Gemini con la catena di modelli (se il primo non esiste più si passa al successivo).
async function gemini(catena: readonly string[], corpo: (modello: string, ragiona: boolean) => unknown) {
  const chiave = Deno.env.get("GEMINI_API_KEY") ?? "";
  if (!chiave) throw new Error("manca la chiave Google: GEMINI_API_KEY nei segreti di Supabase");
  let ultimo = "";
  let ragiona = true;                                                     // se il modello rifiuta il ragionamento, si riprova senza
  for (const modello of catena) {
    for (let tentativo = 0; tentativo < 3; tentativo++) {
      let r: Response;
      try {
        r = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${modello}:generateContent`, {
          method: "POST", signal: AbortSignal.timeout(150_000),
          headers: { "x-goog-api-key": chiave, "content-type": "application/json" },
          body: JSON.stringify(corpo(modello, ragiona)),
        });
      } catch (e) { ultimo = `Google non risponde (${(e as Error).message})`; continue; }
      if (r.ok) return { modello, d: await r.json() };
      const testo = (await r.text().catch(() => "")).slice(0, 400);
      if (r.status === 404) { ultimo = `modello ${modello} non disponibile`; break; }
      if (r.status === 400 && /thinking/i.test(testo) && ragiona) { ultimo = testo; ragiona = false; continue; }
      if (r.status === 401 || r.status === 403) throw new Error("la chiave Google non è valida o non ha la fatturazione attiva");
      if (r.status === 429) throw new Error("Google: troppe richieste o credito finito, riprova tra un minuto");
      if (r.status >= 500 && tentativo < 2) { ultimo = `Google ${r.status}`; await new Promise((ok) => setTimeout(ok, 1500)); continue; }
      throw new Error(`Google ${r.status}: ${testo}`);
    }
  }
  throw new Error(ultimo || "Google non ha risposto");
}

/// L'immagine finale (non i «pensieri») e il testo che l'accompagna; altrimenti il motivo del rifiuto.
function immagineDi(d: any) {
  const c = d?.candidates?.[0];
  const parti: any[] = c?.content?.parts ?? [];
  const img = [...parti].reverse().find((p) => (p.inlineData?.data || p.inline_data?.data) && !p.thought);
  const testo = parti.filter((p) => typeof p.text === "string" && !p.thought).map((p) => p.text).join(" ").trim();
  if (img) { const x = img.inlineData ?? img.inline_data; return { dati: String(x.data), mime: String(x.mimeType ?? x.mime_type ?? "image/png"), testo }; }
  const motivo = d?.promptFeedback?.blockReason || c?.finishReason || "";
  if (/SAFETY|PROHIBITED|BLOCK/i.test(motivo)) throw new Error("Google ha bloccato questa foto per i suoi filtri: prova con un'altra foto di base");
  throw new Error(testo ? `nessuna immagine: ${testo.slice(0, 200)}` : `nessuna immagine (${motivo || "motivo sconosciuto"})`);
}

/// Anteprima leggera dallo Storage (WebP se possibile): null se le trasformazioni non sono disponibili.
async function rendi(percorso: string, larghezza: number, qualita: number) {
  try {
    const r = await fetch(`${URL_SB}/storage/v1/render/image/authenticated/${BUCKET}/${percorso}?width=${larghezza}&quality=${qualita}&resize=contain`, {
      headers: { authorization: `Bearer ${CHIAVE_SB}`, apikey: CHIAVE_SB, accept: "image/webp,image/jpeg;q=0.9,*/*;q=0.5" },
      signal: AbortSignal.timeout(25_000),
    });
    if (!r.ok) return null;
    const b = new Uint8Array(await r.arrayBuffer());
    if (b.length < 200) return null;
    return { mime: (r.headers.get("content-type") ?? "image/webp").split(";")[0], b64: encodeBase64(b) };
  } catch { return null; }
}
function misurePng(b: Uint8Array) {
  if (b.length > 24 && b[0] === 0x89 && b[1] === 0x50) {
    const v = new DataView(b.buffer, b.byteOffset); return { w: v.getUint32(16), h: v.getUint32(20) };
  }
  return { w: null, h: null };
}

async function lavora(id: string) {
  const t0 = Date.now();
  const segna = (campi: Record<string, unknown>) => db.from("friday_prova").update(campi).eq("id", id);
  try {
    const { data: p, error } = await db.from("friday_prova").select("id, qualita, richiesta").eq("id", id).maybeSingle();
    if (error || !p) throw new Error("prova non trovata");
    await segna({ stato: "in_corso" });
    const r = p.richiesta ?? {};
    const capi: any[] = (Array.isArray(r.capi) ? r.capi : []).filter((c: any) => typeof c?.hash === "string").slice(0, 6);
    if (!capi.length) throw new Error("nessun capo scelto");
    const foto = await caricaFoto([String(r.bea), ...capi.map((c) => c.hash)]);
    const M = p.qualita === "alta" ? MODELLI.alta : MODELLI.normale;
    const formato = FORMATI.includes(r.formato) ? r.formato : "3:4";
    const parti: any[] = [{ text: istruzioni(r, capi) }];
    const bea = foto.get(String(r.bea))!;
    parti.push({ text: "IMAGE 1 — Bea:" }, { inlineData: { mimeType: bea.mime, data: bea.dati } });
    capi.forEach((c, k) => {
      const f = foto.get(c.hash)!;
      parti.push({ text: `IMAGE ${k + 2} — ${(RUOLI[c.ruolo] ?? ["GARMENT"])[0]}:` }, { inlineData: { mimeType: f.mime, data: f.dati } });
    });
    const { modello, d } = await gemini(M.catena, (mod, ragiona) => {
      const flash = mod.includes("flash");
      return {
        contents: [{ role: "user", parts: parti }],
        generationConfig: {
          responseModalities: ["TEXT", "IMAGE"],
          imageConfig: { aspectRatio: formato, ...(mod.startsWith("gemini-2.5") ? {} : { imageSize: M.misura }) },
          ...(flash && ragiona && !mod.startsWith("gemini-2.5") ? { thinkingConfig: { thinkingLevel: "high" } } : {}),
        },
      };
    });
    const img = immagineDi(d);
    const u = d?.usageMetadata ?? {};
    const costo = M.immagine + (Number(u.promptTokenCount) || 0) * M.ingresso / 1e6 + (Number(u.thoughtsTokenCount) || 0) * M.uscita / 1e6;
    const byte = decodeBase64(img.dati);
    const est = img.mime.includes("jpeg") ? "jpg" : img.mime.includes("webp") ? "webp" : "png";
    const percorso = `${id}.${est}`;
    const su = await db.storage.from(BUCKET).upload(percorso, byte, { contentType: img.mime, upsert: true });
    const anteprima = su.error ? null : await rendi(percorso, 900, 82);
    const mini = su.error ? null : await rendi(percorso, 240, 70);
    const { w, h } = misurePng(byte);
    await segna({
      stato: "pronta", modello, costo_usd: Math.round(costo * 10000) / 10000, ms: Date.now() - t0, larghezza: w, altezza: h,
      mime: anteprima?.mime ?? img.mime, anteprima: anteprima?.b64 ?? img.dati, mime_mini: mini?.mime ?? null, miniatura: mini?.b64 ?? null,
      file: su.error ? null : percorso, testo_modello: img.testo ? img.testo.slice(0, 500) : null, finita: new Date().toISOString(),
    });
    await db.from("friday_consumi").insert({ servizio: "prova", modello, token_in: Number(u.promptTokenCount) || 0,
      token_out: (Number(u.candidatesTokenCount) || 0) + (Number(u.thoughtsTokenCount) || 0), ms_totale: Date.now() - t0, esito: "ok" });
  } catch (e) {
    const msg = (e as Error).message || "errore";
    await segna({ stato: "errore", errore: msg.slice(0, 400), ms: Date.now() - t0, finita: new Date().toISOString() });
    await db.from("friday_consumi").insert({ servizio: "prova", ms_totale: Date.now() - t0, esito: msg.slice(0, 120) });
  }
}

/* ───────────── collaudo: un'immagine inventata salvata come «foto» (persona o capo) ───────────── */
async function campione(c: any) {
  const hash = String(c.hash ?? "");
  if (!/^[a-f0-9]{16,64}$/.test(hash)) return;
  try {
    const { d } = await gemini(MODELLI.normale.catena, () => ({
      contents: [{ role: "user", parts: [{ text: String(c.testo ?? "").slice(0, 600) }] }],
      generationConfig: { responseModalities: ["IMAGE"], imageConfig: { aspectRatio: FORMATI.includes(c.formato) ? c.formato : "3:4", imageSize: "1K" } },
    }));
    const img = immagineDi(d);
    const percorso = `campione-${hash}.png`;
    const byte = decodeBase64(img.dati);
    await db.storage.from(BUCKET).upload(percorso, byte, { contentType: img.mime, upsert: true });
    const leggera = await rendi(percorso, 1024, 88);
    await db.from("friday_foto_parti").upsert({ hash, parte: 0, tot: 1, mime: leggera?.mime ?? img.mime, dati: leggera?.b64 ?? img.dati });
    await db.storage.from(BUCKET).remove([percorso]);
  } catch (e) {
    await db.from("friday_consumi").insert({ servizio: "prova", esito: ("campione: " + (e as Error).message).slice(0, 120) });
  }
}

/* ───────────── «Dalle tue foto»: i capi veri di Bea, staccati dalle sue foto ───────────── */
const CATEGORIE = ["maglie", "camicie", "giacche", "jeans", "pantaloni", "gonne", "vestiti", "scarpe", "borse"];
const FORMA_CAT: Record<string, string> = { maglie: "4:5", camicie: "3:4", giacche: "3:4", jeans: "3:4", pantaloni: "3:4", gonne: "4:5", vestiti: "3:4", scarpe: "1:1", borse: "1:1" };
const RAPIDO = Deno.env.get("MODELLO_RAPIDO") || "claude-haiku-5-5";

async function impronta(b64: string) {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(b64));
  return [...new Uint8Array(d)].slice(0, 20).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function domandaRiconosci(gia: string[]) {
  return [
    "You are a fashion stylist cataloguing a woman's wardrobe from a photo of her.",
    "List the clothes, shoes and bags she is wearing that are clearly visible, at most 6. Leave out jewellery, glasses, phones, socks, and anything mostly hidden.",
    gia.length ? `Already in her wardrobe (leave out an item if it is the same garment as one of these):\n${gia.map((g) => "- " + g).join("\n")}` : "Her wardrobe is still empty.",
    'Answer only with a JSON array. Each element: {"cat": one of "maglie","camicie","giacche","jeans","pantaloni","gonne","vestiti","scarpe","borse"; ' +
      '"nome": short Italian name, 1-3 words (e.g. "Giacca oversize", "Jeans larghi", "Décolleté"); "colore": main colour in Italian, 1-2 words; ' +
      '"hex": main colour as #rrggbb; "brand": the brand only if its logo or label is clearly readable in the photo, otherwise ""; ' +
      '"descrizione": a precise English visual description for a product photographer: type, cut, fit, length, colour, fabric, pattern or print, logos, details (25-60 words)}.',
  ].join("\n");
}

async function riconosci(foto: { mime: string; dati: string }, gia: string[]) {
  const chiave = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
  if (!chiave) throw new Error("manca la chiave Anthropic");
  const r = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST", signal: AbortSignal.timeout(90_000),
    headers: { "content-type": "application/json", "x-api-key": chiave, "anthropic-version": "2023-06-01" },
    body: JSON.stringify({ model: RAPIDO, max_tokens: 2000, messages: [{ role: "user", content: [
      { type: "image", source: { type: "base64", media_type: foto.mime, data: foto.dati } },
      { type: "text", text: domandaRiconosci(gia) },
    ] }] }),
  });
  if (!r.ok) throw new Error(`riconoscimento dei capi non riuscito (${r.status}: ${(await r.text().catch(() => "")).slice(0, 160)})`);
  const d = await r.json();
  const u = d?.usage ?? {};
  await db.from("friday_consumi").insert({ servizio: "claude", modello: RAPIDO, token_in: Number(u.input_tokens) || 0, token_out: Number(u.output_tokens) || 0, esito: "armadio" });
  const usd = (Number(u.input_tokens) || 0) * 1 / 1e6 + (Number(u.output_tokens) || 0) * 5 / 1e6;
  const testo = (d.content ?? []).filter((b: any) => b.type === "text").map((b: any) => b.text).join("");
  const m = testo.match(/\[[\s\S]*\]/);
  let elenco: any[] = [];
  try { elenco = m ? JSON.parse(m[0]) : []; } catch { elenco = []; }
  const capi = elenco.filter((c) => c && CATEGORIE.includes(c.cat) && c.nome && c.descrizione).slice(0, 6).map((c) => ({
    cat: c.cat, nome: pulisci(c.nome, 30), colore: pulisci(c.colore, 24), brand: pulisci(c.brand, 24),
    hex: /^#[0-9a-f]{6}$/i.test(String(c.hex)) ? String(c.hex).toLowerCase() : null, descrizione: pulisci(c.descrizione, 420),
  }));
  return { capi, usd };
}

function domandaEstrai(c: { cat: string; descrizione: string }) {
  const come = c.cat === "scarpe" ? "a pair of shoes seen from the side, the nearer shoe slightly in front"
    : c.cat === "borse" ? "the bag seen from the front, handles up" : "the garment in ghost-mannequin style, front view";
  return [
    "IMAGE 1 is a photo of a woman wearing several items.",
    `Create a professional e-commerce product photo of only this item from IMAGE 1: ${c.descrizione}`,
    `Show ${come}, complete and neatly presented as in a fashion catalogue, centered and filling most of the frame, on a pure white background with soft, even studio light and a faint natural shadow.`,
    "Keep the item identical to IMAGE 1: the same colour and shade, fabric and texture, print or pattern and its scale, logos and lettering, buttons, zips, pockets, seams, cut, fit and length. Reconstruct any part hidden in IMAGE 1 consistently with the visible parts.",
    "The picture contains only the item, with no person, body, hands, phone, text or other objects.",
  ].join("\n");
}

async function estrai(id: string) {
  const t0 = Date.now();
  const segna = (campi: Record<string, unknown>) => db.from("friday_estrai").update(campi).eq("id", id);
  let usd = 0, fatti = 0, ultimo = "";
  try {
    const { data: j } = await db.from("friday_estrai").select("id, fonte, fonte_nome").eq("id", id).maybeSingle();
    if (!j) throw new Error("lavoro non trovato");
    await segna({ stato: "in_corso" });
    if (!Deno.env.get("GEMINI_API_KEY")) throw new Error("manca la chiave Google: GEMINI_API_KEY nei segreti di Supabase");
    const foto = (await caricaFoto([j.fonte])).get(j.fonte)!;
    const { data: esistenti } = await db.from("friday_capi").select("nome, colore, descrizione").eq("stato", "pronto");
    const gia = (esistenti ?? []).map((c: any) => `${c.nome}, ${c.colore}: ${String(c.descrizione ?? "").slice(0, 140)}`);
    const ric = await riconosci(foto, gia);
    usd += ric.usd;
    await segna({ trovati: ric.capi.length, costo_usd: Math.round(usd * 10000) / 10000 });
    for (const c of ric.capi) {
      try {
        const { modello, d } = await gemini(MODELLI.normale.catena, (mod, ragiona) => ({
          contents: [{ role: "user", parts: [{ text: domandaEstrai(c) }, { inlineData: { mimeType: foto.mime, data: foto.dati } }] }],
          generationConfig: {
            responseModalities: ["TEXT", "IMAGE"],
            imageConfig: { aspectRatio: FORMA_CAT[c.cat] ?? "3:4", ...(mod.startsWith("gemini-2.5") ? {} : { imageSize: "1K" }) },
            ...(mod.includes("flash") && ragiona && !mod.startsWith("gemini-2.5") ? { thinkingConfig: { thinkingLevel: "high" } } : {}),
          },
        }));
        const img = immagineDi(d), u = d?.usageMetadata ?? {};
        const costo = MODELLI.normale.immagine + (Number(u.promptTokenCount) || 0) * MODELLI.normale.ingresso / 1e6 + (Number(u.thoughtsTokenCount) || 0) * MODELLI.normale.uscita / 1e6;
        usd += costo;
        const uid = crypto.randomUUID(), percorso = `capi/${uid}.png`;
        const su = await db.storage.from(BUCKET).upload(percorso, decodeBase64(img.dati), { contentType: img.mime, upsert: true });
        const grande = su.error ? null : await rendi(percorso, 1024, 86);
        const mini = su.error ? null : await rendi(percorso, 420, 80);
        const dati = grande?.b64 ?? img.dati, mime = grande?.mime ?? img.mime, hash = await impronta(dati);
        const { error: e1 } = await db.from("friday_foto_parti").upsert({ hash, parte: 0, tot: 1, mime, dati });
        if (e1) throw new Error("foto del capo non salvata: " + e1.message);
        const { error: e2 } = await db.from("friday_capi").insert({ id: uid, cat: c.cat, nome: c.nome, brand: c.brand, colore: c.colore, hex: c.hex,
          descrizione: c.descrizione, foto_hash: hash, mime, miniatura: mini?.b64 ?? null, mime_mini: mini?.mime ?? null, origine: "look",
          fonte: j.fonte, fonte_nome: j.fonte_nome, costo_usd: Math.round(costo * 10000) / 10000 });
        if (e2) throw new Error("capo non salvato: " + e2.message);
        fatti++;
        await db.from("friday_consumi").insert({ servizio: "prova", modello, token_in: Number(u.promptTokenCount) || 0,
          token_out: (Number(u.candidatesTokenCount) || 0) + (Number(u.thoughtsTokenCount) || 0), esito: "capo" });
      } catch (e) { ultimo = (e as Error).message || "errore"; if (/chiave Google|fatturazione|credito finito/.test(ultimo)) throw e; }
      await segna({ fatti, costo_usd: Math.round(usd * 10000) / 10000 });
    }
    await segna({ stato: fatti || !ric.capi.length ? "pronta" : "errore", errore: fatti || !ric.capi.length ? null : ultimo.slice(0, 400),
      fatti, costo_usd: Math.round(usd * 10000) / 10000, finita: new Date().toISOString() });
  } catch (e) {
    await segna({ stato: "errore", errore: ((e as Error).message || "errore").slice(0, 400), fatti, costo_usd: Math.round(usd * 10000) / 10000, finita: new Date().toISOString() });
  }
  void t0;
}
