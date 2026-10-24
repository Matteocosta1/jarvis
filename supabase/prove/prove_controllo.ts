// Controllo totale (24 ott): prove delle correzioni del ramo claude/controllo-cervello, sul cervello vero (copia di prepara.sh)
// con Anthropic finto e database finto che registra gli insert.
// A) il signore interrompe (l'app chiude la linea): riga «claude» con i token d'ingresso (esito «interrotta»), turno «interrotto»,
//    e la lettura da Anthropic si ferma; B) «sveglia» dà la chiave della cache voce con il modello fisso;
// C) il filo riassume solo ciò che il signore ha sentito; D) l'archivista salta le modalità riservate anche con le note dell'app;
// E) «sì» dopo «La mando?» detto e poi interrotto → modello di riserva, non il rapido.
const qui = new URL(".", import.meta.url).pathname;
Deno.writeTextFileSync(qui + "cervello_reg.ts", Deno.readTextFileSync(qui + "cervello_test.ts").replace('from "./finto_db.ts"', 'from "./finto_db_reg.ts"'));
Deno.env.set("ELEVENLABS_MODELLO", "eleven_v4_turbo");
const C = await import(qui + "cervello_reg.ts");
let ko = 0; const atteso = (n: string, v: boolean, info: unknown = "") => { if (!v) { ko++; console.log("✗", n, JSON.stringify(info)); } else console.log("✓", n); };
const ins = () => (globalThis as any).__ins as { tab: string; o: any }[];
const pausa = (ms: number) => new Promise((ok) => setTimeout(ok, ms));
let letti = 0, scena = "";
const rapide: any[] = [], modelli: string[] = [];
const ev = (t: string[]) => [{ type: "message_start", message: { usage: { input_tokens: 120, cache_read_input_tokens: 30000 } } },
  { type: "content_block_start", index: 0, content_block: { type: "text", text: "" } },
  ...t.map((x) => ({ type: "content_block_delta", index: 0, delta: { type: "text_delta", text: x } })),
  { type: "content_block_stop", index: 0 }, { type: "message_delta", delta: { stop_reason: "end_turn" }, usage: { output_tokens: 40 } }];
globalThis.fetch = (async (u: any, o?: any) => {
  const url = String(u?.url ?? u);
  if (!url.includes("api.anthropic.com")) return new Response("{}", { status: 200 });
  const corpo = JSON.parse(o.body);
  if (corpo.stream !== true) { rapide.push(corpo); return new Response(JSON.stringify({ content: [{ type: "text", text: scena === "filo" ? "Riassunto." : "[]" }] }), { status: 200 }); }
  modelli.push(corpo.model);
  const eventi = scena === "lungo" ? ev(Array.from({ length: 40 }, (_, k) => `Frase numero ${k}. `)) : ev(["Va bene, Sir."]);
  letti = 0;
  return new Response(new ReadableStream({
    async pull(c) { if (letti >= eventi.length) { c.close(); return; } if (scena === "lungo") await pausa(60); c.enqueue(new TextEncoder().encode(`data: ${JSON.stringify(eventi[letti++])}\n\n`)); },
  }), { status: 200 });
}) as typeof fetch;
const richiesta = (corpo: unknown) => C.__servi(new Request("http://x/jarvis", { method: "POST", headers: { "x-jarvis-token": "prova", "content-type": "application/json" }, body: JSON.stringify(corpo) }));

// A ─ interruzione
scena = "lungo"; ins().length = 0;
const r = await richiesta({ messaggi: [{ role: "user", content: "raccontami una storia lunga" }], dispositivo: "iphone", strumenti_client: [], senza_filo: true });
const rd = r.body!.getReader();
await rd.read(); await rd.read(); await rd.cancel();
const alTaglio = letti;
await pausa(1500);
const claude = ins().find((x) => x.tab === "jarvis_consumi" && x.o.servizio === "claude");
const turno = ins().find((x) => x.tab === "jarvis_consumi" && x.o.servizio === "turno");
atteso("A. riga claude anche se interrotta, con i token d'ingresso", !!claude && claude.o.token_in === 120 && claude.o.token_cache === 30000 && claude.o.esito === "interrotta", claude);
atteso("A. uscita stimata dai caratteri già arrivati (non zero)", !!claude && claude.o.token_out > 0, claude);
atteso("A. turno «interrotto», non «errore»", turno?.o.esito === "interrotto", turno);
atteso("A. la lettura da Anthropic si ferma subito", letti - alTaglio <= 3, { alTaglio, letti });
// e una risposta normale scrive una riga sola, senza esito «interrotta»
scena = "breve"; ins().length = 0;
await new Response((await richiesta({ messaggi: [{ role: "user", content: "che ore sono adesso a Tokyo, più o meno?" }], dispositivo: "iphone", strumenti_client: [], senza_filo: true })).body).text();
await pausa(100);
const righeClaude = ins().filter((x) => x.tab === "jarvis_consumi" && x.o.servizio === "claude");
atteso("A. risposta normale: una riga claude, token veri", righeClaude.length === 1 && righeClaude[0].o.token_out === 40 && !righeClaude[0].o.esito, righeClaude);

// B ─ chiave della cache voce
const sv = await (await richiesta({ sveglia: true })).json();
atteso("B. sveglia: voce con il modello fisso", sv.voce === "onwK4e9ZLuTAKqWW03F9·eleven_v4_turbo", sv);
Deno.env.delete("ELEVENLABS_MODELLO");
const sv2 = await (await richiesta({ sveglia: true })).json();
atteso("B. senza modello fisso: solo la voce (come prima)", sv2.voce === "onwK4e9ZLuTAKqWW03F9", sv2);

// C ─ il filo
const interrotta = "Domani a Milano piove dalle tre. (qui il signore mi ha interrotto: il resto non l'ho detto) Porti l'ombrello e le scarpe buone.";
atteso("C. JARVIS: solo la parte sentita", C.battutaPerFilo({ r: "assistant", t: interrotta }) === "Domani a Milano piove dalle tre. (qui il signore l'ha interrotto)", C.battutaPerFilo({ r: "assistant", t: interrotta }));
atteso("C. JARVIS interrotto prima di parlare", C.battutaPerFilo({ r: "assistant", t: "(il signore mi ha interrotto prima che cominciassi a parlare: non ha sentito nulla) Lungo discorso." }) === "(interrotto prima di cominciare a rispondere)");
atteso("C. signore: senza la nota dell'app", C.battutaPerFilo({ r: "user", t: "(ti ho interrotto mentre rispondevi a «che tempo fa?». Se questa frase completa, corregge o aggiunge qualcosa a quella richiesta, rispondi tenendo conto di tutte e due insieme; se è una domanda nuova, rispondi solo a questa, senza riprendere la risposta interrotta) e a Roma?" }) === "e a Roma?");
scena = "filo"; rapide.length = 0;
await C.aggiornaFilo("iphone", "", [{ r: "user", t: "che tempo fa domani?" }, { r: "assistant", t: interrotta }], [{ r: "user", t: "e a Roma?" }]);
const inviato = String(rapide.at(-1)?.messages?.[0]?.content ?? "");
atteso("C. il modello rapido non riceve il resto non detto", inviato.includes("piove dalle tre") && !inviato.includes("ombrello"), inviato);

// D ─ l'archivista e le modalità riservate
const lungo = "Ieri sera con Beatrice abbiamo litigato per la cena e non so come rimediare, ci tengo davvero tanto";
const prova = async (lavoro: any[]) => { rapide.length = 0; scena = "memoria"; await C.memoriaAutomatica(lavoro, "Capisco, Sir."); return rapide.length; };
atteso("D. «Modalità confidente» dietro la nota «riprendo il discorso»: niente archivista",
  await prova([{ role: "user", content: `[Contesto: x]\n[Memoria:\n- (ancora niente)]\n\n(riprendo il discorso: se questo completa o aggiunge qualcosa a quello che ti ho detto prima, rispondi tenendo conto di entrambe le cose; se è un argomento nuovo, rispondi solo a questo) Modalità confidente. ${lungo}` }]) === 0);
atteso("D. confidente aperto da JARVIS («A voce»): niente archivista",
  await prova([{ role: "assistant", content: "Modalità confidente. Mi racconti pure, Sir: la ascolto." }, { role: "user", content: `[Contesto: x]\n[Memoria:\n- (ancora niente)]\n\n${lungo}` }]) === 0);
atteso("D. «ok» con la nota davanti: niente archivista",
  await prova([{ role: "user", content: "[Contesto: x]\n[Memoria:\n- (ancora niente)]\n\n(ti ho interrotto mentre rispondevi a «che tempo fa?». Se questa frase completa, corregge o aggiunge qualcosa a quella richiesta, rispondi tenendo conto di tutte e due insieme; se è una domanda nuova, rispondi solo a questa, senza riprendere la risposta interrotta) ok" }]) === 0);
atteso("D. discorso normale: l'archivista lavora come prima",
  await prova([{ role: "user", content: `[Contesto: x]\n[Memoria:\n- (ancora niente)]\n\nMatteo è il mio socio in Discosizer da tre anni, ricordatelo bene` }]) === 1);

// E ─ «sì» dopo una domanda sentita e poi interrotta
scena = "breve"; modelli.length = 0;
await new Response((await richiesta({ messaggi: [{ role: "user", content: "rispondi a Mario che va bene" }],
  dispositivo: "iphone", strumenti_client: [], senza_filo: true })).body).text();
modelli.length = 0;
await new Response((await richiesta({ messaggi: [{ role: "user", content: "rispondi a Mario che va bene" },
  { role: "assistant", content: "A Mario scrivo: «Va bene, a sabato». La mando? (qui il signore mi ha interrotto: il resto non l'ho detto) Altrimenti la cambio." },
  { role: "user", content: "(ti ho interrotto mentre rispondevi a «rispondi a Mario che va bene». Se questa frase completa, corregge o aggiunge qualcosa a quella richiesta, rispondi tenendo conto di tutte e due insieme; se è una domanda nuova, rispondi solo a questa, senza riprendere la risposta interrotta) sì" }],
  dispositivo: "iphone", strumenti_client: [], senza_filo: true })).body).text();
atteso("E. «sì» dopo «La mando?» sentito: modello di riserva", modelli[0] === "claude-sonnet-5-5", modelli);
modelli.length = 0;
await new Response((await richiesta({ messaggi: [{ role: "user", content: "accendi la torcia" }, { role: "assistant", content: "Accesa, Sir." }, { role: "user", content: "grazie" }],
  dispositivo: "iphone", strumenti_client: [], senza_filo: true })).body).text();
atteso("E. «grazie» dopo una conferma: resta il modello rapido", modelli[0] === "claude-haiku-5-5", modelli);

console.log("prove controllo: sbagliate", ko);
Deno.exit(ko ? 1 : 0);
