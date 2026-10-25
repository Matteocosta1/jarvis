// Idea D (25 ott): orologio e Mac mandano la frase come audio insieme alla richiesta della risposta (un giro solo).
// Il cervello trascrive, manda «trascritto», e solo dopo una breve attesa chiama Claude; se l'app chiude la linea (era un suo
// comando) Claude non parte. Più: la richiesta ripetuta (stesso x-richiesta) col numero registrato insieme alle letture (difetto 5).
const qui = new URL(".", import.meta.url).pathname;
Deno.writeTextFileSync(qui + "cervello_stato.ts", Deno.readTextFileSync(qui + "cervello_test.ts").replace('from "./finto_db.ts"', 'from "./finto_db_stato.ts"'));
Deno.env.set("ELEVENLABS_API_KEY", "finta");
const C = await import(qui + "cervello_stato.ts");
const g = globalThis as any;
let ko = 0; const atteso = (n: string, v: boolean, info: unknown = "") => { if (!v) { ko++; console.log("✗", n, JSON.stringify(info)); } else console.log("✓", n); };
const pausa = (ms: number) => new Promise((ok) => setTimeout(ok, ms));
const enc = new TextEncoder();
const anthropic: any[] = [];
let trascrizione: { stato: number; testo: string } = { stato: 200, testo: "che tempo fa domani?" };
const stt: { nome: string; tipo: string }[] = [];
let ritardoClaude = 0;
g.fetch = async (u: any, o?: any) => {
  const url = String(u?.url ?? u);
  if (url.includes("/speech-to-text")) {
    const f = o.body.get("file");
    stt.push({ nome: f?.name ?? "", tipo: f?.type ?? "" });
    await pausa(60);
    return trascrizione.stato === 200 ? new Response(JSON.stringify({ text: trascrizione.testo })) : new Response("quota", { status: trascrizione.stato });
  }
  if (!url.includes("api.anthropic.com")) return new Response("{}", { status: 200 });
  const corpo = JSON.parse(o.body);
  if (corpo.stream !== true) return new Response(JSON.stringify({ content: [{ type: "text", text: "[]" }] }));
  anthropic.push(corpo);
  if (ritardoClaude) await pausa(ritardoClaude);
  const ev = [{ type: "message_start", message: { usage: { input_tokens: 5 } } },
    { type: "content_block_start", index: 0, content_block: { type: "text", text: "" } },
    { type: "content_block_delta", index: 0, delta: { type: "text_delta", text: "Domani sole, Sir." } }, { type: "content_block_stop", index: 0 },
    { type: "message_delta", delta: { stop_reason: "end_turn" }, usage: { output_tokens: 5 } }];
  return new Response(new ReadableStream({ start(c) { for (const e of ev) c.enqueue(enc.encode(`data: ${JSON.stringify(e)}\n\n`)); c.close(); } }));
};
const audio = btoa("RIFF" + "x".repeat(400));
const richiesta = (extra: Record<string, unknown>, intestazioni: Record<string, string> = {}) => C.__servi(new Request("http://x/jarvis", { method: "POST",
  headers: { "x-jarvis-token": "prova", "content-type": "application/json", ...intestazioni },
  body: JSON.stringify({ dispositivo: "mac", strumenti_client: [], senza_filo: true, ...extra }) }));
const righe = async (r: Response) => (await r.text()).split("\n").filter(Boolean).map((l) => JSON.parse(l));
const azzera = () => { g.__tab = {}; anthropic.length = 0; stt.length = 0; trascrizione = { stato: 200, testo: "che tempo fa domani?" }; ritardoClaude = 0; };
const ultimoUtente = (c: any) => { const m = c?.messages?.at(-1); return typeof m?.content === "string" ? m.content : (m?.content ?? []).map((b: any) => b.text ?? "").join(""); };

// 1 ─ la frase in audio: prima «trascritto», poi la risposta; Claude riceve storia + prefisso + testo
azzera();
const r1 = await righe(await richiesta({ audio_domanda: audio, formato_audio: "wav", prefisso_domanda: "(riprendo il discorso: se questo completa o aggiunge qualcosa a quello che ti ho detto prima, rispondi tenendo conto di entrambe le cose; se è un argomento nuovo, rispondi solo a questo) ",
  messaggi: [{ role: "user", content: "che tempo fa oggi?" }, { role: "assistant", content: "Sole, Sir." }] }));
atteso("1. la prima riga è «trascritto» con il testo", r1[0]?.t === "trascritto" && r1[0]?.d === "che tempo fa domani?", r1[0]);
atteso("1. poi la risposta", r1.some((e) => e.t === "testo") && r1.at(-1)?.t === "fine", r1.map((e) => e.t));
atteso("1. una chiamata a Claude, con la storia di prima", anthropic.length === 1 && anthropic[0].messages.length === 3, anthropic.map((c) => c.messages.length));
atteso("1. il messaggio nuovo è prefisso + trascrizione", /riprendo il discorso[\s\S]*che tempo fa domani\?$/.test(ultimoUtente(anthropic[0])), ultimoUtente(anthropic[0]).slice(-120));
atteso("1. il file va a ElevenLabs come WAV", stt[0]?.nome === "voce.wav" && stt[0]?.tipo === "audio/wav", stt);

// 2 ─ l'app chiude la linea appena legge «trascritto» (era un suo comando): Claude non parte
azzera();
trascrizione.testo = "apri il meteo";
const r2 = await richiesta({ audio_domanda: audio, formato_audio: "m4a", messaggi: [] });
const rd = r2.body!.getReader();
let prima2: any = null;
for (;;) {
  const x = await rd.read(); if (x.done) break;
  const l = new TextDecoder().decode(x.value).split("\n").filter(Boolean).map((z) => JSON.parse(z));
  if (l.some((e) => e.t === "trascritto")) { prima2 = l.find((e) => e.t === "trascritto"); await rd.cancel(); break; }
}
await pausa(500);
atteso("2. «trascritto» arriva", prima2?.d === "apri il meteo", prima2);
atteso("2. l'app chiude subito: nessuna chiamata a Claude", anthropic.length === 0, anthropic.length);
const turni2 = (g.__tab.jarvis_consumi ?? []).filter((x: any) => x.servizio === "turno");
atteso("2. non risulta un turno «interrotto»", !turni2.some((x: any) => x.esito === "interrotto"), turni2);
atteso("2. il file m4a dell'orologio va a ElevenLabs come audio/mp4", stt[0]?.nome === "voce.m4a" && stt[0]?.tipo === "audio/mp4", stt);

// 3 ─ trascrizione fallita: «trascritto» con l'errore, niente Claude (l'app ripassa dalla strada di prima)
azzera();
trascrizione.stato = 429;
const r3 = await righe(await richiesta({ audio_domanda: audio, messaggi: [] }));
atteso("3. errore di trascrizione: «trascritto» vuoto con l'errore", r3.length === 1 && r3[0].t === "trascritto" && r3[0].d === "" && /429/.test(r3[0].errore), r3);
atteso("3. niente Claude", anthropic.length === 0, anthropic.length);

// 4 ─ non si sente niente: «trascritto» vuoto e basta
azzera();
trascrizione.testo = "";
const r4 = await righe(await richiesta({ audio_domanda: audio, messaggi: [] }));
atteso("4. niente di detto: solo «trascritto» vuoto", r4.length === 1 && r4[0].t === "trascritto" && r4[0].d === "" && !r4[0].errore, r4);
atteso("4. niente Claude", anthropic.length === 0, anthropic.length);

// 5 ─ la sveglia dice all'app che il giro unico c'è
azzera();
const s5 = await (await richiesta({ sveglia: true })).json();
atteso("5. sveglia: giro_unico vero", s5.giro_unico === true, s5);

// 6 ─ audio + arbitro: il doppione si riconosce dal testo trascritto (Mac e iPhone sentono la stessa frase)
azzera();
const IPHONE = "11111111-aaaa-4aaa-8aaa-111111111111", MAC = "22222222-bbbb-4bbb-8bbb-222222222222";
const fine = Date.now();
const [a6, b6] = await Promise.all([
  righe(await C.__servi(new Request("http://x/jarvis", { method: "POST", headers: { "x-jarvis-token": "prova", "content-type": "application/json" },
    body: JSON.stringify({ messaggi: [{ role: "user", content: "Jarvis, che tempo fa domani?" }], dispositivo: "iphone", strumenti_client: [], senza_filo: true, a_voce: true, arbitro: { id: IPHONE, fine } }) }))),
  pausa(30).then(async () => righe(await richiesta({ audio_domanda: audio, messaggi: [], a_voce: true, arbitro: { id: MAC, fine: fine + 200 } }))),
]);
const es = (rr: any[]) => rr.some((e) => e.t === "doppione") ? "tace" : rr.some((e) => e.t === "fine") ? "risponde" : "?";
atteso("6. iPhone (testo) e Mac (audio) con la stessa frase: risponde uno solo", [es(a6), es(b6)].sort().join(",") === "risponde,tace", [es(a6), es(b6)]);

// 7 ─ difetto 5: la richiesta ripetuta con lo stesso numero rimanda la risposta pronta, senza rifarla
azzera();
const num = "abcd1234-0000-4000-8000-000000000001";
const domanda = { messaggi: [{ role: "user", content: "che tempo fa domani?" }], dispositivo: "iphone" };
const r7a = await righe(await richiesta(domanda, { "x-richiesta": num }));
await pausa(100);                                     // l'esito si scrive in sottofondo
const r7b = await righe(await richiesta(domanda, { "x-richiesta": num }));
atteso("7. la prima risponde", r7a.at(-1)?.t === "fine", r7a.map((e) => e.t));
atteso("7. la ripetuta rimanda la stessa risposta", r7b.length === 2 && r7b[0].t === "testo" && r7b[1].t === "fine" && r7b[1].testo === r7a.at(-1)?.testo, r7b);
atteso("7. Claude chiamato una volta sola", anthropic.length === 1, anthropic.length);
// 8 ─ ripetuta mentre la prima è ancora in lavorazione: aspetta e rimanda la risposta
azzera();
ritardoClaude = 900;
const num8 = "abcd1234-0000-4000-8000-000000000002";
const [r8a, r8b] = await Promise.all([righe(await richiesta(domanda, { "x-richiesta": num8 })),
  pausa(200).then(async () => righe(await richiesta(domanda, { "x-richiesta": num8 })))]);
atteso("8. la ripetuta in lavorazione aspetta e rimanda la risposta pronta", r8b.at(-1)?.t === "fine" && r8b.at(-1)?.testo === r8a.at(-1)?.testo, { r8a: r8a.map((e) => e.t), r8b });
atteso("8. Claude chiamato una volta sola", anthropic.length === 1, anthropic.length);
// 9 ─ il filo: col comando chiuso dall'app non si scrive niente; con la domanda vera sì (dopo il primo giro con Claude)
azzera();
trascrizione.testo = "apri il meteo";
const r9 = await C.__servi(new Request("http://x/jarvis", { method: "POST", headers: { "x-jarvis-token": "prova", "content-type": "application/json" },
  body: JSON.stringify({ dispositivo: "orologio", strumenti_client: [], audio_domanda: audio, formato_audio: "m4a", messaggi: [] }) }));
const rd9 = r9.body!.getReader();
for (;;) { const x = await rd9.read(); if (x.done) break; if (new TextDecoder().decode(x.value).includes("trascritto")) { await rd9.cancel(); break; } }
await pausa(700);
atteso("9. comando chiuso dall'app: nessuna chiamata a Claude", anthropic.length === 0, anthropic.length);
atteso("9. comando chiuso dall'app: il filo non si tocca", !(g.__tab.jarvis_filo ?? []).length, g.__tab.jarvis_filo);
azzera();
await righe(await C.__servi(new Request("http://x/jarvis", { method: "POST", headers: { "x-jarvis-token": "prova", "content-type": "application/json" },
  body: JSON.stringify({ dispositivo: "orologio", strumenti_client: [], audio_domanda: audio, formato_audio: "m4a", messaggi: [] }) })));
await pausa(300);
atteso("9. domanda vera in audio: il filo si aggiorna", (g.__tab.jarvis_filo ?? []).length === 1 && anthropic.length >= 1, { filo: g.__tab.jarvis_filo, claude: anthropic.length });
console.log("prove giro unico: sbagliate", ko);
