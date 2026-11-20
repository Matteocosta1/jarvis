// FRIDAY — le richieste delle sezioni nuove dell'app (20 nov 2026): Gestionale modificabile, Armadio (le funzioni SQL friday_*),
// posta di Bea collegata da lei (nella cassaforte del database, mai nei file), SOS verso Ale (il Tocco d'aiuto di JARVIS),
// Occhi delle sezioni (Frigo, Armadio, Nando, Makeup: una foto → dati in JSON), testi pronti (annuncio Vinted, didascalia,
// riassunto per il medico), impostazioni pubbliche dell'app (l'ID Spotify). Tutto con la stessa parola d'ordine dell'app.
import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { "content-type": "application/json" } });

// le funzioni SQL dell'Armadio che l'app può chiamare (tutte security definer, solo dati dell'Armadio)
const RPC_ARMADIO = new Set([
  "friday_capi_elenco", "friday_capi_conta", "friday_capi_togli", "friday_foto_parte", "friday_foto_mancanti",
  "friday_prova_avvia", "friday_prova_stato", "friday_prova_pezzo", "friday_prova_elenco", "friday_prova_elimina", "friday_prova_mese",
  "friday_estrai_avvia", "friday_estrai_stato", "friday_estrai_fatte",
]);

// il gestionale di Bea: le sue tabelle e le colonne che l'app può scrivere
const GESTIONALE: Record<string, string[]> = {
  clienti: ["nome", "tel", "lezioni", "note"],
  agenda: ["cliente", "data", "ora", "tipo", "fatta"],
  pagamenti: ["cliente", "importo", "lezioni", "data"],
  corsi: ["titolo", "prezzo", "abbonati"],
  contenuti: ["titolo", "tipo", "data", "stato"],
};

const COMPITI_VISTA: Record<string, string> = {
  frigo: `Sei l'occhio di FRIDAY nel frigo di Bea. Elenca gli alimenti visibili nella foto. Rispondi SOLO con JSON:
{"cose":[{"nome":"Yogurt greco","quanti":2,"giorni":4}]} dove giorni = quanti giorni ancora si conserva, stimati in modo prudente
(aperto o fresco: pochi giorni). Nomi in italiano, brevi. Niente che non vedi davvero.`,
  capo: `Sei l'occhio di FRIDAY sull'armadio di Bea. Riconosci il capo (o l'etichetta) nella foto. Rispondi SOLO con JSON:
{"capo":"trench doppiopetto","categoria":"una tra maglie, camicie, giacche, cappotti, jeans, pantaloni, gonne, vestiti, scarpe, borse, accessori","brand":"Zara","brand_sicuro":true,
"colore":"beige","hex":"#d8c3a5","materiale":"100% cotone","taglia":"S"} con stringhe vuote per quello che non si vede. brand_sicuro solo
se logo o etichetta sono leggibili.`,
  cibo_cane: `Sei FRIDAY e Bea ha un barboncino, Nando. Guarda il cibo nella foto e dì se è pericoloso per un cane. Rispondi SOLO con JSON:
{"cibo":"uva","pericoloso":true,"perche":"tossica per i cani: anche poca può dare insufficienza renale"}. Se non sei sicura, pericoloso:true
e spiega di chiedere al veterinario.`,
  pelo: `Sei FRIDAY. Nella foto c'è Nando, un barboncino. Stima la lunghezza del pelo sul corpo in centimetri e quanti giorni mancano a una
toelettatura (di solito si fa con 4-5 cm). Rispondi SOLO con JSON: {"cm":3.5,"giorni":9}.`,
  trucco: `Sei FRIDAY. Nella foto c'è un prodotto di trucco di Bea. Rispondi SOLO con JSON:
{"tipo":"Fondotinta","brand":"…","nome":"…","tonalita":"2W"} con stringhe vuote per quello che non si legge.`,
  doppione: `Sei FRIDAY. Bea sta pensando di comprare il capo nella foto. Confrontalo con il suo armadio (elenco sotto) e rispondi SOLO con JSON:
{"capo":"blazer nero","simili":["Blazer nero Zara","Giacca nera Mango"]} (simili: quelli del suo armadio che le somigliano davvero, anche vuoto).`,
};

const COMPITI_TESTO: Record<string, string> = {
  annuncio: "Scrivi l'annuncio Vinted per il capo descritto: titolo (max 60 caratteri), descrizione breve e onesta, condizioni, categoria. JSON: {\"titolo\":\"\",\"descrizione\":\"\",\"condizioni\":\"\",\"categoria\":\"\"}",
  didascalia: "Scrivi una didascalia Instagram breve e naturale per un Reel di Pilates di Bea (istruttrice), con 3-5 hashtag pertinenti. JSON: {\"testo\":\"\"}",
  medico: "Con i dati del diario qui sotto prepara un riassunto chiaro per il medico (date, durata, intensità, farmaci, fattori ricorrenti), senza diagnosi né dosi. JSON: {\"testo\":\"\"}",
  trucco: "Con la trousse di Bea e l'occasione qui sotto, dai un consiglio di trucco in 3-4 frasi, con il «tu». JSON: {\"testo\":\"\"}",
  volantino: "Scrivi il testo del volantino «cane smarrito» per Nando con i dati qui sotto: titolo, descrizione, contatto. JSON: {\"testo\":\"\"}",
};

async function claudeJSON(sistema: string, contenuto: any[], modello = "claude-sonnet-5-5", max = 900) {
  const r = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: { "content-type": "application/json", "x-api-key": Deno.env.get("ANTHROPIC_API_KEY") ?? "", "anthropic-version": "2023-06-01" },
    body: JSON.stringify({ model: modello, max_tokens: max, system: sistema, messages: [{ role: "user", content: contenuto }] }),
    signal: AbortSignal.timeout(60_000),
  });
  if (!r.ok) throw new Error(`il cervello risponde ${r.status}`);
  const d = await r.json();
  const testo = (d.content ?? []).filter((b: any) => b.type === "text").map((b: any) => b.text).join("");
  const m = testo.match(/\{[\s\S]*\}/);
  if (!m) throw new Error("risposta non leggibile");
  return JSON.parse(m[0]);
}

async function provaPosta(email: string, password: string): Promise<string | null> {
  const conn = await Deno.connectTls({ hostname: "imap.mail.me.com", port: 993 });
  const enc = new TextEncoder(), dec = new TextDecoder(), buf = new Uint8Array(8192);
  const leggi = async (fine: RegExp) => {
    let t = ""; const limite = Date.now() + 8000;
    while (!fine.test(t)) { if (Date.now() > limite) throw new Error("iCloud non risponde"); const n = await conn.read(buf); if (n === null) throw new Error("connessione chiusa"); t += dec.decode(buf.subarray(0, n)); }
    return t;
  };
  const q = (s: string) => `"${s.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
  try {
    await leggi(/\r\n$/);
    await conn.write(enc.encode(`b1 LOGIN ${q(email)} ${q(password)}\r\n`));
    const r = await leggi(/(^|\r\n)b1 (OK|NO|BAD)[^\r\n]*\r\n$/);
    if (!/b1 OK/.test(r)) return "iCloud non accetta questa password: serve la «password per app» (non quella dell'Apple ID).";
    await conn.write(enc.encode("b2 LOGOUT\r\n")); await leggi(/b2 (OK|NO|BAD)/).catch(() => "");
    return null;
  } finally { try { conn.close(); } catch { /* chiusa */ } }
}

/** Le richieste delle sezioni nuove. Restituisce null se la richiesta non è per qui. */
export async function richiesteBea(corpo: any, db: SupabaseClient): Promise<Response | null> {
  try {
    // ── Armadio: le funzioni SQL già usate dal mockup
    if (corpo?.rpc && typeof corpo.rpc === "object") {
      const nome = String(corpo.rpc.nome ?? "");
      if (!RPC_ARMADIO.has(nome)) return json({ errore: "funzione non ammessa" }, 400);
      const { data, error } = await db.rpc(nome, corpo.rpc.args ?? {});
      if (error) return json({ errore: error.message });
      return json({ dati: data });
    }

    // ── Gestionale: leggere, aggiungere, cambiare, togliere (Bea lo personalizza dall'app)
    if (corpo?.gestionale && typeof corpo.gestionale === "object") {
      const g = corpo.gestionale, tabella = String(g.tabella ?? "");
      if (g.azione === "tutto") {
        const fuori: Record<string, unknown> = {};
        for (const t of Object.keys(GESTIONALE)) {
          const { data, error } = await db.from(t).select("*").order("creato_il", { ascending: false }).limit(500);
          if (error) return json({ errore: error.message });
          fuori[t] = data ?? [];
        }
        return json(fuori);
      }
      const colonne = GESTIONALE[tabella];
      if (!colonne) return json({ errore: "tabella non ammessa" }, 400);
      if (g.azione === "salva") {
        const riga: Record<string, unknown> = {};
        for (const c of colonne) if (g.riga && c in g.riga) riga[c] = g.riga[c];
        const id = String(g.riga?.id ?? "") || crypto.randomUUID();
        const { error } = await db.from(tabella).upsert({ id, ...riga });
        return json(error ? { errore: error.message } : { ok: true, id });
      }
      if (g.azione === "elimina") {
        const { error } = await db.from(tabella).delete().eq("id", String(g.id ?? ""));
        return json(error ? { errore: error.message } : { ok: true });
      }
      return json({ errore: "azione non ammessa" }, 400);
    }

    // ── Account › Mail: Bea collega la sua posta iCloud (password per app), provata subito, poi nella cassaforte
    if (corpo?.account_mail && typeof corpo.account_mail === "object") {
      const email = String(corpo.account_mail.email ?? "").trim(), password = String(corpo.account_mail.password ?? "").trim();
      if (corpo.account_mail.scollega === true) {
        await db.rpc("friday_segreto_salva", { p_nome: "posta_icloud", p_valore: "" });
        return json({ ok: true, collegata: false });
      }
      if (!/^[^@\s]+@[^@\s]+\.[a-z]{2,}$/i.test(email) || password.length < 8) return json({ ok: false, errore: "Mail o password non valide." });
      const no = await provaPosta(email, password).catch((e) => (e as Error).message);
      if (no) return json({ ok: false, errore: no });
      const { error } = await db.rpc("friday_segreto_salva", { p_nome: "posta_icloud", p_valore: JSON.stringify({ email, password }) });
      return json(error ? { ok: false, errore: error.message } : { ok: true, collegata: true, email });
    }
    if (corpo?.account_stato === true) {
      const { data } = await db.rpc("friday_segreto_leggi", { p_nome: "posta_icloud" });
      let email = ""; try { email = data ? JSON.parse(String(data)).email ?? "" : ""; } catch { /* vuota */ }
      const env = Deno.env.get("ICLOUD_EMAIL") ?? "";
      const { data: c } = await db.from("friday_config").select("chiave, valore").in("chiave", ["spotify_client_id"]);
      return json({ posta: env || email, spotify_client_id: (c ?? []).find((x: any) => x.chiave === "spotify_client_id")?.valore ?? "",
        sos_pronto: !!Deno.env.get("BEA_SOS_CHIAVE") });
    }

    // ── SOS: il Tocco d'aiuto di JARVIS (notifica sugli iPhone di Ale con la posizione)
    if (corpo?.sos && typeof corpo.sos === "object") {
      const chiave = Deno.env.get("BEA_SOS_CHIAVE") ?? "";
      if (!chiave) return json({ ok: false, errore: "SOS non collegato: manca BEA_SOS_CHIAVE nei segreti di FRIDAY." });
      const r = await fetch("https://axalouhijcsizqgnneco.supabase.co/functions/v1/jarvis-bea-sos", {
        method: "POST", headers: { "content-type": "application/json", "x-bea-chiave": chiave },
        body: JSON.stringify({ lat: corpo.sos.lat ?? null, lon: corpo.sos.lon ?? null, prova: corpo.sos.prova === true }),
        signal: AbortSignal.timeout(15_000),
      });
      const d = await r.json().catch(() => ({}));
      return json({ ok: r.ok && (d.ok === true || d.gia_inviato === true), inviate: d.inviate ?? 0, errore: r.ok ? undefined : `risponde ${r.status}` });
    }

    // ── Occhi delle sezioni: una foto (JPEG base64) e il compito → JSON
    if (corpo?.vista && typeof corpo.vista === "object") {
      const compito = String(corpo.vista.compito ?? ""), sistema = COMPITI_VISTA[compito];
      if (!sistema) return json({ errore: "compito non ammesso" }, 400);
      const img = String(corpo.vista.immagine ?? "");
      if (!/^[A-Za-z0-9+/=]{100,}$/.test(img) || img.length > 7_000_000) return json({ errore: "foto non valida" }, 400);
      const extra = corpo.vista.contesto ? `\n\nContesto: ${String(corpo.vista.contesto).slice(0, 6000)}` : "";
      const r = await claudeJSON(sistema + extra, [{ type: "image", source: { type: "base64", media_type: "image/jpeg", data: img } }, { type: "text", text: "Ecco la foto." }]);
      return json(r);
    }

    // ── Testi pronti
    if (corpo?.scrivi && typeof corpo.scrivi === "object") {
      const compito = String(corpo.scrivi.compito ?? ""), sistema = COMPITI_TESTO[compito];
      if (!sistema) return json({ errore: "compito non ammesso" }, 400);
      const dati = JSON.stringify(corpo.scrivi.dati ?? {}).slice(0, 12000);
      const r = await claudeJSON(`Sei FRIDAY, l'assistente di Bea: italiano, tono caldo e concreto. ${sistema}`, [{ type: "text", text: dati }], "claude-sonnet-5-5", 1200);
      return json(r);
    }
  } catch (e) {
    return json({ errore: (e as Error).message });
  }
  return null;
}
