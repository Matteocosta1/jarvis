// jarvis-prova-voce: prova temporanea della voce (23 ottobre 2026), da cancellare dopo l'ascolto.
// Fa dire le stesse frasi al modello ElevenLabs di oggi e a eleven_v4_turbo, con la stessa voce di JARVIS:
// misura il tempo al primo suono (streaming, come nell'app), i crediti consumati, salva gli mp3 nell'Archivio
// (cartella prove-voce) e restituisce i link per ascoltarli (validi 24 ore).
// Chiave: un codice usa-e-getta della tabella jarvis_deploy_codici (?codice=…), come jarvis-deploy.
// Segreti già presenti: ELEVENLABS_API_KEY, ELEVENLABS_VOICE_ID (facoltativo), ELEVENLABS_MODELLO (facoltativo).
import { createClient } from "npm:@supabase/supabase-js@2";

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o, null, 1), { status, headers: { "content-type": "application/json" } });
const XI = "https://api.elevenlabs.io/v1";
const VOCE = Deno.env.get("ELEVENLABS_VOICE_ID") || "onwK4e9ZLuTAKqWW03F9";   // come il cervello: Daniel se non ce n'è un'altra
const BUCKET = "archivio";
const IMPOSTAZIONI = { stability: 0.45, similarity_boost: 0.8, style: 0.2, use_speaker_boost: true, speed: 1.05 };   // quelle del cervello

// [testo per il modello di oggi, testo per v4 Turbo con il tono]
const FRASI: [string, string, string][] = [
  ["normale", "Buonasera, Sir. Tutti i sistemi sono in linea, e domani a Milano non piove.", "Buonasera, Sir. Tutti i sistemi sono in linea, e domani a Milano non piove."],
  ["ironica", "Diciamo che oggi ha avuto i suoi momenti, Sir.", "[sarcastic] Diciamo che oggi ha avuto i suoi momenti, Sir."],
  ["sussurro", "Sono le otto e cinque, Sir.", "[whispers] Sono le otto e cinque, Sir."],
];

async function crediti(chiave: string): Promise<number | null> {
  try {
    const r = await fetch(`${XI}/user/subscription`, { headers: { "xi-api-key": chiave }, signal: AbortSignal.timeout(8000) });
    if (!r.ok) return null;
    const d = await r.json();
    return typeof d.character_count === "number" ? d.character_count : null;
  } catch { return null; }
}

async function dici(testo: string, modello: string, chiave: string) {
  const t0 = performance.now();
  const corpo = (impostazioni: unknown) => JSON.stringify({ text: testo, model_id: modello, ...(impostazioni ? { voice_settings: impostazioni } : {}) });
  let r = await fetch(`${XI}/text-to-speech/${VOCE}/stream?output_format=mp3_44100_128`, {
    method: "POST", headers: { "xi-api-key": chiave, "content-type": "application/json" }, body: corpo(IMPOSTAZIONI), signal: AbortSignal.timeout(60_000),
  });
  let nota = "";
  if (r.status === 400 || r.status === 422) {        // un modello nuovo potrebbe non accettare tutte le impostazioni: riprova con quelle di base
    nota = `impostazioni del cervello rifiutate (${r.status}): ${(await r.text()).slice(0, 160)}; riprovato con quelle di base`;
    r = await fetch(`${XI}/text-to-speech/${VOCE}/stream?output_format=mp3_44100_128`, {
      method: "POST", headers: { "xi-api-key": chiave, "content-type": "application/json" }, body: corpo(null), signal: AbortSignal.timeout(60_000),
    });
  }
  if (!r.ok || !r.body) return { errore: `ElevenLabs ${r.status}: ${(await r.text()).slice(0, 300)}`, nota };
  const lettore = r.body.getReader(), pezzi: Uint8Array[] = [];
  let primo: number | null = null, byte = 0;
  for (;;) {
    const { done, value } = await lettore.read();
    if (done) break;
    if (value?.length) { if (primo === null) primo = performance.now() - t0; pezzi.push(value); byte += value.length; }
  }
  const audio = new Uint8Array(byte); let k = 0; for (const p of pezzi) { audio.set(p, k); k += p.length; }
  return { audio, primo_suono_ms: Math.round(primo ?? -1), totale_ms: Math.round(performance.now() - t0), byte,
    costo_dichiarato: r.headers.get("character-cost") ?? r.headers.get("x-character-count") ?? null, nota };
}

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const codice = url.searchParams.get("codice") ?? "";
  let ok = false;
  if (/^[a-f0-9]{32,64}$/.test(codice)) {
    const { data } = await db.from("jarvis_deploy_codici").delete().eq("codice", codice).gt("scade", new Date().toISOString()).select("codice");
    ok = (data?.length ?? 0) > 0;
  }
  if (!ok) return json({ errore: "chiave mancante o scaduta" }, 401);
  const chiave = Deno.env.get("ELEVENLABS_API_KEY") ?? "";
  if (!chiave) return json({ errore: "manca ELEVENLABS_API_KEY" }, 500);

  const { data: secchio } = await db.storage.getBucket(BUCKET);        // l'Archivio si crea alla prima volta, come nel cervello
  if (!secchio) await db.storage.createBucket(BUCKET, { public: false, fileSizeLimit: "200MB" });
  const oggi = Deno.env.get("ELEVENLABS_MODELLO") || "eleven_multilingual_v2";
  const risultati: unknown[] = [];
  for (const [modello, colonna] of [[oggi, 1], ["eleven_v4_turbo", 2]] as [string, number][]) {
    const prima = await crediti(chiave);
    const frasi: unknown[] = [];
    let caratteri = 0;
    for (const f of FRASI) {
      const testo = f[colonna];
      caratteri += testo.length;
      try {
        const d = await dici(testo, modello, chiave);
        if ("errore" in d && d.errore) { frasi.push({ tipo: f[0], testo, errore: d.errore, nota: d.nota }); continue; }
        const { audio, ...dati } = d as any;
        const percorso = `prove-voce/${new Date().toISOString().slice(0, 10)}-${modello}-${f[0]}.mp3`;
        const su = await db.storage.from(BUCKET).upload(percorso, audio, { contentType: "audio/mpeg", upsert: true });
        const link = su.error ? null : (await db.storage.from(BUCKET).createSignedUrl(percorso, 86400)).data?.signedUrl ?? null;
        frasi.push({ tipo: f[0], testo, ...dati, link, errore_archivio: su.error?.message ?? null });
      } catch (e) { frasi.push({ tipo: f[0], testo, errore: (e as Error).message }); }
    }
    await new Promise((r) => setTimeout(r, 2500));       // il conteggio dei crediti si aggiorna con un attimo di ritardo
    const dopo = await crediti(chiave);
    risultati.push({ modello, caratteri_mandati: caratteri, crediti_consumati: prima !== null && dopo !== null ? dopo - prima : null,
      crediti_per_carattere: prima !== null && dopo !== null && caratteri ? Math.round(((dopo - prima) / caratteri) * 100) / 100 : null, frasi });
  }
  return json({ voce: VOCE, risultati });
});
