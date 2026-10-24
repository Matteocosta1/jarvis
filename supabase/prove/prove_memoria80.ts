// Decisione 52 (24 ott): con più di 80 fatti in memoria si caricano gli 80 più RECENTI (prima erano i più vecchi);
// la ricerca per significato aggiunge ancora i vecchi che servono. Cervello vero (prepara.sh), database finto con stato.
const qui = new URL(".", import.meta.url).pathname;
Deno.writeTextFileSync(qui + "cervello_stato.ts", Deno.readTextFileSync(qui + "cervello_test.ts").replace('from "./finto_db.ts"', 'from "./finto_db_stato.ts"'));
const g = globalThis as any;
// il modello dei significati (gte-small) finto: un vettore qualsiasi; la ricerca (rpc) dice che il fatto 5 è vicino
g.Supabase = { ai: { Session: class { run() { return Promise.resolve(new Array(384).fill(1 / Math.sqrt(384))); } } } };
const rpc: any[] = [];
g.__rpc = (nome: string, arg: any) => { rpc.push({ nome, arg }); return { data: arg?.tabella === "jarvis_memoria" ? [{ id: 5, somiglianza: 0.9 }] : [], error: null }; };
const C: any = await import(qui + "cervello_stato.ts");
let ko = 0; const atteso = (n: string, v: boolean, info: unknown = "") => { if (!v) { ko++; console.log("✗", n, JSON.stringify(info)); } else console.log("✓", n); };
let mandato = "";
g.fetch = async (u: any, o?: any) => {
  const corpo = JSON.parse(o?.body ?? "{}");
  if (corpo.stream === true) {
    const ultimo = corpo.messages.at(-1).content; mandato = typeof ultimo === "string" ? ultimo : ultimo.map((b: any) => b.text ?? "").join("");
    const ev = [{ type: "message_start", message: { usage: {} } }, { type: "content_block_start", index: 0, content_block: { type: "text", text: "" } },
      { type: "content_block_delta", index: 0, delta: { type: "text_delta", text: "Ok." } }, { type: "content_block_stop", index: 0 }, { type: "message_delta", delta: { stop_reason: "end_turn" } }];
    return new Response(ev.map((e) => `data: ${JSON.stringify(e)}\n\n`).join(""));
  }
  return new Response(JSON.stringify({ content: [{ type: "text", text: "[]" }] }));
};
const chiedi = async (frase: string) => { await (await C.__servi(new Request("http://x/jarvis", { method: "POST", headers: { "x-jarvis-token": "prova" },
  body: JSON.stringify({ messaggi: [{ role: "user", content: frase }], dispositivo: "iphone", strumenti_client: [], senza_filo: true }) }))).text(); };
const cat = ["persone", "preferenze", "progetti", "lavoro", "casa", "profilo"];
const fatti = (n: number) => Array.from({ length: n }, (_, k) => ({ id: k + 1, fatto: `fatto numero ${k + 1}.`, categoria: k === 0 ? "profilo" : cat[k % cat.length],
  creata: new Date(Date.UTC(2026, 9, 1) + k * 3600_000).toISOString() }));
const presenti = () => new Set([...mandato.matchAll(/fatto numero (\d+)\./g)].map((m) => Number(m[1])));

// 1 ─ 100 fatti: entrano i più recenti (21-100) e il 5, vicino per significato; non gli altri vecchi
g.__tab = { jarvis_memoria: fatti(100) };
await chiedi("cosa sai dei miei progetti con Matteo per il locale?");
let p = presenti();
atteso("1. ci sono gli 80 più recenti (21-100)", Array.from({ length: 80 }, (_, k) => k + 21).every((n) => p.has(n)), [...p].sort((a, b) => a - b).slice(0, 10));
atteso("1. i vecchi non vicini restano fuori (1-4, 6-20)", [1, 2, 3, 4, 6, 7, 10, 20].every((n) => !p.has(n)), [...p].filter((n) => n <= 20));
atteso("1. il vecchio vicino per significato (5) c'è", p.has(5) && rpc.some((x) => x.nome === "jarvis_significato" && x.arg.tabella === "jarvis_memoria"), { p5: p.has(5), rpc });
atteso("1. 81 fatti in tutto", p.size === 81, p.size);
// l'ordine nel contesto resta quello di prima: profilo in testa, poi per categoria, dal più vecchio al più nuovo
const righe = mandato.split("\n").filter((l) => /^- \(/.test(l)).map((l) => l.match(/^- \((\w+)\) fatto numero (\d+)/)!).map((m) => ({ c: m[1], n: Number(m[2]) }));
atteso("1. profilo in testa", righe.findIndex((r) => r.c !== "profilo") === righe.filter((r) => r.c === "profilo").length, righe.slice(0, 20));
const resto = righe.filter((r) => r.c !== "profilo" && r.n !== 5);
atteso("1. poi per categoria e per data", resto.every((r, i) => i === 0 || resto[i - 1].c < r.c || (resto[i - 1].c === r.c && resto[i - 1].n < r.n)), resto.slice(0, 12));
atteso("1. il fatto trovato per significato in coda, come prima", righe.at(-1)?.n === 5, righe.at(-1));

// 2 ─ 30 fatti: entrano tutti, come prima (niente ricerca per significato)
g.__tab = { jarvis_memoria: fatti(30) }; rpc.length = 0;
await chiedi("cosa sai dei miei progetti con Matteo per il locale?");
p = presenti();
atteso("2. sotto gli 80 ci sono tutti", p.size === 30 && rpc.length === 0, { n: p.size, rpc: rpc.length });

console.log("prove memoria80: sbagliate", ko);
Deno.exit(ko ? 1 : 0);
