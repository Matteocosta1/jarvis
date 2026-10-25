// JARVIS — orecchie in cloud: riceve un audio (base64) dall'orologio e restituisce il testo.
// POST, header x-jarvis-token. Corpo: { audio: base64, formato?: "m4a" }  →  { testo: "..." }
// 25 ott (v32): prima ElevenLabs Scribe, come il cervello (stessi parametri, ~0,6 s): la sua risposta vale subito, anche vuota
// (rumore, niente parole). Groq e Gemini restano solo di riserva, se Scribe non risponde. Prima erano tutti in gara e una
// risposta vuota non vinceva: si aspettava fino a 20 s e alla fine vinceva Whisper con «Sottotitoli a cura di QTSS»
// (la sua frase inventata sull'audio senza voce, 53 byte): l'orologio la mandava al cervello come domanda.
// Segreti: JARVIS_TOKEN e almeno uno tra ELEVENLABS_API_KEY, GROQ_API_KEY, GEMINI_API_KEY.
// Facoltativi: GROQ_STT_MODELLO, GEMINI_STT_MODELLO, ELEVENLABS_STT_MODELLO.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { "content-type": "application/json" } });
function uguali(a: string, b: string) {
  if (!a || a.length !== b.length) return false;
  let x = 0; for (let k = 0; k < a.length; k++) x |= a.charCodeAt(k) ^ b.charCodeAt(k);
  return x === 0;
}
const tipoAudio = (formato: string) => formato === "wav" ? "audio/wav" : "audio/mp4";

// ───────── Groq (Whisper) ─────────
async function conGroq(audio: Uint8Array, formato: string, chiave: string) {
  const modelli = [Deno.env.get("GROQ_STT_MODELLO") || "whisper-large-v3-turbo", "whisper-large-v3"];
  let ultimo = "";
  for (const modello of [...new Set(modelli)]) {
    const f = new FormData();
    f.append("model", modello);
    f.append("language", "it");
    f.append("response_format", "json");
    f.append("temperature", "0");
    // aiuta Whisper con i nomi propri che il signore usa spesso
    f.append("prompt", "Jarvis, Discosizer, Discogs, Matteo, Bea, Cristina, Pier, Apple Music, Shazam.");
    f.append("file", new Blob([audio], { type: tipoAudio(formato) }), `voce.${formato}`);
    try {
      const r = await fetch("https://api.groq.com/openai/v1/audio/transcriptions", {
        method: "POST", headers: { authorization: `Bearer ${chiave}` }, body: f, signal: AbortSignal.timeout(9000),
      });
      if (r.ok) {
        const d = await r.json();
        return { testo: String(d.text ?? "").trim(), fonte: "groq" };
      }
      ultimo = `Groq ${r.status}: ${(await r.text().catch(() => "")).slice(0, 300)}`;
      if (r.status === 401 || r.status === 403 || r.status === 429) break;   // chiave o limiti: si passa alla riserva
    } catch (e) {
      ultimo = `Groq: ${(e as Error).message}`;
      break;                                   // tempo scaduto: inutile aspettare anche il secondo modello
    }
  }
  return { errore: ultimo };
}

// ───────── Google Gemini ─────────
let modelloGemini: string | null = null;
function base64(byte: Uint8Array) {
  let s = "";
  for (let k = 0; k < byte.length; k += 0x8000) s += String.fromCharCode(...byte.subarray(k, k + 0x8000));
  return btoa(s);
}
async function conGemini(audio: Uint8Array, formato: string, chiave: string) {
  const fisso = Deno.env.get("GEMINI_STT_MODELLO");
  const modelli = fisso ? [fisso] : modelloGemini ? [modelloGemini] : ["gemini-3.8-flash", "gemini-3.5-flash", "gemini-2.5-flash"];
  const tipi = formato === "wav" ? ["audio/wav"] : ["audio/mp4", "audio/aac"];
  const dati = base64(audio);
  let ultimo = "";
  for (const modello of modelli) {
    for (const tipo of tipi) {
      try {
        const r = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${modello}:generateContent`, {
          method: "POST", signal: AbortSignal.timeout(9000),
          headers: { "x-goog-api-key": chiave, "content-type": "application/json" },
          body: JSON.stringify({
            contents: [{ role: "user", parts: [
              { inlineData: { mimeType: tipo, data: dati } },
              { text: "Trascrivi parola per parola quello che dice la persona in questo audio, in italiano. " +
                      "Nomi frequenti: Jarvis, Discosizer, Discogs, Matteo, Bea, Cristina, Pier. " +
                      "Rispondi solo con la trascrizione, senza commenti. Se non si sente nulla rispondi con una riga vuota." },
            ] }],
            generationConfig: { temperature: 0 },
          }),
        });
        if (r.ok) {
          const d = await r.json();
          const testo = (d.candidates?.[0]?.content?.parts ?? []).map((p: any) => p.text ?? "").join("").trim();
          modelloGemini = modello;
          return { testo, fonte: "gemini" };
        }
        ultimo = `Gemini ${r.status}: ${(await r.text().catch(() => "")).slice(0, 300)}`;
        if (r.status === 401 || r.status === 403 || r.status === 429) return { errore: ultimo };
        if (r.status === 404) break;          // modello inesistente: si prova il successivo
      } catch (e) {
        ultimo = `Gemini: ${(e as Error).message}`;
      }
    }
  }
  return { errore: ultimo };
}

// ───────── ElevenLabs Scribe (il primo, come nel cervello) ─────────
let modelloBuono: string | null = null;
async function conElevenLabs(audio: Uint8Array, formato: string, chiave: string) {
  const fisso = Deno.env.get("ELEVENLABS_STT_MODELLO");
  const tentativi: [string, boolean][] = fisso ? [[fisso, true], [fisso, false]]
    : modelloBuono ? [[modelloBuono, true], [modelloBuono, false]]
    : [["scribe_v2", true], ["scribe_v1", true]];
  let ultimo = "";
  for (const [modello, lingua] of tentativi) {
    const f = new FormData();
    f.append("model_id", modello);
    if (lingua) f.append("language_code", "ita");
    f.append("tag_audio_events", "false");
    f.append("file", new Blob([audio], { type: tipoAudio(formato) }), `voce.${formato}`);
    let r: Response;
    try {
      r = await fetch("https://api.elevenlabs.io/v1/speech-to-text", { method: "POST", headers: { "xi-api-key": chiave }, body: f, signal: AbortSignal.timeout(8000) });
    } catch (e) { ultimo = `ElevenLabs: ${(e as Error).message}`; continue; }
    if (r.ok) {
      const d = await r.json();
      modelloBuono = modello;
      return { testo: String(d.text ?? "").trim(), fonte: "elevenlabs" };
    }
    ultimo = `ElevenLabs ${r.status}: ${(await r.text().catch(() => "")).slice(0, 300)}`;
    if (r.status === 401 || r.status === 402 || r.status === 403 || r.status === 429) break;   // chiave o credito: inutile insistere
  }
  return { errore: ultimo };
}

/// Le frasi che Whisper inventa sull'audio senza voce (sottotitoli dei video su cui è stato addestrato): non sono il signore.
const ALLUCINAZIONI = /^\s*(sottotitoli|sottotitolato|sottotitoli creati|grazie per la visione|grazie a tutti per la visione|a cura di qtss|iscriviti al canale)\b/i;

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ errore: "metodo non ammesso" }, 405);
  const segreto = Deno.env.get("JARVIS_TOKEN") ?? "";
  if (!segreto || !uguali(req.headers.get("x-jarvis-token") ?? "", segreto)) return json({ errore: "parola d'ordine errata" }, 401);
  const groq = Deno.env.get("GROQ_API_KEY") ?? "";
  const gemini = Deno.env.get("GEMINI_API_KEY") ?? "";
  const eleven = Deno.env.get("ELEVENLABS_API_KEY") ?? "";
  if (!groq && !gemini && !eleven) return json({ errore: "manca una chiave per la trascrizione (GEMINI_API_KEY, GROQ_API_KEY o ELEVENLABS_API_KEY)" }, 503);
  let corpo: any;
  try { corpo = await req.json(); } catch { return json({ errore: "richiesta non valida" }, 400); }
  if (typeof corpo?.audio !== "string" || corpo.audio.length < 100 || corpo.audio.length > 12_000_000) return json({ errore: "audio mancante o troppo lungo" }, 400);
  let audio: Uint8Array;
  try { audio = Uint8Array.from(atob(corpo.audio), (c) => c.charCodeAt(0)); } catch { return json({ errore: "audio non leggibile" }, 400); }
  const formato = corpo.formato === "wav" ? "wav" : "m4a";

  const t0 = Date.now();
  // 1) Scribe, come il cervello: la sua risposta (anche vuota) è quella buona
  if (eleven) {
    const e = await conElevenLabs(audio, formato, eleven);
    if (!("errore" in e)) {
      console.log(`ascolto: elevenlabs ${Date.now() - t0} ms, ${e.testo.length} caratteri, audio ${audio.length} byte`);
      return json(e);
    }
    console.log(`ascolto: elevenlabs non riuscito (${Date.now() - t0} ms): ${e.errore}`);
  }
  // 2) riserva: Groq e Gemini in gara; vince il primo che trascrive. Una risposta vuota vale come «niente parole».
  const errori: string[] = [];
  const gara: Promise<any>[] = [];
  let vuoto: any = null;
  const iscrivi = (p: Promise<any>) => gara.push(p.then((e) => {
    if (e.errore) { errori.push(e.errore); throw new Error(e.errore); }
    if (!e.testo || ALLUCINAZIONI.test(e.testo)) { vuoto = { testo: "", fonte: e.fonte }; throw new Error("vuoto"); }
    return e;
  }));
  if (groq) iscrivi(conGroq(audio, formato, groq));
  if (gemini) iscrivi(conGemini(audio, formato, gemini));
  const scadenza = new Promise((_, no) => setTimeout(() => no(new Error("tempo scaduto")), 10000));
  try {
    const e = await Promise.race([Promise.any(gara), scadenza]);
    console.log(`ascolto: riserva ${(e as any).fonte} ${Date.now() - t0} ms`);
    return json(e);
  } catch { /* nessuno ha trascritto qualcosa in tempo */ }
  console.log(`ascolto: nessun testo dalla riserva (${Date.now() - t0} ms) ${errori.join(" · ").slice(0, 300)}`);
  if (vuoto) return json(vuoto);
  if (!errori.length) errori.push("nessun servizio di trascrizione ha risposto in tempo");
  return json({ errore: errori.join(" · ") }, 502);
});
