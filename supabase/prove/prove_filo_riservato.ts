// Decisione 54 (24 ott): i turni di Confidente, Profiler e Wiretap non entrano nel filo della conversazione: né nel riassunto,
// né in [Battute appena uscite…], né nel testo della finestra salvata in jarvis_filo (resta solo un'impronta).
// Cervello vero (prepara.sh), Anthropic finto, database finto con stato.
const qui = new URL(".", import.meta.url).pathname;
Deno.writeTextFileSync(qui + "cervello_stato.ts", Deno.readTextFileSync(qui + "cervello_test.ts").replace('from "./finto_db.ts"', 'from "./finto_db_stato.ts"'));
const C: any = await import(qui + "cervello_stato.ts");
const g = globalThis as any;
let ko = 0; const atteso = (n: string, v: boolean, info: unknown = "") => { if (!v) { ko++; console.log("✗", n, JSON.stringify(info)); } else console.log("✓", n); };
const pausa = (ms: number) => new Promise((ok) => setTimeout(ok, ms));
const riassunti: string[] = [];   // quello che arriva al modello rapido che riassume il filo
let contesto = "";                // il messaggio con il contesto che arriva al modello principale
g.fetch = async (_u: any, o?: any) => {
  const corpo = JSON.parse(o?.body ?? "{}");
  if (corpo.stream === true) {
    const ultimo = corpo.messages.at(-1).content; contesto = typeof ultimo === "string" ? ultimo : ultimo.map((b: any) => b.text ?? "").join("");
    const ev = [{ type: "message_start", message: { usage: {} } }, { type: "content_block_start", index: 0, content_block: { type: "text", text: "" } },
      { type: "content_block_delta", index: 0, delta: { type: "text_delta", text: "Ok." } }, { type: "content_block_stop", index: 0 }, { type: "message_delta", delta: { stop_reason: "end_turn" } }];
    return new Response(ev.map((e) => `data: ${JSON.stringify(e)}\n\n`).join(""));
  }
  if (/Tieni il filo/.test(String(corpo.system))) { riassunti.push(corpo.messages[0].content); return new Response(JSON.stringify({ content: [{ type: "text", text: "Si parlava del meteo." }] })); }
  return new Response(JSON.stringify({ content: [{ type: "text", text: "[]" }] }));
};
const u = (t: string) => ({ role: "user", content: t }), a = (t: string) => ({ role: "assistant", content: t });
const turno = async (messaggi: unknown[]) => {
  await (await C.__servi(new Request("http://x/jarvis", { method: "POST", headers: { "x-jarvis-token": "prova" },
    body: JSON.stringify({ messaggi, dispositivo: "iphone", strumenti_client: [] }) }))).text();
  await pausa(300);   // il filo si aggiorna in sottofondo
};
const filoSalvato = () => JSON.stringify(g.__tab.jarvis_filo ?? []);
g.__tab = {};

// A ─ Confidente dal pannello: «Modalità confidente. …» poi meteo; la finestra scorre e il confidente esce
const conf = u("Modalità confidente. Cosa ne pensi? Dimmi la verità.\n\nBea: SEGRETO-UNO non me lo aspettavo");
const rispConf = a("Capisco, Sir: SEGRETO-UNO pesa, ma lei ha esagerato un poco.");
await turno([conf, rispConf, u("che tempo fa domani?"), a("Sole, Sir."), u("e sabato?")]);
atteso("A. la finestra salvata non contiene il confidente", !filoSalvato().includes("SEGRETO-UNO") && filoSalvato().includes("che tempo fa domani"), filoSalvato().slice(0, 300));
const fin = (g.__tab.jarvis_filo?.[0]?.finestra ?? []) as any[];
atteso("A. al loro posto un'impronta segnata «riservata»", fin[0]?.s === true && fin[0]?.t === "" && !!fin[0]?.h && fin[1]?.s === true && !fin[2]?.s, fin.slice(0, 3));
const adesso2 = [u("che tempo fa domani?"), a("Sole, Sir."), u("e sabato?"), a("Pioggia, Sir."), u("e domenica?")].map((m) => ({ r: m.role, t: m.content }));
atteso("A. con le impronte la finestra nuova si allinea (2 battute uscite)", C.battuteUscite(fin, adesso2) === 2, C.battuteUscite(fin, adesso2));
await turno([u("che tempo fa domani?"), a("Sole, Sir."), u("e sabato?"), a("Pioggia, Sir."), u("e domenica?")]);
atteso("A. la finestra combacia ancora (le impronte bastano): nessuna conversazione nuova", (g.__tab.jarvis_filo?.[0]?.finestra ?? [])[0]?.t === "che tempo fa domani?", g.__tab.jarvis_filo?.[0]?.finestra?.[0]);
atteso("A. il confidente uscito non va al riassunto", !riassunti.some((r) => r.includes("SEGRETO-UNO")), riassunti);
atteso("A. né in [Battute appena uscite…]", !contesto.includes("SEGRETO-UNO"), contesto.slice(0, 400));
// e le battute normali che escono si riassumono come prima
await turno([u("e sabato?"), a("Pioggia, Sir."), u("e domenica?"), a("Nuvole, Sir."), u("grazie")]);
atteso("A. le battute normali che escono vanno al riassunto, come prima", riassunti.some((r) => r.includes("che tempo fa domani")), riassunti);
atteso("A. e compaiono in [Battute appena uscite…]", /Battute appena uscite[^\]]*che tempo fa domani/.test(contesto), contesto.slice(0, 500));

// B ─ Confidente «A voce», aperto da JARVIS: la frase dopo è riservata; l'apertura esce per prima e la storia resta riservata
g.__tab = {}; riassunti.length = 0;
const apre = a("Modalità confidente. Mi racconti pure, Sir: la ascolto.");
const storia = u("Oggi con Bea abbiamo litigato per SEGRETO-DUE e mi sento uno straccio");
const rispStoria = a("Mi dispiace, Sir. SEGRETO-DUE è una cosa che si sistema parlando.");
await turno([apre, storia, rispStoria, u("che tempo fa domani?")]);
await turno([storia, rispStoria, u("che tempo fa domani?"), a("Sole, Sir."), u("e sabato?")]);
atteso("B. la storia resta riservata anche quando l'apertura è uscita", !filoSalvato().includes("SEGRETO-DUE"), filoSalvato().slice(0, 300));
await turno([u("che tempo fa domani?"), a("Sole, Sir."), u("e sabato?"), a("Pioggia, Sir."), u("e domenica?")]);
atteso("B. niente del confidente nel riassunto", !riassunti.some((r) => r.includes("SEGRETO-DUE")), riassunti);
atteso("B. niente nel contesto", !contesto.includes("SEGRETO-DUE"), contesto.slice(0, 300));

// C ─ quali battute sono riservate (la stessa regola dell'archivista e del prompt)
const R = (w: { role: string; content: string }[]) => C.battuteRiservate(w.map((m) => ({ r: m.role, t: m.content })));
atteso("C. Wiretap e il suo verbale", JSON.stringify(R([u("Wiretap: il verbale della registrazione (12 min)."), a("Si è parlato del palco."), u("grazie")])) === "[true,true,false]", R([u("Wiretap: x"), a("y"), u("z")]));
atteso("C. Profiler e la sua scheda", JSON.stringify(R([u("Modalità Profiler: questo è Marco. Fammi la scheda."), a("ESPRESSIONE: sorriso."), u("che ore sono?"), a("Le nove.")])) === "[true,true,false,false]", "");
atteso("C. con la nota dell'app davanti", R([u("(riprendo il discorso: prima avevo detto «x». Ora aggiungo, rispondi solo a questo) Modalità confidente. Ti racconto.")])[0] === true, "");
atteso("C. un discorso normale no", JSON.stringify(R([u("che tempo fa?"), a("Sole."), u("confidenzialmente, che ne pensi del locale?")])) === "[false,false,false]", "");
atteso("C. la domanda dopo la risposta del confidente non è riservata (come per l'archivista)", JSON.stringify(R([conf, rispConf, u("che tempo fa domani?")])) === "[true,true,false]", "");

console.log("prove filo riservato: sbagliate", ko);
Deno.exit(ko ? 1 : 0);
