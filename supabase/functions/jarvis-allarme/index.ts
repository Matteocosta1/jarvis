// JARVIS — allarme cuore: l'orologio segnala un battito alto e qui partono WhatsApp, SMS e chiamata vocale al contatto di emergenza.
// POST, header x-jarvis-token. Corpo: { bpm: number, prova?: boolean, posizione?: "lat,lon" }
// Segreti:
//   JARVIS_TOKEN
//   EMERGENZA_NUMERO     numeri per chiamata e SMS (+39…, separati da virgola)
//   CLICKSEND_USERNAME, CLICKSEND_API_KEY   → telefonata con voce (e SMS) tramite ClickSend
//   EMERGENZA_WHATSAPP   "+39…:APIKEY" (uno o più, separati da virgola) → WhatsApp gratuito tramite CallMeBot
// Facoltativo: NOME_UTENTE. Un allarme vero ogni 5 minuti al massimo (tabella jarvis_allarmi).
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
const json = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { "content-type": "application/json" } });
const env = (k: string) => Deno.env.get(k) ?? "";
function uguali(a: string, b: string) {
  if (!a || a.length !== b.length) return false;
  let x = 0; for (let k = 0; k < a.length; k++) x |= a.charCodeAt(k) ^ b.charCodeAt(k);
  return x === 0;
}
const internazionale = (n: string) => "+" + n.replace(/[^\d]/g, "").replace(/^00/, "");

// ───────── ClickSend: telefonata con voce e SMS ─────────
async function clicksend(percorso: "voice/send" | "sms/send", messaggio: Record<string, unknown>) {
  try {
    const r = await fetch(`https://rest.clicksend.com/v3/${percorso}`, {
      method: "POST",
      headers: { authorization: "Basic " + btoa(`${env("CLICKSEND_USERNAME")}:${env("CLICKSEND_API_KEY")}`), "content-type": "application/json" },
      body: JSON.stringify({ messages: [messaggio] }),
    });
    const d = await r.json().catch(() => ({}));
    const m = d?.data?.messages?.[0];
    const ok = r.ok && (!m?.status || m.status === "SUCCESS");
    return ok ? { ok: true, id: m?.message_id } : { ok: false, errore: `${r.status} ${m?.status ?? d?.response_code ?? ""} ${d?.response_msg ?? ""}`.trim() };
  } catch (e) {
    return { ok: false, errore: (e as Error).message };
  }
}

// ───────── CallMeBot: WhatsApp gratuito ─────────
async function whatsapp(numero: string, apikey: string, testo: string) {
  try {
    const q = new URLSearchParams({ phone: internazionale(numero), text: testo, apikey });
    const r = await fetch(`https://api.callmebot.com/whatsapp.php?${q}`);
    const t = await r.text().catch(() => "");
    const ok = r.ok && !/error|invalid|wrong/i.test(t.slice(0, 300));
    return ok ? { ok: true } : { ok: false, errore: `${r.status} ${t.replace(/<[^>]+>/g, " ").trim().slice(0, 160)}` };
  } catch (e) {
    return { ok: false, errore: (e as Error).message };
  }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ errore: "metodo non ammesso" }, 405);
  const segreto = env("JARVIS_TOKEN");
  if (!segreto || !uguali(req.headers.get("x-jarvis-token") ?? "", segreto)) return json({ errore: "parola d'ordine errata" }, 401);
  let corpo: any;
  try { corpo = await req.json(); } catch { return json({ errore: "richiesta non valida" }, 400); }

  const numeri = env("EMERGENZA_NUMERO").split(",").map((s) => s.trim()).filter(Boolean);
  const whatsappDest = env("EMERGENZA_WHATSAPP").split(",").map((s) => s.trim()).filter((s) => s.includes(":"))
    .map((s) => { const k = s.lastIndexOf(":"); return { numero: s.slice(0, k), apikey: s.slice(k + 1) }; });
  const conClicksend = !!(env("CLICKSEND_USERNAME") && env("CLICKSEND_API_KEY") && numeri.length);
  if (!conClicksend && !whatsappDest.length) {
    return json({ errore: "allarme non configurato: mancano i dati di ClickSend o di WhatsApp (CallMeBot)" }, 503);
  }

  const bpm = Math.round(Number(corpo.bpm) || 0);
  const prova = corpo.prova === true;
  // motivo: "alto" (battito troppo alto a riposo), "basso" (troppo basso), "manuale" (il tasto SOS)
  const motivo = ["alto", "basso", "manuale"].includes(corpo.motivo) ? corpo.motivo : (bpm > 0 ? "alto" : "manuale");

  if (!prova) {
    const { data } = await db.from("jarvis_allarmi").select("creato").eq("prova", false).order("creato", { ascending: false }).limit(1);
    const ultimo = data?.[0]?.creato ? new Date(data[0].creato).getTime() : 0;
    if (Date.now() - ultimo < 5 * 60_000) return json({ ok: true, ripetuto: true, nota: "allarme già inviato da meno di 5 minuti" });
  } else {
    // anche le prove hanno un freno: al massimo 5 all'ora (ogni prova manda SMS o WhatsApp veri)
    const { count } = await db.from("jarvis_allarmi").select("id", { count: "exact", head: true }).eq("prova", true).gte("creato", new Date(Date.now() - 3600_000).toISOString());
    if ((count ?? 0) >= 5) return json({ ok: true, ripetuto: true, nota: "troppe prove nell'ultima ora: riprovi più tardi" });
  }

  const ora = new Intl.DateTimeFormat("it-IT", { timeZone: "Europe/Rome", hour: "2-digit", minute: "2-digit" }).format(new Date());
  const posizione = typeof corpo.posizione === "string" && /^-?\d+(\.\d+)?,-?\d+(\.\d+)?$/.test(corpo.posizione)
    ? ` Dove si trova: https://maps.google.com/?q=${corpo.posizione}` : "";
  const chi = env("NOME_COMPLETO") || "Alessandro Andreucetti";
  const frase = motivo === "manuale"
    ? `Sono Jarvis, l'assistente di ${chi}. Alle ${ora} ha chiesto aiuto premendo il tasto di emergenza${bpm > 0 ? `; il suo battito è a ${bpm} al minuto` : ""}. La prego di chiamarlo subito.`
    : `Sono Jarvis, l'assistente di ${chi}. Alle ${ora} il suo battito cardiaco era a ${bpm} al minuto mentre era a riposo, ${motivo === "basso" ? "troppo basso" : "troppo alto"}, e non ha risposto all'avviso. La prego di chiamarlo subito.`;
  const testo = prova ? "Sono Jarvis, questo è solo un test. Nessuna emergenza." + posizione : frase + posizione;
  const voce = prova ? "Sono Jarvis, questo è solo un test. Nessuna emergenza. Arrivederci." : `${frase} Ripeto. ${frase}`;

  const lavori: Promise<Record<string, unknown>>[] = [];
  for (const w of whatsappDest) lavori.push(whatsapp(w.numero, w.apikey, testo).then((e) => ({ canale: "whatsapp", a: w.numero.slice(0, 4) + "…", ...e })));
  if (conClicksend) for (const n of numeri) {
    const a = internazionale(n);
    lavori.push(clicksend("voice/send", { to: a, body: voce, voice: "female", lang: "it-it", require_input: 0, machine_detection: 0 })
      .then((e) => ({ canale: "chiamata", a: a.slice(0, 4) + "…", ...e })));
    lavori.push(clicksend("sms/send", { to: a, body: testo, source: "jarvis" })
      .then((e) => ({ canale: "sms", a: a.slice(0, 4) + "…", ...e })));
  }
  const esiti = await Promise.all(lavori);
  await db.from("jarvis_allarmi").insert({ bpm, prova, esito: [{ motivo }, ...esiti] });
  const ok = esiti.some((e) => e.ok);
  return json({ ok, canali: esiti.filter((e) => e.ok).map((e) => e.canale), esiti }, ok ? 200 : 502);
});
