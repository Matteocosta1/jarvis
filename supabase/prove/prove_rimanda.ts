// Decisioni 50 e 51 (24 ott): invio incerto → «Non so se è partita, Sir: in Inviata non la vedrà.»; dopo 10 minuti la risposta
// si può rimandare, solo con il sì esplicito del signore (rimanda: true). Prima la chiave restava «incerto» per sempre.
// Cervello vero (copia di prepara.sh), server IMAP/SMTP finti (finti_server.ts), database finto con stato (finto_db_stato.ts).
import { imap, smtp, registro, opzioni } from "./finti_server.ts";
const qui = new URL(".", import.meta.url).pathname;
Deno.writeTextFileSync(qui + "cervello_stato.ts", Deno.readTextFileSync(qui + "cervello_test.ts").replace('from "./finto_db.ts"', 'from "./finto_db_stato.ts"'));
const C: any = await import(qui + "cervello_stato.ts");
const g = globalThis as any;
const porte: Record<number, number> = { 993: 47995, 465: 47467 };
(Deno as any).connectTls = (o: any) => Deno.connect({ hostname: "127.0.0.1", port: porte[o.port] });
imap(47995); smtp(47467);
let ko = 0; const atteso = (n: string, v: boolean, info: unknown = "") => { if (!v) { ko++; console.log("✗", n, JSON.stringify(info)); } else console.log("✓", n); };
const NON_SO = "Non so se è partita, Sir: in Inviata non la vedrà.";
const invii = () => registro.smtp.filter((x) => x === "DATA").length;
const chiave = () => (g.__tab.jarvis_cache ?? []).find((r: any) => String(r.chiave).startsWith("risposta:"));
const indietro = (min: number) => { const k = chiave(); k.aggiornato = new Date(Date.now() - min * 60_000).toISOString(); };
opzioni.intestazioni = "From: Mario <mario@rossi.it>\r\nSubject: Sabato\r\nMessage-ID: <q@rossi.it>\r\n\r\n";
const manda = (rimanda?: boolean) => C.postaRispondi({ id: "arrivo:12", testo: "Va bene, a sabato.", ...(rimanda === undefined ? {} : { rimanda }) }, true);

// 1 ─ iCloud non conferma: incerto, con la frase decisa
opzioni.smtpMutoDopoDati = true;
let r = await manda();
atteso("1. incerto con «Non so se è partita, Sir: in Inviata non la vedrà.»", r.ok === false && r.incerto === true && r.errore === NON_SO, r);
atteso("1. rimandabile tra 10 minuti", r.rimandabile === false && r.tra_minuti === 10, r);
atteso("1. la chiave resta «incerto», con l'ora dell'esito", chiave()?.valore?.stato === "incerto" && Date.now() - Date.parse(chiave()?.aggiornato) < 5000, chiave());
opzioni.smtpMutoDopoDati = false;
const dopo1 = invii();

// 2 ─ subito dopo, anche con il sì: non si rimanda (mancano 10 minuti)
r = await manda(true);
atteso("2. prima dei 10 minuti non parte, nemmeno con il sì", r.ok === false && r.incerto === true && r.errore === NON_SO && r.tra_minuti >= 9 && invii() === dopo1, { r, invii: invii() });

// 3 ─ dopo 11 minuti ma senza il sì: non parte, e si può chiedere
indietro(11);
r = await manda();
atteso("3. dopo 10 minuti, senza il sì: non parte, si può proporre", r.ok === false && r.incerto === true && r.rimandabile === true && !r.tra_minuti && invii() === dopo1, { r, invii: invii() });
atteso("3. la nota per il modello chiede il sì esplicito", /sì, rimandala/.test(r.nota ?? "") && /rimanda: true/.test(r.nota ?? ""), r.nota);

// 4 ─ dopo 11 minuti con il sì: parte una volta, la chiave diventa «inviata»
r = await manda(true);
atteso("4. con il sì dopo 10 minuti la rimanda", r.ok === true && invii() === dopo1 + 1, { r, invii: invii() });
atteso("4. chiave «inviata»", chiave()?.valore?.stato === "inviata", chiave());

// 5 ─ un altro sì: era già partita, non la manda due volte
r = await manda(true);
atteso("5. non parte due volte", r.ok === true && /già partita/.test(r.nota ?? "") && invii() === dopo1 + 1, { r, invii: invii() });

// 6 ─ invio rimasto a metà (il cervello si è fermato durante l'invio): dopo 2 minuti è incerto; dopo 10, con il sì, riparte
g.__tab.jarvis_cache = [];
opzioni.smtpMutoDopoDati = false;
const k6 = await manda();   // prima la mando davvero, così la chiave è quella vera
atteso("6. (premessa) invio normale ok", k6.ok === true, k6);
chiave().valore = { stato: "invio", a: "mario@rossi.it" }; indietro(5);
const prima6 = invii();
r = await manda(true);
atteso("6. invio a metà da 5 minuti: incerto, mancano 5 minuti", r.incerto === true && r.errore === NON_SO && r.tra_minuti === 5 && invii() === prima6, r);
indietro(12);
r = await manda(true);
atteso("6. dopo 12 minuti con il sì riparte", r.ok === true && invii() === prima6 + 1, { r, invii: invii() });

// 7 ─ un invio in corso da meno di 2 minuti resta «la sto già inviando» (non cambia)
chiave().valore = { stato: "invio", a: "mario@rossi.it" }; indietro(0.5);
r = await manda(true);
atteso("7. invio in corso: non riparte", r.ok === false && /già inviando/.test(r.errore) && invii() === prima6 + 1, r);

// 8 ─ il modello vede il parametro e la regola
let corpo: any = null;
g.fetch = async (u: any, o?: any) => {
  if (String(u?.url ?? u).includes("api.anthropic.com") && JSON.parse(o.body).stream === true) {
    corpo = JSON.parse(o.body);
    const ev = [{ type: "message_start", message: { usage: {} } }, { type: "content_block_start", index: 0, content_block: { type: "text", text: "" } },
      { type: "content_block_delta", index: 0, delta: { type: "text_delta", text: "Ok." } }, { type: "content_block_stop", index: 0 }, { type: "message_delta", delta: { stop_reason: "end_turn" } }];
    return new Response(ev.map((e) => `data: ${JSON.stringify(e)}\n\n`).join(""));
  }
  return new Response(JSON.stringify({ content: [{ type: "text", text: "[]" }] }));
};
await (await C.__servi(new Request("http://x/jarvis", { method: "POST", headers: { "x-jarvis-token": "prova" },
  body: JSON.stringify({ messaggi: [{ role: "user", content: "rimandala" }], dispositivo: "iphone", strumenti_client: [], senza_filo: true }) }))).text();
const pr = (corpo?.tools ?? []).find((t: any) => t.name === "posta_rispondi");
atteso("8. posta_rispondi ha «rimanda»", pr?.input_schema?.properties?.rimanda?.type === "boolean", pr?.input_schema);
atteso("8. il prompt dice la frase e la regola dei 10 minuti", /Non so se è partita, Sir: in Inviata non la vedrà\./.test(corpo?.system?.[0]?.text) && /dieci minuti/.test(corpo?.system?.[0]?.text), "");

console.log("prove rimanda: sbagliate", ko);
Deno.exit(ko ? 1 : 0);
