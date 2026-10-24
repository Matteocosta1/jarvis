// Decisioni 5, 13, 27, 50 (24 ott): le righe del prompt e i testi fissi cambiati. Si legge il prompt che arriva ad Anthropic
// e il sorgente di jarvis-briefing (accanto al cervello, nel repository).
import * as C from "./cervello_test.ts";
let ko = 0; const atteso = (n: string, v: boolean, info: unknown = "") => { if (!v) { ko++; console.log("✗", n, JSON.stringify(info)); } else console.log("✓", n); };
let sistema = "";
(globalThis as any).fetch = async (_u: any, o?: any) => {
  const corpo = JSON.parse(o?.body ?? "{}");
  if (corpo.stream === true) {
    sistema = corpo.system?.[0]?.text ?? "";
    const ev = [{ type: "message_start", message: { usage: {} } }, { type: "content_block_start", index: 0, content_block: { type: "text", text: "" } },
      { type: "content_block_delta", index: 0, delta: { type: "text_delta", text: "Ok." } }, { type: "content_block_stop", index: 0 }, { type: "message_delta", delta: { stop_reason: "end_turn" } }];
    return new Response(ev.map((e) => `data: ${JSON.stringify(e)}\n\n`).join(""));
  }
  return new Response(JSON.stringify({ content: [{ type: "text", text: "[]" }] }));
};
await (await (C as any).__servi(new Request("http://x/jarvis", { method: "POST", headers: { "x-jarvis-token": "prova" },
  body: JSON.stringify({ messaggi: [{ role: "user", content: "ciao" }], dispositivo: "iphone", strumenti_client: [], senza_filo: true }) }))).text();
const lunghezza = sistema.split("\n").find((l) => l.startsWith("LUNGHEZZA")) ?? "";
atteso("5. LUNGHEZZA: spiegazione a voce in 5-6 frasi", /cinque o sei frasi al massimo/.test(lunghezza), lunghezza);
atteso("5. LUNGHEZZA: la versione lunga con «nei dettagli», «nel dettaglio», «spiegami bene»", /«nei dettagli»/.test(lunghezza) && /«nel dettaglio»/.test(lunghezza) && /«spiegami bene»/.test(lunghezza), "");
atteso("5. LUNGHEZZA: «in breve» = tre frasi resta", /«in breve».*tre frasi al massimo/.test(lunghezza), "");
atteso("5. confidente, diario e testi richiesti con le loro regole", /Il confidente e il diario seguono le loro regole/.test(lunghezza) && /restano completi/.test(lunghezza), "");
atteso("5. la regola dei testi completi in INTELLIGENZA c'è ancora", /scrivilo completo e curato anche se è lungo/.test(sistema), "");
atteso("5. TONO, IN PRATICA ed ESEMPI non toccati", sistema.includes("TONO, IN PRATICA. Una battuta all'incirca ogni quattro risposte") && sistema.includes("«Accendi la torcia.» → «Accesa, Sir.»"), "");
const occhi = sistema.split("\n").find((l) => l.startsWith("Occhi:")) ?? "";
atteso("27. Occhi: niente «persone note»", !/persone note/.test(occhi), occhi);
atteso("27. Occhi: mai nomi di persone, nemmeno famose", /non dici mai il loro nome, nemmeno se sono famose/.test(occhi), occhi);
atteso("27. Profiler invariato", sistema.includes("Non riconoscere né identificare mai una persona dal volto e non tirare a indovinare chi sia"), "");
atteso("50. la frase dell'invio incerto nel prompt", sistema.includes("«Non so se è partita, Sir: in Inviata non la vedrà.»"), "");
// il sorgente di jarvis-briefing: argomento, oppure accanto alle prove nel repository (supabase/prove → supabase/functions), oppure S/dcerv
const candidati = [Deno.args[0], new URL("../functions/jarvis-briefing/index.ts", import.meta.url).pathname, new URL("../dcerv/supabase/functions/jarvis-briefing/index.ts", import.meta.url).pathname];
const briefing = candidati.filter(Boolean).map((p) => { try { return Deno.readTextFileSync(p!); } catch { return ""; } }).find(Boolean) ?? "";
atteso("13. titolo del briefing «Buongiorno, Sir»", briefing.includes('mandaATutti("Buongiorno, Sir", testo, "briefing")') && !/Buongiorno, signore/.test(briefing), "");
console.log("prove testi decisioni: sbagliate", ko);
Deno.exit(ko ? 1 : 0);
