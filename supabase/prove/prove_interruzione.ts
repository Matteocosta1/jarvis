// Decisione 4 (24 ott): dopo un'interruzione (l'app chiude la linea) il cervello si ferma subito: nessun nuovo giro con Claude,
// nessun modello di riserva, nessun passaggio al dispositivo; lo strumento già partito finisce e resta nel registro,
// quelli non ancora partiti non partono; la chiamata in corso si chiude anche quando il modello non sta scrivendo.
// Cervello vero (copia di prepara.sh) con Anthropic finto e database finto con stato (finto_db_stato.ts).
const qui = new URL(".", import.meta.url).pathname;
Deno.writeTextFileSync(qui + "cervello_stato.ts", Deno.readTextFileSync(qui + "cervello_test.ts").replace('from "./finto_db.ts"', 'from "./finto_db_stato.ts"'));
const C = await import(qui + "cervello_stato.ts");
const g = globalThis as any;
let ko = 0; const atteso = (n: string, v: boolean, info: unknown = "") => { if (!v) { ko++; console.log("✗", n, JSON.stringify(info)); } else console.log("✓", n); };
const pausa = (ms: number) => new Promise((ok) => setTimeout(ok, ms));
const enc = new TextEncoder();

let scena = "";
const anthropic: string[] = [];          // modello di ogni chiamata ad Anthropic
const meteoChiesto: string[] = [];       // località cercate dallo strumento meteo
let letti = 0;                           // eventi del flusso Anthropic letti dal cervello (scena «client»)
const uso = { type: "message_start", message: { usage: { input_tokens: 50, cache_read_input_tokens: 1000 } } };
const strumento = (i: number, id: string, nome: string, input: unknown) => [
  { type: "content_block_start", index: i, content_block: { type: "tool_use", id, name: nome, input: {} } },
  { type: "content_block_delta", index: i, delta: { type: "input_json_delta", partial_json: JSON.stringify(input) } },
  { type: "content_block_stop", index: i }];
const testo = (i: number, t: string) => [{ type: "content_block_start", index: i, content_block: { type: "text", text: "" } },
  { type: "content_block_delta", index: i, delta: { type: "text_delta", text: t } }, { type: "content_block_stop", index: i }];
const fineCon = (stop: string) => ({ type: "message_delta", delta: { stop_reason: stop }, usage: { output_tokens: 20 } });
const sse = (eventi: unknown[], ritardo = 0) => new Response(new ReadableStream({
  async pull(c) {
    if (letti >= eventi.length) { c.close(); return; }
    if (ritardo) await pausa(ritardo);
    c.enqueue(enc.encode(`data: ${JSON.stringify(eventi[letti++])}\n\n`));
  },
}), { status: 200 });

g.fetch = async (u: any, o?: any) => {
  const url = String(u?.url ?? u);
  if (url.includes("geocoding-api.open-meteo.com")) {
    const luogo = new URL(url).searchParams.get("name") ?? "";
    meteoChiesto.push(luogo);
    await pausa(1500);                   // uno strumento lento: il signore interrompe mentre lavora
    return new Response(JSON.stringify({ results: [{ name: luogo, latitude: 45, longitude: 9 }] }));
  }
  if (url.includes("api.open-meteo.com")) return new Response(JSON.stringify({ current: { temperature_2m: 12, weather_code: 0 }, daily: { time: [] } }));
  if (!url.includes("api.anthropic.com")) return new Response("{}", { status: 200 });
  const corpo = JSON.parse(o.body);
  if (corpo.stream !== true) return new Response(JSON.stringify({ content: [{ type: "text", text: "[]" }] }));
  anthropic.push(corpo.model);
  letti = 0;
  const giro = corpo.messages.at(-1)?.role === "user" && Array.isArray(corpo.messages.at(-1).content) && corpo.messages.at(-1).content.some((b: any) => b.type === "tool_result");
  if (giro) return sse([uso, ...testo(0, "Domani sole, Sir."), fineCon("end_turn")]);
  if (scena === "strumento") return sse([uso, ...testo(0, "Un attimo, controllo."), ...strumento(1, "t1", "meteo", { luogo: "Roma", giorni: 1 }), fineCon("tool_use")]);
  if (scena === "due") return sse([uso, ...strumento(0, "t1", "memoria_salva", { fatto: "Il signore ama il jazz modale", categoria: "preferenze" }),
    ...strumento(1, "t2", "meteo", { luogo: "Roma", giorni: 1 }), ...strumento(2, "t3", "meteo", { luogo: "Parigi", giorni: 1 }), fineCon("tool_use")]);
  if (scena === "client") return sse([uso, ...strumento(0, "c1", "guarda", { cosa: "il disco" }), fineCon("tool_use")], 150);   // il modello prepara lo strumento, muto
  if (scena === "sovraccarico" && corpo.model.includes("opus")) { await pausa(800); return new Response(JSON.stringify({ error: { type: "overloaded_error", message: "Overloaded" } }), { status: 529 }); }
  return sse([uso, ...testo(0, "Eccomi."), fineCon("end_turn")]);
};

const richiesta = (frase: string, strumenti_client: string[] = []) => C.__servi(new Request("http://x/jarvis", { method: "POST",
  headers: { "x-jarvis-token": "prova", "content-type": "application/json" },
  body: JSON.stringify({ messaggi: [{ role: "user", content: frase }], dispositivo: "iphone", strumenti_client, senza_filo: true }) }));
const turni = () => (g.__tab.jarvis_consumi ?? []).filter((r: any) => r.servizio === "turno");
const azzera = () => { g.__tab = {}; anthropic.length = 0; meteoChiesto.length = 0; };
/** l'app legge le prime righe, poi chiude la linea dopo `dopo` ms */
async function interrompi(r: Response, dopo: number) {
  const rd = r.body!.getReader();
  const t0 = Date.now();
  while (Date.now() - t0 < dopo) { const x = await Promise.race([rd.read(), pausa(dopo - (Date.now() - t0)).then(() => null)]); if (x && (x as any).done) break; }
  await rd.cancel();
}

// 1 ─ interruzione mentre uno strumento del cervello lavora: lo strumento finisce, ma nessun nuovo giro con Claude
scena = "strumento"; azzera();
await interrompi(await richiesta("che tempo fa domani a Roma?"), 400);
await pausa(2500);
atteso("1. lo strumento già partito finisce", meteoChiesto.join(",") === "Roma", meteoChiesto);
atteso("1. nessun nuovo giro con Claude dopo lo strumento", anthropic.length === 1, anthropic);
atteso("1. il turno risulta «interrotto»", turni().length === 1 && turni()[0].esito === "interrotto", turni());

// 2 ─ tre strumenti nella stessa risposta: il primo fatto e registrato, il secondo già partito finisce, il terzo non parte
scena = "due"; azzera();
await interrompi(await richiesta("segnati che amo il jazz modale e dimmi il meteo di Roma e Parigi"), 400);
await pausa(2500);
atteso("2. il primo strumento è fatto", (g.__tab.jarvis_memoria ?? []).length === 1, g.__tab.jarvis_memoria);
atteso("2. lo strumento in corso finisce (Roma), quello dopo non parte (Parigi)", meteoChiesto.join(",") === "Roma", meteoChiesto);
const reg = (g.__tab.jarvis_azioni ?? []).map((r: any) => r.strumento);
atteso("2. il fatto resta nel registro delle azioni", reg.includes("memoria_salva"), g.__tab.jarvis_azioni);
atteso("2. nessun nuovo giro con Claude", anthropic.length === 1, anthropic);
atteso("2. turno «interrotto»", turni()[0]?.esito === "interrotto", turni());

// 3 ─ interruzione mentre il modello prepara uno strumento del dispositivo, senza scrivere: la chiamata si chiude subito
// e il lavoro non passa al dispositivo
scena = "client"; azzera();
const r3 = await richiesta("guarda questo disco", ["guarda"]);
const righe3: any[] = [];
const rd3 = r3.body!.getReader();
setTimeout(() => rd3.cancel(), 250);
for (;;) { const x = await rd3.read().catch(() => ({ done: true, value: undefined })); if (x.done) break; for (const l of new TextDecoder().decode(x.value).split("\n").filter(Boolean)) righe3.push(JSON.parse(l)); }
const alTaglio = letti;
await pausa(1500);
atteso("3. la lettura da Anthropic si ferma subito", letti - alTaglio <= 1 && letti < 5, { alTaglio, letti });
atteso("3. nessun passaggio al dispositivo", !righe3.some((e) => e.t === "client") && !turni().some((t: any) => t.esito === "client"), { righe3, turni: turni() });
atteso("3. turno «interrotto»", turni()[0]?.esito === "interrotto", turni());
const claude3 = (g.__tab.jarvis_consumi ?? []).filter((r: any) => r.servizio === "claude");
atteso("3. la chiamata chiusa resta nei conti («interrotta»)", claude3.length === 1 && claude3[0].esito === "interrotta", claude3);

// 4 ─ interruzione mentre il primo modello sta per rispondere «sovraccarico»: il modello di riserva non parte
scena = "sovraccarico"; azzera();
await interrompi(await richiesta("Spiegami bene come funziona il contratto di affitto del locale e quali clausole devo guardare prima di firmare"), 200);
await pausa(1500);
atteso("4. dopo l'interruzione nessun modello di riserva", anthropic.length === 1 && anthropic[0].includes("opus"), anthropic);
atteso("4. turno «interrotto»", turni()[0]?.esito === "interrotto", turni());

// 5 ─ senza interruzione tutto come prima: strumento, secondo giro, risposta
scena = "strumento"; azzera();
const t5 = await (await richiesta("che tempo fa domani a Roma?")).text();
const righe5 = t5.split("\n").filter(Boolean).map((l) => JSON.parse(l));
atteso("5. senza interruzione: secondo giro e risposta", anthropic.length === 2 && righe5.at(-1)?.t === "fine" && /Domani sole/.test(righe5.at(-1)?.testo), { anthropic, fine: righe5.at(-1) });
await pausa(200);
atteso("5. turno «fine»", turni()[0]?.esito === "fine", turni());

console.log("prove interruzione: sbagliate", ko);
Deno.exit(ko ? 1 : 0);
