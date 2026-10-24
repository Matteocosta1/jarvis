// punto 2 (24 ott): righe dei tempi in jarvis_consumi — chiamata, turno, turno che passa al dispositivo, voce
// la copia del cervello preparata da prepara.sh, con il database finto che registra gli insert
const qui = new URL(".", import.meta.url).pathname;
Deno.writeTextFileSync(qui + "cervello_reg.ts", Deno.readTextFileSync(qui + "cervello_test.ts").replace('from "./finto_db.ts"', 'from "./finto_db_reg.ts"'));
Deno.env.set("ELEVENLABS_API_KEY", "finta"); Deno.env.set("ELEVENLABS_MODELLO", Deno.env.get("ELEVENLABS_MODELLO") ?? "eleven_v4_turbo");
const C = await import(qui + "cervello_reg.ts");
const sse = (ev: unknown[], ritardo = 0) => new Response(new ReadableStream({ async start(c) { for (const e of ev) { if (ritardo) await new Promise((r) => setTimeout(r, ritardo)); c.enqueue(new TextEncoder().encode(`event: x\ndata: ${JSON.stringify(e)}\n\n`)); } c.close(); } }), { status: 200 });
const testoPoi = (t: string, strumento?: { name: string; input: unknown }) => [
  { type: "message_start", message: { usage: { input_tokens: 10 } } },
  { type: "content_block_start", index: 0, content_block: { type: "text", text: "" } },
  { type: "content_block_delta", index: 0, delta: { type: "text_delta", text: t } },
  { type: "content_block_stop", index: 0 },
  ...(strumento ? [{ type: "content_block_start", index: 1, content_block: { type: "tool_use", id: "tu1", name: strumento.name, input: {} } },
    { type: "content_block_delta", index: 1, delta: { type: "input_json_delta", partial_json: JSON.stringify(strumento.input) } },
    { type: "content_block_stop", index: 1 }] : []),
  { type: "message_delta", delta: { stop_reason: strumento ? "tool_use" : "end_turn" }, usage: { output_tokens: 5 } },
];
let scena = "", giro = 0;
globalThis.fetch = (async (u: any, o?: any) => {
  const url = String(u?.url ?? u);
  if (url.includes("elevenlabs")) {
    if (url.includes("/models")) return new Response("[]", { status: 200 });
    (globalThis as any).__xi = JSON.parse(o.body);
    return new Response(new ReadableStream({ async start(c) { await new Promise((r) => setTimeout(r, 120)); c.enqueue(new Uint8Array([1, 2, 3])); await new Promise((r) => setTimeout(r, 80)); c.enqueue(new Uint8Array([4])); c.close(); } }), { status: 200 });
  }
  if (!url.includes("api.anthropic.com")) return new Response(JSON.stringify({ daily: {}, hourly: {}, current: {} }), { status: 200 });
  const corpo = JSON.parse(o.body);
  if (corpo.stream !== true) return new Response(JSON.stringify({ content: [{ type: "text", text: "[]" }] }), { status: 200 });
  giro++;
  if (scena === "guarda") return sse(testoPoi("Guardo.", { name: "guarda", input: {} }), 30);
  if (scena === "rotto") throw new Error("rete giù");
  return giro === 1 ? sse(testoPoi("Un attimo, controllo.", { name: "meteo", input: { citta: "Milano" } }), 30) : sse(testoPoi("Domani a Milano piove dalle tre."), 30);
}) as typeof fetch;
let ko = 0; const atteso = (n: string, v: boolean, info: unknown = "") => { if (!v) { ko++; console.log("✗", n, JSON.stringify(info)); } else console.log("✓", n); };
const ins = () => (globalThis as any).__ins as { tab: string; o: any }[];
const chiedi = async (corpo: unknown) => {
  const r = await C.__servi(new Request("http://x/jarvis", { method: "POST", headers: { "x-jarvis-token": "prova", "content-type": "application/json" }, body: JSON.stringify(corpo) }));
  const t = await (r.body ? new Response(r.body).arrayBuffer() : Promise.resolve(new ArrayBuffer(0)));
  await new Promise((ok) => setTimeout(ok, 50));
  return t;
};
const consumi = (s: string) => ins().filter((x) => x.tab === "jarvis_consumi" && x.o.servizio === s).map((x) => x.o);
// 1. turno con strumento del server: due chiamate a Claude e una riga «turno»
scena = "meteo"; giro = 0; ins().length = 0;
await chiedi({ messaggi: [{ role: "user", content: "che tempo fa domani?" }], dispositivo: "iphone", senza_filo: true });
const cl = consumi("claude"), tu = consumi("turno");
atteso("due righe claude con i tempi", cl.length === 2 && cl.every((o) => o.ms_prima_parola >= 25 && o.ms_totale >= o.ms_prima_parola && o.token_in === 10), cl);
atteso("una riga turno, esito fine", tu.length === 1 && tu[0].esito === "fine" && tu[0].modello && tu[0].ms_prima_parola > 0 && tu[0].ms_totale >= tu[0].ms_prima_parola, tu);
atteso("prima parola del turno = prima chiamata (non la seconda)", tu[0]?.ms_prima_parola < cl[0]?.ms_totale + 40, [tu[0], cl[0]]);
// 2. turno che passa al dispositivo: esito client
scena = "guarda"; giro = 0; ins().length = 0;
await chiedi({ messaggi: [{ role: "user", content: "cosa vedo?" }], dispositivo: "iphone", strumenti_client: ["guarda"], senza_filo: true });
atteso("turno passato all'iPhone: esito client", consumi("turno").length === 1 && consumi("turno")[0].esito === "client", consumi("turno"));
// 3. il seguito (continua) si registra come turno_seguito
scena = "meteo"; giro = 1; ins().length = 0;
await chiedi({ continua: { lavoro: [{ role: "user", content: "cosa vedo?" }, { role: "assistant", content: [{ type: "text", text: "Guardo." }, { type: "tool_use", id: "tu1", name: "guarda", input: {} }] }], risultati: [{ tool_use_id: "tu1", content: "foto" }], modello: "claude-sonnet-5-5", azioni: ["guarda"], detto: "Guardo. " }, dispositivo: "iphone", senza_filo: true });
atteso("seguito: turno_seguito con esito fine", consumi("turno_seguito").length === 1 && consumi("turno_seguito")[0].esito === "fine" && consumi("turno").length === 0, ins().map((x) => x.o));
// 4. errore: si registra lo stesso
scena = "rotto"; giro = 0; ins().length = 0;
await chiedi({ messaggi: [{ role: "user", content: "ciao" }], dispositivo: "iphone", senza_filo: true });
atteso("errore: riga turno con esito errore e prima parola vuota", consumi("turno").length === 1 && consumi("turno")[0].esito === "errore" && consumi("turno")[0].ms_prima_parola === null, consumi("turno"));
// 5. prova generale: nessuna riga turno
scena = "meteo"; giro = 0; ins().length = 0;
await chiedi({ messaggi: [{ role: "user", content: "che tempo fa?" }], dispositivo: "iphone", senza_filo: true, prova_generale: true });
atteso("prova generale: niente riga turno", consumi("turno").length === 0, consumi("turno"));
// 6. voce in streaming e intera: primo suono e totale
ins().length = 0;
await chiedi({ voce: "Buongiorno, Sir.", flusso: true });
const vf = consumi("voce");
atteso("voce in streaming: primo suono ~120 ms, totale dopo", vf.length === 1 && vf[0].ms_primo_suono >= 100 && vf[0].ms_totale >= vf[0].ms_primo_suono + 60 && vf[0].caratteri > 0, vf);
ins().length = 0;
await chiedi({ voce: "Buongiorno, Sir." });
const vi = consumi("voce");
atteso("voce intera: primo suono = totale", vi.length === 1 && vi[0].ms_primo_suono === vi[0].ms_totale && vi[0].ms_totale >= 180, vi);
// 7. punto 4: «prima» arriva a ElevenLabs come previous_text, con le pronunce; senza «prima» niente previous_text
await chiedi({ voce: "Le conviene l'ombrello.", flusso: true, prima: "Domani a Milano, Sir, piove su Spotify." });
const xi = (globalThis as any).__xi;
atteso("voce con prima: previous_text con le pronunce", xi?.previous_text === "Domani a Milano, Sir, piove su Spòtifai." && xi?.text === "Le conviene l'ombrello.", xi);
await chiedi({ voce: "Accesa, Sir.", flusso: true });
atteso("voce senza prima: niente previous_text", !("previous_text" in ((globalThis as any).__xi ?? {})), (globalThis as any).__xi);
await chiedi({ voce: "Dopo.", prima: "x".repeat(900) + " fine." });
atteso("prima tagliato agli ultimi 300 caratteri", (globalThis as any).__xi?.previous_text?.length <= 300 && (globalThis as any).__xi.previous_text.endsWith("fine."), (globalThis as any).__xi?.previous_text?.length);
console.log("prove tempi: sbagliate", ko); Deno.exit(ko ? 1 : 0);
