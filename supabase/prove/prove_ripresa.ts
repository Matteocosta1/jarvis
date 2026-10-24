// Decisione 53 (24 ott): «continua» dopo un'interruzione riprende con lo STESSO modello della risposta interrotta, non con la riserva.
// Cervello vero (copia di prepara.sh), Anthropic finto: si guarda quale modello riceve la richiesta.
import * as C from "./cervello_test.ts";
let ko = 0; const atteso = (n: string, v: boolean, info: unknown = "") => { if (!v) { ko++; console.log("✗", n, JSON.stringify(info)); } else console.log("✓", n); };
const modelli: string[] = [];
(globalThis as any).fetch = async (u: any, o?: any) => {
  const url = String(u?.url ?? u);
  if (!url.includes("api.anthropic.com")) return new Response("{}", { status: 200 });
  const corpo = JSON.parse(o.body);
  if (corpo.stream !== true) return new Response(JSON.stringify({ content: [{ type: "text", text: "[]" }] }));
  modelli.push(corpo.model);
  const ev = [{ type: "message_start", message: { usage: { input_tokens: 5 } } }, { type: "content_block_start", index: 0, content_block: { type: "text", text: "" } },
    { type: "content_block_delta", index: 0, delta: { type: "text_delta", text: "Riprendo." } }, { type: "content_block_stop", index: 0 },
    { type: "message_delta", delta: { stop_reason: "end_turn" }, usage: { output_tokens: 3 } }];
  return new Response(ev.map((e) => `data: ${JSON.stringify(e)}\n\n`).join(""), { status: 200 });
};
const modelloPer = async (messaggi: { role: string; content: string }[], dispositivo = "iphone") => {
  modelli.length = 0;
  await (await C.__servi(new Request("http://x/jarvis", { method: "POST", headers: { "x-jarvis-token": "prova", "content-type": "application/json" },
    body: JSON.stringify({ messaggi, dispositivo, strumenti_client: [], senza_filo: true }) }))).text();
  return modelli[0];
};
const OPUS = "claude-opus-5-5", SONNET = "claude-sonnet-5-5", HAIKU = "claude-haiku-5-5";
const u = (t: string) => ({ role: "user", content: t }), a = (t: string) => ({ role: "assistant", content: t });
const lunga = "Spiegami bene come funziona il contratto di affitto del locale e quali clausole devo guardare prima di firmare";
const tagliata = (detto: string, resto: string) => `${detto} (qui il signore mi ha interrotto: non ha sentito il resto, che era «${resto}»)`;
const rispOpus = tagliata("Il contratto ha tre parti che contano.", "La prima è la durata, la seconda il deposito.");

atteso("la domanda lunga va su Opus (premessa)", await modelloPer([u(lunga)]) === OPUS, modelli);
atteso("1. «continua» dopo una risposta di Opus interrotta → Opus", await modelloPer([u(lunga), a(rispOpus), u("continua")]) === OPUS, modelli);
atteso("2. «Jarvis, vai avanti pure» → Opus", await modelloPer([u(lunga), a(rispOpus), u("Jarvis, vai avanti pure")]) === OPUS, modelli);
atteso("3. «sì, continua» → Opus", await modelloPer([u(lunga), a(rispOpus), u("sì, continua")]) === OPUS, modelli);
atteso("4. «dicevi?» → Opus", await modelloPer([u(lunga), a(rispOpus), u("dicevi?")]) === OPUS, modelli);
atteso("5. interrotto prima di cominciare, poi «continua» → Opus",
  await modelloPer([u(lunga), a("(il signore mi ha interrotto prima che cominciassi a parlare: non ha sentito nulla) Il contratto ha tre parti."), u("continua")]) === OPUS, modelli);
atteso("6. due interruzioni di fila: «continua», poi «vai avanti» → ancora Opus",
  await modelloPer([u(lunga), a(rispOpus), u("continua"), a(tagliata("La prima è la durata.", "La seconda il deposito.")), u("vai avanti")]) === OPUS, modelli);
atteso("7. meteo interrotto, «continua» → la riserva, come la risposta di allora",
  await modelloPer([u("che tempo fa domani?"), a(tagliata("Domani a Milano sole pieno", ", massime di diciotto gradi.")), u("continua")]) === SONNET, modelli);
atteso("8. ora interrotta, «continua» → il modello rapido, come allora",
  await modelloPer([u("che ore sono?"), a(tagliata("Sono le nove", " e mezza, Sir.")), u("continua")]) === HAIKU, modelli);
atteso("9. «continua a cercare voli per Roma» è una richiesta nuova (riserva)",
  await modelloPer([u(lunga), a(rispOpus), u("continua a cercare voli per Roma")]) === SONNET, modelli);
atteso("10. «continua» senza interruzione: come prima (riserva)",
  await modelloPer([u(lunga), a("Il contratto ha tre parti che contano: durata, deposito e recesso."), u("continua")]) === SONNET, modelli);
atteso("11. orologio: la risposta era della riserva, «continua» resta sulla riserva",
  await modelloPer([u(lunga), a(rispOpus), u("continua")], "orologio") === SONNET, modelli);
atteso("12. «sì» dopo «La mando?» interrotta resta sulla riserva (non è un «continua»)",
  await modelloPer([u("rispondi a Mario che va bene sabato"), a(tagliata("A Mario scrivo: «Va bene sabato». La mando?", " Altrimenti la cambio.")), u("sì")]) === SONNET, modelli);

console.log("prove ripresa: sbagliate", ko);
Deno.exit(ko ? 1 : 0);
