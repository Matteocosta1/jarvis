// Funzione di prova, temporanea: misura quanto ci mette ogni servizio a trascrivere la stessa frase. Non restituisce chiavi.
// Si cancella subito dopo la misura.
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { "content-type": "application/json" } });
function wav(pcm: Uint8Array, hz = 16000) {
  const h = new DataView(new ArrayBuffer(44));
  const s = (o: number, t: string) => { for (let i = 0; i < 4; i++) h.setUint8(o + i, t.charCodeAt(i)); };
  s(0, "RIFF"); h.setUint32(4, 36 + pcm.length, true); s(8, "WAVE"); s(12, "fmt "); h.setUint32(16, 16, true); h.setUint16(20, 1, true); h.setUint16(22, 1, true);
  h.setUint32(24, hz, true); h.setUint32(28, hz * 2, true); h.setUint16(32, 2, true); h.setUint16(34, 16, true); s(36, "data"); h.setUint32(40, pcm.length, true);
  const out = new Uint8Array(44 + pcm.length); out.set(new Uint8Array(h.buffer), 0); out.set(pcm, 44); return out;
}
Deno.serve(async (req) => {
  if (new URL(req.url).searchParams.get("k") !== "misura-7f3a") return json({ errore: "no" }, 401);
  const xi = Deno.env.get("ELEVENLABS_API_KEY") ?? "", groq = Deno.env.get("GROQ_API_KEY") ?? "", gem = Deno.env.get("GEMINI_API_KEY") ?? "";
  const chiavi = { elevenlabs: !!xi, groq: !!groq, gemini: !!gem };
  const t0 = Date.now();
  const r = await fetch("https://api.elevenlabs.io/v1/text-to-speech/onwK4e9ZLuTAKqWW03F9?output_format=pcm_16000", {
    method: "POST", headers: { "xi-api-key": xi, "content-type": "application/json" },
    body: JSON.stringify({ text: "Jarvis, che tempo fa domani a Milano?", model_id: "eleven_multilingual_v2" }) });
  if (!r.ok) return json({ chiavi, errore: `tts ${r.status} ${(await r.text()).slice(0, 200)}` });
  const audio = wav(new Uint8Array(await r.arrayBuffer()));
  const tts = Date.now() - t0;
  const prova = async (nome: string, f: () => Promise<Response>, leggi: (d: any) => string) => {
    const a = Date.now();
    try { const x = await f(); const t = await x.text(); let testo = ""; try { testo = leggi(JSON.parse(t)); } catch { testo = t.slice(0, 120); }
      return { nome, ms: Date.now() - a, stato: x.status, testo: String(testo).slice(0, 120) }; }
    catch (e) { return { nome, ms: Date.now() - a, errore: (e as Error).message }; }
  };
  const elevenFD = (m: string) => { const f = new FormData(); f.append("model_id", m); f.append("language_code", "ita"); f.append("tag_audio_events", "false"); f.append("file", new Blob([audio], { type: "audio/wav" }), "v.wav"); return f; };
  const groqFD = (m: string) => { const f = new FormData(); f.append("model", m); f.append("language", "it"); f.append("response_format", "json"); f.append("file", new Blob([audio], { type: "audio/wav" }), "v.wav"); return f; };
  let b64 = ""; for (let k = 0; k < audio.length; k += 0x8000) b64 += String.fromCharCode(...audio.subarray(k, k + 0x8000)); b64 = btoa(b64);
  const lavori: Promise<any>[] = [];
  if (xi) for (const m of ["scribe_v2", "scribe_v1"]) lavori.push(prova(`elevenlabs ${m}`, () => fetch("https://api.elevenlabs.io/v1/speech-to-text", { method: "POST", headers: { "xi-api-key": xi }, body: elevenFD(m) }), (d) => d.text ?? JSON.stringify(d)));
  if (groq) for (const m of ["whisper-large-v3-turbo", "whisper-large-v3"]) lavori.push(prova(`groq ${m}`, () => fetch("https://api.groq.com/openai/v1/audio/transcriptions", { method: "POST", headers: { authorization: `Bearer ${groq}` }, body: groqFD(m) }), (d) => d.text ?? JSON.stringify(d)));
  if (gem) for (const m of ["gemini-2.5-flash", "gemini-2.5-flash-lite", "gemini-3.5-flash"]) lavori.push(prova(`gemini ${m}`, () => fetch(`https://generativelanguage.googleapis.com/v1beta/models/${m}:generateContent`, { method: "POST", headers: { "x-goog-api-key": gem, "content-type": "application/json" },
    body: JSON.stringify({ contents: [{ role: "user", parts: [{ inlineData: { mimeType: "audio/wav", data: b64 } }, { text: "Trascrivi parola per parola, in italiano. Solo la trascrizione." }] }], generationConfig: { temperature: 0 } }) }),
    (d) => d.candidates?.[0]?.content?.parts?.map((p: any) => p.text).join("") ?? JSON.stringify(d).slice(0, 120)));
  return json({ chiavi, tts_ms: tts, secondi_audio: (audio.length - 44) / 32000, risultati: await Promise.all(lavori) });
});
