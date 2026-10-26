// JARVIS — STUDIO · CREA LIBERO (MARK X): il banco olografico chiede al cervello la ricetta dei pezzi per «qualsiasi cosa» descritta.
// POST, header x-jarvis-token (l'app) o x-chiave-interna (le prove dal database). Corpo: { prompt: string }  →  { testo: string } (il JSON dei pezzi lo legge la pagina dello Studio)
// Segreti: JARVIS_TOKEN, ANTHROPIC_API_KEY, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY. Facoltativo: MODELLO_STUDIO (predefinito Sonnet).
// v3 (26 ott sera, il signore: «CREA veloce e intelligente al massimo»):
//  · le istruzioni del progettista stanno qui (in cache da Anthropic: si pagano e si leggono una volta), più precise e con un esempio;
//  · il cervello risponde in forma compatta (circa metà dei token: metà del tempo), qui si riscrive nella forma che la pagina legge;
//  · la stessa descrizione già progettata torna subito dall'archivio (tabella studio_ricette), senza chiedere di nuovo.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { "content-type": "application/json" } });
const env = (k: string) => Deno.env.get(k) ?? "";
function uguali(a: string, b: string) {
  if (!a || a.length !== b.length) return false;
  let x = 0; for (let k = 0; k < a.length; k++) x |= a.charCodeAt(k) ^ b.charCodeAt(k);
  return x === 0;
}

const SISTEMA = `Sei il progettista 3D di JARVIS: sul banco olografico costruisci oggetti stampabili in 3D unendo forme semplici.
Ti do una descrizione in italiano; tu progetti l'oggetto in millimetri e rispondi SOLO con JSON compatto, senza spazi né testo:
{"n":"nome breve in italiano","p":[[forma,misure,[x,y,z],[rx,ry,rz],foro],...]}
Forme e misure:
- "scatola" {"l":lungo x,"p":profondo z,"h":alto y}
- "cilindro" {"d":diametro,"h":altezza} (asse verticale)
- "cono" {"d":base,"d2":cima (0 = punta),"h"}
- "sfera" {"d"} oppure ellissoide {"d","h"}
- "toro" {"d":esterno,"s":spessore} (anello orizzontale)
- "cuneo" {"l","p","h"} (prisma triangolare, colmo in alto, come un tetto)
- "piramide" {"d","h"}
Regole:
- Y è l'alto, il piano di stampa è y=0. [x,y,z] è il CENTRO del pezzo. La rotazione in gradi (ometti [rx,ry,rz] e foro se sono 0 e false; se serve solo foro metti [0,0,0]).
- Il quinto valore 1 = il pezzo SCAVA gli altri (occhi incavati, finestre, fori, cavità).
- Rendi l'oggetto RICONOSCIBILE dalla sagoma: prima le masse principali con le proporzioni vere, poi i dettagli che lo identificano (orecchie a punta del gatto, muso lungo del cane, ali dell'aereo…). Le parti doppie sono simmetriche rispetto a x=0.
- Tutto unito in un solo solido: i pezzi si compenetrano di qualche millimetro; niente parti sospese; la base appoggia bene sul piano (eventualmente una base piatta).
- Da 4 a 18 pezzi; ingombro sui 60-120 mm (o le misure dette), tutto dentro 250 mm; spessori minimi 2 mm (stampa FDM).
Esempio, «un cane seduto»:
{"n":"Cane","p":[["sfera",{"d":44,"h":52},[0,30,-4]],["sfera",{"d":30},[0,64,12]],["cilindro",{"d":14,"h":14},[0,60,28],[90,0,0]],["sfera",{"d":7},[0,61,36]],["sfera",{"d":12,"h":26},[-13,70,8],[0,0,20]],["sfera",{"d":12,"h":26},[13,70,8],[0,0,-20]],["cilindro",{"d":10,"h":28},[-10,14,14]],["cilindro",{"d":10,"h":28},[10,14,14]],["sfera",{"d":26,"h":16},[-14,8,-8]],["sfera",{"d":26,"h":16},[14,8,-8]],["cono",{"d":8,"d2":3,"h":26},[0,22,-30],[-50,0,0]],["sfera",{"d":4},[-6,68,24],[0,0,0],1],["sfera",{"d":4},[6,68,24],[0,0,0],1],["scatola",{"l":56,"p":64,"h":3},[0,1.5,0]]]}`;

const FORME = new Set(["scatola", "cilindro", "cono", "sfera", "toro", "cuneo", "piramide"]);
function espandi(c: any) {
  const p = Array.isArray(c?.p) ? c.p : [];
  const pezzi = p.filter((q: any) => Array.isArray(q) && FORME.has(q[0])).slice(0, 20).map((q: any) => ({
    forma: q[0], misure: q[1] && typeof q[1] === "object" ? q[1] : {}, pos: Array.isArray(q[2]) ? q[2] : [0, 0, 0],
    rot: Array.isArray(q[3]) ? q[3] : [0, 0, 0], foro: q[4] === 1 || q[4] === true,
  }));
  return { nome: String(c?.n ?? "Pezzo").slice(0, 40), pezzi };
}

async function db(percorso: string, init: RequestInit = {}) {
  const u = env("SUPABASE_URL"), k = env("SUPABASE_SERVICE_ROLE_KEY");
  if (!u || !k) return null;
  return await fetch(`${u}/rest/v1/${percorso}`, { ...init, headers: { apikey: k, authorization: `Bearer ${k}`, "content-type": "application/json", ...(init.headers ?? {}) } }).catch(() => null);
}

Deno.serve(async (req) => {
  const segreto = env("JARVIS_TOKEN");
  let ammesso = !!segreto && uguali(req.headers.get("x-jarvis-token") ?? "", segreto);
  if (!ammesso) {                                          // le prove dal database (pg_net), come travel-voli
    const interna = req.headers.get("x-chiave-interna") ?? "";
    const v = interna ? await db("rpc/verifica_chiave_interna", { method: "POST", body: JSON.stringify({ p: interna }) }) : null;
    ammesso = v?.ok ? (await v.json().catch(() => false)) === true : false;
  }
  if (!ammesso) return json({ errore: "parola d'ordine errata" }, 401);
  const { prompt } = await req.json().catch(() => ({ prompt: "" }));
  const p = String(prompt ?? "").slice(0, 6000);
  if (!p) return json({ errore: "manca la descrizione" }, 400);
  // la pagina dello Studio manda le sue istruzioni con la descrizione tra «»: qui vale solo la descrizione
  const m = p.match(/l'oggetto descritto: «([^»]{1,300})»/);
  const descr = (m ? m[1] : p.slice(0, 300)).trim();
  const chiave = descr.toLowerCase().replace(/[^\p{L}\p{N} ]+/gu, " ").replace(/^(un|una|uno|il|lo|la|l)\s+/, "").replace(/\s+/g, " ").trim();
  // già progettato: subito dall'archivio
  const c = await db(`studio_ricette?descrizione=eq.${encodeURIComponent(chiave)}&select=ricetta`);
  if (c?.ok) { const r = await c.json().catch(() => []); if (r?.[0]?.ricetta?.pezzi?.length) {
    return json({ testo: JSON.stringify(r[0].ricetta), archivio: true }); } }
  try {
    const r = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "x-api-key": env("ANTHROPIC_API_KEY"), "anthropic-version": "2023-06-01", "content-type": "application/json" },
      body: JSON.stringify({
        model: env("MODELLO_STUDIO") || "claude-sonnet-5-5", max_tokens: 1800,
        system: [{ type: "text", text: SISTEMA, cache_control: { type: "ephemeral" } }],
        messages: [{ role: "user", content: `Progetta: «${descr}»` }],
      }),
    });
    const d = await r.json();
    if (!r.ok) return json({ errore: "cervello: " + (d?.error?.message ?? r.status) }, 502);
    const grezzo = (d.content ?? []).filter((x: any) => x.type === "text").map((x: any) => x.text).join("");
    const j = grezzo.slice(grezzo.indexOf("{"), grezzo.lastIndexOf("}") + 1);
    let ric; try { ric = espandi(JSON.parse(j)); } catch { return json({ errore: "il progetto è arrivato rotto" }, 502); }
    if (!ric.pezzi.length) return json({ errore: "nessun pezzo" }, 502);
    const salva = db("studio_ricette", { method: "POST", headers: { prefer: "resolution=merge-duplicates" }, body: JSON.stringify({ descrizione: chiave, ricetta: ric }) });
    // @ts-ignore EdgeRuntime c'è nelle funzioni di Supabase: l'archivio si scrive dopo la risposta, senza farla aspettare
    if (typeof EdgeRuntime !== "undefined") EdgeRuntime.waitUntil(salva); else await salva;
    return json({ testo: JSON.stringify(ric) });
  } catch (e) { return json({ errore: "il cervello non risponde: " + String(e) }, 502); }
});
