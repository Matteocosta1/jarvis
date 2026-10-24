// Idea B (25 ott): un solo JARVIS risponde quando più dispositivi mandano la stessa frase detta a voce.
// Cervello vero (copia di prepara.sh) con Anthropic finto e database finto con stato (finto_db_stato.ts).
const qui = new URL(".", import.meta.url).pathname;
Deno.writeTextFileSync(qui + "cervello_stato.ts", Deno.readTextFileSync(qui + "cervello_test.ts").replace('from "./finto_db.ts"', 'from "./finto_db_stato.ts"'));
const C = await import(qui + "cervello_stato.ts");
const g = globalThis as any;
let ko = 0; const atteso = (n: string, v: boolean, info: unknown = "") => { if (!v) { ko++; console.log("✗", n, JSON.stringify(info)); } else console.log("✓", n); };
const pausa = (ms: number) => new Promise((ok) => setTimeout(ok, ms));
const enc = new TextEncoder();
let anthropic = 0;
g.fetch = async (u: any, o?: any) => {
  const url = String(u?.url ?? u);
  if (!url.includes("api.anthropic.com")) return new Response("{}", { status: 200 });
  const corpo = JSON.parse(o.body);
  if (corpo.stream !== true) return new Response(JSON.stringify({ content: [{ type: "text", text: "[]" }] }));
  anthropic++;
  const ev = [{ type: "message_start", message: { usage: { input_tokens: 5 } } },
    { type: "content_block_start", index: 0, content_block: { type: "text", text: "" } },
    { type: "content_block_delta", index: 0, delta: { type: "text_delta", text: "Domani sole, Sir." } }, { type: "content_block_stop", index: 0 },
    { type: "message_delta", delta: { stop_reason: "end_turn" }, usage: { output_tokens: 5 } }];
  return new Response(new ReadableStream({ start(c) { for (const e of ev) c.enqueue(enc.encode(`data: ${JSON.stringify(e)}\n\n`)); c.close(); } }));
};
const IPHONE = "11111111-aaaa-4aaa-8aaa-111111111111", MAC = "22222222-bbbb-4bbb-8bbb-222222222222", POLSO = "33333333-cccc-4ccc-8ccc-333333333333";
const manda = (frase: string, id: string | null, fine: number, dispositivo = "iphone") => C.__servi(new Request("http://x/jarvis", { method: "POST",
  headers: { "x-jarvis-token": "prova", "content-type": "application/json" },
  body: JSON.stringify({ messaggi: [{ role: "user", content: frase }], dispositivo, strumenti_client: [], senza_filo: true, a_voce: true,
    ...(id ? { arbitro: { id, fine } } : {}) }) }));
const righe = async (r: Response) => (await r.text()).split("\n").filter(Boolean).map((l) => JSON.parse(l));
const esito = (rr: any[]) => rr.some((e) => e.t === "doppione") ? "tace" : rr.some((e) => e.t === "fine") ? "risponde" : "?";
const azzera = () => { g.__tab = {}; anthropic = 0; };

// 1 ─ un dispositivo solo: risponde subito, senza attese
azzera();
let t0 = Date.now();
const r1 = await righe(await manda("che tempo fa domani?", IPHONE, Date.now()));
const ms1 = Date.now() - t0;
atteso("1. un dispositivo solo risponde", esito(r1) === "risponde" && anthropic === 1, r1);
atteso("1. nessuna attesa dell'arbitro (meno di 250 ms in tutto)", ms1 < 250, ms1);
atteso("1. la frase è segnata come vinta", (g.__tab.jarvis_arbitro ?? []).length === 1 && g.__tab.jarvis_arbitro[0].vince === true, g.__tab.jarvis_arbitro);

// 2 ─ iPhone e Mac, la stessa frase quasi insieme (dispositivi fermi da prima): risponde uno solo
azzera();
let fine = Date.now();
const [a2, b2] = await Promise.all([manda("Jarvis, che tempo fa domani?", IPHONE, fine).then(righe),
  pausa(40).then(() => manda("che tempo fa domani", MAC, fine + 150, "mac")).then(righe)]);
atteso("2. iPhone + Mac: uno risponde e uno tace", [esito(a2), esito(b2)].sort().join(",") === "risponde,tace", [esito(a2), esito(b2)]);
atteso("2. Claude chiamato una volta sola", anthropic === 1, anthropic);
const turni2 = (g.__tab.jarvis_consumi ?? []).filter((x: any) => x.servizio === "turno").map((x: any) => x.esito).sort();
atteso("2. nei tempi un turno «fine» e uno «doppione»", turni2.join(",") === "doppione,fine", turni2);

// 3 ─ frasi diverse dai due dispositivi: rispondono tutti e due
azzera();
fine = Date.now();
const [a3, b3] = await Promise.all([manda("che tempo fa domani?", IPHONE, fine).then(righe),
  pausa(30).then(() => manda("metti un timer di dieci minuti", MAC, fine + 100, "mac")).then(righe)]);
atteso("3. frasi diverse: rispondono tutti e due", esito(a3) === "risponde" && esito(b3) === "risponde", [esito(a3), esito(b3)]);

// 4 ─ lo stesso dispositivo ripete la stessa frase: non è un doppione
azzera();
const a4 = await righe(await manda("che ore sono?", IPHONE, Date.now()));
const b4 = await righe(await manda("che ore sono?", IPHONE, Date.now()));
atteso("4. stesso dispositivo, stessa frase due volte: risponde due volte", esito(a4) === "risponde" && esito(b4) === "risponde", [esito(a4), esito(b4)]);

// 5 ─ la copia arriva tardi (il primo ha già vinto): tace
azzera();
fine = Date.now();
const a5 = await righe(await manda("raccontami una barzelletta", POLSO, fine, "orologio"));
await pausa(600);
const b5 = await righe(await manda("raccontami una barzelletta", MAC, fine + 300, "mac"));
atteso("5. arriva dopo che il primo ha vinto: il secondo tace", esito(a5) === "risponde" && esito(b5) === "tace", [esito(a5), esito(b5)]);

// 6 ─ dispositivi già attivi tutti e due: vince chi ha sentito finire la frase per primo, anche se arriva dopo
azzera();
fine = Date.now();
g.__tab.jarvis_arbitro = [{ id: 1, dispositivo: MAC, tipo: "mac", testo: "altro", fine: fine - 30_000, parole: 1, creata: new Date(Date.now() - 30_000).toISOString(), vince: true },
  { id: 2, dispositivo: IPHONE, tipo: "iphone", testo: "altro ancora", fine: fine - 20_000, parole: 2, creata: new Date(Date.now() - 20_000).toISOString(), vince: true }];
const [a6, b6] = await Promise.all([manda("che tempo fa domani?", IPHONE, fine + 1000).then(righe),
  pausa(60).then(() => manda("che tempo fa domani?", MAC, fine, "mac")).then(righe)]);
atteso("6. vince il Mac, che l'ha sentita finire un secondo prima (anche se è arrivato dopo)", esito(a6) === "tace" && esito(b6) === "risponde", [esito(a6), esito(b6)]);

// 7 ─ a pari tempo vince chi ha sentito più parole
azzera();
fine = Date.now();
g.__tab.jarvis_arbitro = [{ id: 1, dispositivo: MAC, tipo: "mac", testo: "x", fine: fine - 30_000, parole: 1, creata: new Date(Date.now() - 30_000).toISOString(), vince: true }];
const [a7, b7] = await Promise.all([manda("che tempo fa domani a Milano?", IPHONE, fine).then(righe),
  pausa(40).then(() => manda("tempo fa domani a Milano?", MAC, fine + 50, "mac")).then(righe)]);
atteso("7. stesso momento: vince chi ha sentito tutta la frase", esito(a7) === "risponde" && esito(b7) === "tace", [esito(a7), esito(b7)]);

// 8 ─ senza «arbitro» (scritta, o app vecchia): nessun controllo
azzera();
await righe(await manda("che tempo fa domani?", null, Date.now()));
atteso("8. senza arbitro nessuna riga e nessun controllo", !(g.__tab.jarvis_arbitro ?? []).length && anthropic === 1, g.__tab.jarvis_arbitro);

// 9 ─ il database dell'arbitro non funziona: la frase risponde lo stesso (meglio due voci che nessuna)
azzera();
g.__tab.jarvis_arbitro = { rotto: true };      // il finto database si inceppa su questa tabella
const r9 = await righe(await manda("che tempo fa domani?", MAC, Date.now(), "mac"));
atteso("9. arbitro guasto: risponde", esito(r9) === "risponde", r9);

// 10 ─ id non valido: nessun controllo, risponde
azzera();
const r10 = await righe(await manda("che tempo fa domani?", "x", Date.now()));
atteso("10. id dispositivo non valido: risponde senza arbitro", esito(r10) === "risponde" && !(g.__tab.jarvis_arbitro ?? []).length, r10);

console.log("prove arbitro: sbagliate", ko);
