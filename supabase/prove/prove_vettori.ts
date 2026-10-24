// Sicurezza approvata (24 ott): completaVettori non deve mai superare il limite di 2 s di CPU di Supabase. Budget di circa 700 ms
// di lavoro, poi si ferma e riprende al turno dopo. Il modello gte-small finto qui CALCOLA davvero (un ciclo che occupa la CPU)
// per il tempo indicato, come fa quello vero. Cervello vero (prepara.sh), database finto con stato.
const qui = new URL(".", import.meta.url).pathname;
Deno.writeTextFileSync(qui + "cervello_stato.ts", Deno.readTextFileSync(qui + "cervello_test.ts").replace('from "./finto_db.ts"', 'from "./finto_db_stato.ts"'));
const g = globalThis as any;
let costo = 150, calcolati = 0;
const occupa = (ms: number) => { const t = performance.now(); while (performance.now() - t < ms) { /* calcolo */ } };
g.Supabase = { ai: { Session: class { run() { occupa(costo); calcolati++; return Promise.resolve(new Array(384).fill(1 / Math.sqrt(384))); } } } };
const C: any = await import(qui + "cervello_stato.ts");
let ko = 0; const atteso = (n: string, v: boolean, info: unknown = "") => { if (!v) { ko++; console.log("✗", n, JSON.stringify(info)); } else console.log("✓", n); };
const righe = (n: number, campo: string) => Array.from({ length: n }, (_, k) => ({ id: k + 1, [campo]: `riga ${k + 1}`, vettore: null }));
const riempi = () => { g.__tab = { jarvis_memoria: righe(5, "fatto"), jarvis_ricordi: righe(5, "testo"), jarvis_note: righe(5, "testo"), jarvis_diario: righe(5, "risposta") }; };
const senza = () => ["jarvis_memoria", "jarvis_ricordi", "jarvis_note", "jarvis_diario"].reduce((t, k) => t + g.__tab[k].filter((r: any) => r.vettore == null).length, 0);

// 1 ─ 20 righe senza vettore, 150 ms ciascuna: prima erano 12 vettori di fila (1,8 s di CPU, oltre il limite con il resto del turno)
riempi(); calcolati = 0;
let t0 = performance.now();
await C.completaVettori();
let ms = performance.now() - t0;
console.log(`   1: ${calcolati} vettori in ${Math.round(ms)} ms`);
atteso("1. si ferma entro il budget (circa 700 ms di lavoro)", calcolati * costo <= 700 && ms < 900, { calcolati, ms: Math.round(ms) });
atteso("1. ma lavora (almeno 4 vettori)", calcolati >= 4, calcolati);
atteso("1. i vettori calcolati sono salvati", senza() === 20 - calcolati, senza());

// 2 ─ al turno dopo riprende da dove era rimasto, finché le righe finiscono
let giri = 1;
while (senza() > 0 && giri < 20) { calcolati = 0; t0 = performance.now(); await C.completaVettori(); ms = performance.now() - t0; giri++;
  if (calcolati * costo > 700 || ms > 900) { atteso(`2. giro ${giri} entro il budget`, false, { calcolati, ms }); break; } }
atteso("2. turno dopo turno tutte le righe prendono il vettore", senza() === 0, { senza: senza(), giri });

// 3 ─ un vettore lento (il primo carica il modello: 600 ms): dopo di lui non ne parte un altro che sforerebbe
riempi(); calcolati = 0; costo = 600;
t0 = performance.now(); await C.completaVettori(); ms = performance.now() - t0;
atteso("3. dopo un vettore da 600 ms si ferma", calcolati === 1 && ms < 900, { calcolati, ms: Math.round(ms) });
// e al turno dopo, tornati veloci (50 ms), il primo parte comunque e poi si va avanti
costo = 50; calcolati = 0;
await C.completaVettori();
atteso("3. al turno dopo riparte (il primo vettore parte sempre)", calcolati >= 1 && calcolati * 50 <= 750, calcolati);

// 4 ─ anche il collaudo «vettori_completa» (fino a 10 righe per tabella) resta nel budget
riempi(); calcolati = 0; costo = 150;
t0 = performance.now();
const r = await (await C.__servi(new Request("http://x/jarvis", { method: "POST", headers: { "x-jarvis-token": "prova" }, body: JSON.stringify({ vettori_completa: true, quanti: 10 }) }))).json();
ms = performance.now() - t0;
atteso("4. vettori_completa entro il budget", calcolati * costo <= 700 && ms < 1000, { calcolati, ms: Math.round(ms), r });
atteso("4. e dice quante ne restano", r.senza_vettore_dopo?.jarvis_memoria !== undefined && Object.values(r.senza_vettore_dopo).reduce((t: number, x: any) => t + x, 0) === 20 - calcolati, r);

console.log("prove vettori: sbagliate", ko);
Deno.exit(ko ? 1 : 0);
