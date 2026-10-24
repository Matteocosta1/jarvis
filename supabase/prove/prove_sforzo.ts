// Idea A (25 ott): Opus a voce ragiona «low» (prima parola prima); «medium» (nessun parametro) per le richieste da ragionamento,
// per il Wiretap e quando l'app non dice che è a voce. Lo sforzo resta lo stesso dopo gli strumenti del dispositivo.
// Cervello vero (copia di prepara.sh) con Anthropic finto e database finto con stato.
const qui = new URL(".", import.meta.url).pathname;
Deno.writeTextFileSync(qui + "cervello_stato.ts", Deno.readTextFileSync(qui + "cervello_test.ts").replace('from "./finto_db.ts"', 'from "./finto_db_stato.ts"'));
const C = await import(qui + "cervello_stato.ts");
const g = globalThis as any;
let ko = 0; const atteso = (n: string, v: boolean, info: unknown = "") => { if (!v) { ko++; console.log("✗", n, JSON.stringify(info)); } else console.log("✓", n); };
const enc = new TextEncoder();
const chiamate: any[] = [];
let conStrumento = false;
const sse = (eventi: unknown[]) => new Response(new ReadableStream({ start(c) { for (const e of eventi) c.enqueue(enc.encode(`data: ${JSON.stringify(e)}\n\n`)); c.close(); } }), { status: 200 });
const uso = { type: "message_start", message: { usage: { input_tokens: 50, cache_read_input_tokens: 1000 } } };
const testo = (t: string) => [{ type: "content_block_start", index: 0, content_block: { type: "text", text: "" } },
  { type: "content_block_delta", index: 0, delta: { type: "text_delta", text: t } }, { type: "content_block_stop", index: 0 }];
g.fetch = async (u: any, o?: any) => {
  const url = String(u?.url ?? u);
  if (!url.includes("api.anthropic.com")) return new Response("{}", { status: 200 });
  const corpo = JSON.parse(o.body);
  if (corpo.stream !== true) return new Response(JSON.stringify({ content: [{ type: "text", text: "[]" }] }));
  chiamate.push({ model: corpo.model, effort: corpo.output_config?.effort ?? null });
  if (conStrumento && !corpo.messages.at(-1).content?.some?.((b: any) => b.type === "tool_result")) {
    return sse([uso, { type: "content_block_start", index: 0, content_block: { type: "tool_use", id: "c1", name: "guarda", input: {} } },
      { type: "content_block_delta", index: 0, delta: { type: "input_json_delta", partial_json: "{}" } }, { type: "content_block_stop", index: 0 },
      { type: "message_delta", delta: { stop_reason: "tool_use" }, usage: { output_tokens: 5 } }]);
  }
  return sse([uso, ...testo("Fatto, Sir."), { type: "message_delta", delta: { stop_reason: "end_turn" }, usage: { output_tokens: 5 } }]);
};
const chiedi = async (frase: string, extra: Record<string, unknown> = {}, strumenti_client: string[] = []) => {
  chiamate.length = 0;
  const r = await C.__servi(new Request("http://x/jarvis", { method: "POST", headers: { "x-jarvis-token": "prova", "content-type": "application/json" },
    body: JSON.stringify({ messaggi: [{ role: "user", content: frase }], dispositivo: "iphone", strumenti_client, senza_filo: true, ...extra }) }));
  return (await r.text()).split("\n").filter(Boolean).map((l) => JSON.parse(l));
};
g.__tab = {};
// una frase che va su Opus ma non è un ragionamento («ricord» la manda su Opus)
await chiedi("ricordami cosa avevamo detto ieri sulle chiavi della macchina", { a_voce: true });
atteso("1. Opus a voce, domanda semplice: sforzo «low»", chiamate[0]?.model.includes("opus") && chiamate[0]?.effort === "low", chiamate);
await chiedi("ricordami cosa avevamo detto ieri sulle chiavi della macchina");
atteso("2. la stessa frase senza «a_voce» (scritta, o app vecchia): Opus come prima, senza parametro", chiamate[0]?.model.includes("opus") && chiamate[0]?.effort === null, chiamate);
await chiedi("analizza gli incassi della serata di sabato e confrontali con la settimana prima", { a_voce: true });
atteso("3. ragionamento vero a voce: Opus resta «medium» (nessun parametro)", chiamate[0]?.model.includes("opus") && chiamate[0]?.effort === null, chiamate);
await chiedi("spiegami bene come funziona il contratto di affitto del locale e quali clausole devo guardare prima di firmare", { a_voce: true });
atteso("4. «spiegami bene» a voce: «medium»", chiamate[0]?.model.includes("opus") && chiamate[0]?.effort === null, chiamate);
await chiedi("Wiretap: il verbale della registrazione (12 min).", { a_voce: true, allegato: "Matteo: allora sabato apriamo alle undici. Bea: va bene." });
atteso("5. Wiretap: «medium» anche se arriva a voce", chiamate[0]?.effort === null, chiamate);
await chiedi("che tempo fa domani a Milano?", { a_voce: true });
atteso("6. Sonnet resta «low» come prima", /sonnet/.test(chiamate[0]?.model) && chiamate[0]?.effort === "low", chiamate);
// strumento del dispositivo: il segno «|voce» viaggia nel modello e torna con «continua»
conStrumento = true;
const righe = await chiedi("ricordami come si chiamava il disco che ti ho fatto vedere ieri", { a_voce: true }, ["guarda"]);
const cl = righe.find((e) => e.t === "client");
atteso("7. il passaggio al dispositivo porta «modello|voce»", typeof cl?.modello === "string" && cl.modello.endsWith("|voce"), cl?.modello);
chiamate.length = 0;
const r8 = await C.__servi(new Request("http://x/jarvis", { method: "POST", headers: { "x-jarvis-token": "prova", "content-type": "application/json" },
  body: JSON.stringify({ messaggi: [], dispositivo: "iphone", strumenti_client: ["guarda"], continua: { lavoro: cl?.lavoro, modello: cl?.modello, azioni: [], detto: "",
    risultati: [{ tool_use_id: "c1", content: "un disco dei Daft Punk" }] } }) }));
await r8.text();
atteso("8. dopo lo strumento: stesso modello Opus e ancora «low»", chiamate[0]?.model.includes("opus") && chiamate[0]?.effort === "low", chiamate);
chiamate.length = 0;
const r9 = await C.__servi(new Request("http://x/jarvis", { method: "POST", headers: { "x-jarvis-token": "prova", "content-type": "application/json" },
  body: JSON.stringify({ messaggi: [], dispositivo: "iphone", strumenti_client: ["guarda"], continua: { lavoro: cl?.lavoro, modello: String(cl?.modello).split("|")[0], azioni: [], detto: "",
    risultati: [{ tool_use_id: "c1", content: "un disco" }] } }) }));
await r9.text();
conStrumento = false;
atteso("9. «continua» di un'app vecchia (modello senza segno): Opus senza parametro, come prima", chiamate.length === 1 && chiamate[0].model.includes("opus") && chiamate[0].effort === null, chiamate);
Deno.env.set("OPUS_VOCE_SFORZO", "off");
await chiedi("ricordami cosa avevamo detto ieri sulle chiavi della macchina", { a_voce: true });
atteso("10. OPUS_VOCE_SFORZO=off: Opus torna senza parametro", chiamate[0]?.effort === null, chiamate);
Deno.env.delete("OPUS_VOCE_SFORZO");
console.log("prove sforzo: sbagliate", ko);
