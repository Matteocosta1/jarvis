// jarvis-audizione (12 nov, chiesta dal signore): prepara i campioni della voce di JARVIS per l'audizione dei toni e delle
// pronunce, con la stessa voce, lo stesso modello e le stesse impostazioni del cervello, e li salva nel contenitore privato
// «audizione» di Supabase Storage, con un link firmato valido 14 giorni. Solo con un codice usa-e-getta (jarvis_deploy_codici).
// Non tocca il cervello. Corpo: { campioni: [{ id, testo, velocita? }] }  →  { fatti: [{ id, url }], errori: [...] }
import { createClient } from "npm:@supabase/supabase-js@2";

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { "content-type": "application/json" } });
const CONTENITORE = "audizione";

Deno.serve(async (req) => {
  const codice = new URL(req.url).searchParams.get("codice") ?? "";
  let ok = false;
  if (/^[a-f0-9]{32,64}$/.test(codice)) {
    const { data } = await db.from("jarvis_deploy_codici").delete().eq("codice", codice).gt("scade", new Date().toISOString()).select("codice");
    ok = (data?.length ?? 0) > 0;
  }
  if (!ok) return json({ errore: "codice non valido" }, 401);
  let corpo: any;
  try { corpo = await req.json(); } catch { return json({ errore: "richiesta non valida" }, 400); }
  const chiave = Deno.env.get("ELEVENLABS_API_KEY") ?? "";
  await db.storage.createBucket(CONTENITORE, { public: false }).catch(() => {});
  const voce = Deno.env.get("ELEVENLABS_VOICE_ID") || "onwK4e9ZLuTAKqWW03F9";
  const modello = Deno.env.get("ELEVENLABS_MODELLO") || "eleven_v4_turbo";
  const fatti: any[] = [], errori: any[] = [];
  for (const c of (Array.isArray(corpo?.campioni) ? corpo.campioni : []).slice(0, 40)) {
    const id = String(c.id ?? "").replace(/[^a-z0-9\-]/g, "");
    const testo = String(c.testo ?? "").slice(0, 600);
    if (!id || !testo) continue;
    try {
      const r = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${voce}?output_format=mp3_44100_128`, {
        method: "POST",
        headers: { "xi-api-key": chiave, "content-type": "application/json", accept: "audio/mpeg" },
        body: JSON.stringify({ text: testo, model_id: modello,
          voice_settings: { stability: 0.45, similarity_boost: 0.8, style: 0.2, use_speaker_boost: true, speed: Number(c.velocita) || 1.05 } }),
      });
      if (!r.ok) { errori.push({ id, errore: `ElevenLabs ${r.status}: ${(await r.text()).slice(0, 200)}` }); continue; }
      const audio = new Uint8Array(await r.arrayBuffer());
      const percorso = `${id}.mp3`;
      const su = await db.storage.from(CONTENITORE).upload(percorso, audio, { contentType: "audio/mpeg", upsert: true });
      if (su.error) { errori.push({ id, errore: `Storage: ${su.error.message}` }); continue; }
      const firmato = await db.storage.from(CONTENITORE).createSignedUrl(percorso, 14 * 86400);
      if (firmato.error) { errori.push({ id, errore: `link: ${firmato.error.message}` }); continue; }
      fatti.push({ id, url: firmato.data.signedUrl });
    } catch (e) { errori.push({ id, errore: (e as Error).message }); }
  }
  return json({ fatti, errori, voce, modello });
});
