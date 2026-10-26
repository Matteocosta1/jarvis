#!/usr/bin/env python3
"""Social 10.0 (7): GRIGLIA, PIANO (al posto di CALENDARIO), ORARI, RIVALI nel mockup JARVIS Mark X.
Uso: toppa_social_nuovo.py sorgente.html destinazione.html"""
import sys

src, dst = sys.argv[1], sys.argv[2]
h = open(src, encoding="utf-8").read()

def sost(vecchio, nuovo, n=1):
    global h
    c = h.count(vecchio)
    if c != n:
        sys.exit(f"ATTESO {n}, TROVATO {c}: {vecchio[:90]!r}")
    h = h.replace(vecchio, nuovo)

# ── CSS ──────────────────────────────────────────────────────────────────────
CSS = r"""
/* SOCIAL 10.0 (7): schede su due righe, GRIGLIA, PIANO, ORARI, RIVALI */
.sc-schede { display: grid !important; grid-template-columns: repeat(4, 1fr); gap: 5px; } .sc-schede .chip { padding: 8px 2px; letter-spacing: .5px; }
.sc-griglia { display: grid; grid-template-columns: repeat(3, 1fr); gap: 3px; border-radius: 12px; overflow: hidden; }
.sc-g { position: relative; display: block; width: 100%; height: auto; min-height: 0; aspect-ratio: 3 / 4; align-self: start; padding: 0; border: 0; background: #020a0e; cursor: pointer; overflow: hidden; animation: bwEntra .35s both; }
.sc-g canvas { position: absolute; inset: 0; width: 100%; height: 100%; display: block; }
.sc-g em { position: absolute; top: 5px; right: 6px; font: 700 10px var(--sans); font-style: normal; color: #fff; text-shadow: 0 0 4px #000; }
.sc-g span { position: absolute; left: 5px; bottom: 5px; font: 700 9px var(--mono); color: #fff; text-shadow: 0 0 4px #000, 0 0 2px #000; letter-spacing: .4px; }
.sc-g .sc-g-off { position: absolute; left: 0; right: 0; top: 42%; text-align: center; font: 700 7px var(--mono); letter-spacing: 1px; color: #ffb3b3; background: rgba(0,0,0,.55); padding: 3px 0; font-style: normal; }
.sc-g .sc-g-rank { position: absolute; top: 5px; left: 6px; font: 700 10px var(--mono); color: var(--ciano); text-shadow: 0 0 6px #000; font-style: normal; }
.sc-g.prog { outline: 2px dashed var(--ciano); outline-offset: -2px; touch-action: none; }
.sc-g.prog b { position: absolute; top: 5px; left: 5px; font: 700 8px var(--mono); letter-spacing: .8px; color: #001820; background: var(--ciano); padding: 2px 5px; border-radius: 5px; }
.sc-g.prog::after { content: "⠿"; position: absolute; right: 6px; bottom: 4px; color: var(--ciano); font: 700 14px var(--sans); text-shadow: 0 0 6px #000; }
.sc-g.su { z-index: 5; box-shadow: 0 0 22px rgba(79,227,255,.7); transition: none; animation: none; }
.sc-g.meta { outline: 3px solid var(--ciano); filter: brightness(1.35); }
.sc-g.vecchio { opacity: .55; }
.sc-foglio { position: absolute; left: 0; right: 0; bottom: 0; z-index: 9; max-height: 86%; overflow: auto; display: grid; gap: 12px; padding: 10px 16px 28px; border-radius: 22px 22px 0 0;
  border-top: 1px solid rgba(79,227,255,.5); background: rgba(4,14,18,.98); box-shadow: 0 -10px 40px rgba(0,0,0,.7); transform: translateY(100%); transition: transform .3s cubic-bezier(.2,.8,.2,1); }
.sc-foglio.su { transform: none; } .sc-foglio::before { content: ""; justify-self: center; width: 40px; height: 4px; border-radius: 2px; background: rgba(79,227,255,.4); }
.sc-f-su { display: flex; justify-content: space-between; align-items: center; } .sc-f-su b { font: 700 11px var(--mono); letter-spacing: 2px; }
.sc-f-ant { justify-self: center; width: 150px; aspect-ratio: 3 / 4; border-radius: 12px; overflow: hidden; border: 1px solid rgba(79,227,255,.45); } .sc-f-ant canvas { width: 100%; height: 100%; display: block; }
.sc-n3 { grid-template-columns: repeat(3, 1fr) !important; } .sc-n3 div { padding: 9px !important; } .sc-n3 b { font-size: 17px !important; }
.sc-rosso { color: #ff8a8a !important; border-color: rgba(255,90,90,.5) !important; }
.sc-ore { display: grid; grid-template-columns: 30px repeat(8, 1fr); gap: 3px; align-items: center; }
.sc-ore small { font: 700 8px var(--mono); color: #9fb3b9; letter-spacing: .5px; text-align: center; } .sc-ore small.g { text-align: left; }
.sc-ora { height: 24px; border-radius: 5px; border: 1px solid rgba(79,227,255,.12); padding: 0; cursor: pointer; }
.sc-ora.top { border: 1.5px solid #fff; box-shadow: 0 0 10px rgba(79,227,255,.8); } .sc-ora.sel { outline: 2px solid #fff; outline-offset: 1px; }
.sc-legenda { display: flex; align-items: center; gap: 4px; justify-content: flex-end; font: 600 8px var(--mono); color: #9fb3b9; letter-spacing: .6px; } .sc-legenda i { width: 14px; height: 10px; border-radius: 3px; }
.sc-chiuso { display: grid; gap: 8px; padding: 14px; border-radius: 14px; border: 1px solid rgba(255,196,90,.55); background: rgba(40,28,6,.55); }
.sc-chiuso b { font: 700 10px var(--mono); letter-spacing: 2px; color: #ffc45a; } .sc-chiuso p { margin: 0; font: 13px/1.4 var(--sans); color: #e6f4f8; }
.sc-rivali { display: grid; gap: 8px; } .sc-rivali.sfocato { filter: blur(2.5px); opacity: .55; pointer-events: none; user-select: none; }
.sc-riv { display: grid; grid-template-columns: 1fr repeat(3, auto); gap: 10px; align-items: center; padding: 10px 12px; border-radius: 14px; border: 1px solid rgba(79,227,255,.22); background: rgba(10,31,38,.5); }
.sc-riv.io { border-color: var(--ciano); } .sc-riv b { font: 600 13px var(--sans); color: #fff; } .sc-riv span { display: grid; text-align: right; font: 700 13px var(--mono); color: #fff; } .sc-riv span small { font: 600 7px var(--mono); color: #9fb3b9; letter-spacing: .8px; }
.sc-passi { margin: 0; padding-left: 18px; display: grid; gap: 8px; font: 13px/1.4 var(--sans); color: #e6f4f8; } .sc-passi b { color: var(--ciano); }
"""
sost(".sc-schede em:empty { display: none; }", ".sc-schede em:empty { display: none; }" + CSS)

# ── dati d'esempio ───────────────────────────────────────────────────────────
sost('coda: [{ quando: "LUN 12:00", titolo: "Custom denim · stencil KR", tipo: "REEL" }], pubblicati: [],',
     'coda: [{ quando: "LUN 12:00", titolo: "Custom denim · stencil KR", tipo: "REEL", seme: "q1", dida: "Il jeans che mi avete chiesto: stencil KR fatto a mano, pezzo unico.\\n\\n#kingrusto #customdenim #stencil" },'
     ' { quando: "MER 18:30", titolo: "Stencil su tela · dietro le quinte", tipo: "POST", seme: "q2", dida: "Dietro le quinte: lo stencil prima del colore.\\n\\n#kingrusto #graffiti #processo" },'
     ' { quando: "VEN 13:00", titolo: "Drop di sabato · 4 pezzi", tipo: "CAROSELLO", seme: "q3", dida: "Sabato alle 18 escono 4 pezzi. Commentate LISTA per il link.\\n\\n#kingrusto #drop #streetart" }], pubblicati: [],')

DATI = r"""
// SOCIAL 10.0 (7): i post già pubblicati (GRIGLIA), le ore online dei follower (ORARI), i rivali (RIVALI, da collegare). Tutto d'esempio.
SOC.media = [["REEL", "Giacca custom · stencil KR", "14 OTT", 14800, 1240, 86, 410, 132, 21300], ["POST", "Muro di via Padova", "11 OTT", 0, 980, 41, 120, 18, 7400],
  ["CAROSELLO", "Drop di ottobre · 5 pezzi", "8 OTT", 0, 1510, 122, 380, 64, 11800], ["REEL", "Stampa 3D del logo KR", "4 OTT", 9200, 860, 37, 290, 88, 13900],
  ["POST", "Bomber dipinto", "1 OTT", 0, 720, 29, 60, 9, 5600], ["REEL", "Time-lapse stencil", "27 SET", 21500, 1880, 140, 640, 251, 30100],
  ["POST", "Stencil su tela", "24 SET", 0, 640, 22, 48, 6, 4900], ["CAROSELLO", "Prima e dopo · jeans", "20 SET", 0, 1120, 64, 310, 40, 9100],
  ["REEL", "Live painting Navigli", "15 SET", 7600, 690, 31, 150, 47, 10200]].map(([tipo, titolo, quando, vis, like, comm, salv, cond, cop], i) =>
  ({ id: "m" + i, tipo, titolo, quando, vis, like, comm, salv, cond, cop, commOn: i !== 4, dida: titolo + ". Fatto a mano a Milano.\n\n#kingrusto #streetart #custom" }));
SOC.ore = ["LUN", "MAR", "MER", "GIO", "VEN", "SAB", "DOM"].map((g, d) => [0, 3, 6, 9, 12, 15, 18, 21].map((o) => {   // follower online, migliaia
  const base = { 0: .7, 3: .2, 6: .5, 9: 1.4, 12: 2.4, 15: 1.8, 18: 2.6, 21: 2.9 }[o], extra = (d === 0 && o === 12) ? 1.2 : (d === 3 && o === 21) ? 1.3 : (d === 5 && o === 18) ? .8 : (d >= 5 && o === 9) ? -.5 : 0;
  return Math.max(.1, +(base + extra + ((d * 7 + o) % 5) * .08).toFixed(1)); }));
SOC.rivali = [["kingrusto", 12400, 3.1, 1060, 8.6, true], ["rivale_esempio_1", 18900, 5.4, 1240, 6.6], ["rivale_esempio_2", 9700, 2.2, 990, 10.2], ["rivale_esempio_3", 31200, 6.8, 1610, 5.2]];
SOC.fbCollegato = false;
"""
sost("CONTENUTI.Social = `<div id=\"social\"></div>`;", DATI + "CONTENUTI.Social = `<div id=\"social\"></div>`;")

# ── schede: due righe da 4, CALENDARIO diventa PIANO ─────────────────────────
sost('[["pubblica", "PUBBLICA"], ["posta", "POSTA"], ["calendario", "CALENDARIO"], ["report", "REPORT"], ["automazioni", "AUTOMAZIONI"]]',
     '[["pubblica", "PUBBLICA"], ["posta", "POSTA"], ["griglia", "GRIGLIA"], ["piano", "PIANO"], ["report", "REPORT"], ["orari", "ORARI"], ["rivali", "RIVALI"], ["automazioni", "AUTOMAZIONI"]]')

# stato in più della funzione social()
sost('let scheda = "pubblica", fonte = null, formato = "REEL", quando = "ORA", didascalia = "", giro = 0;',
     'let scheda = "pubblica", fonte = null, formato = "REEL", quando = "ORA", didascalia = "", giro = 0, ordine = "recenti", oraSel = null, trascina = null, saltaClick = false;')

# ── le pagine nuove (al posto di CALENDARIO) ─────────────────────────────────
VECCHIO_CAL_INIZIO = '    if (scheda === "calendario") { const tutti = [...SOC.coda.map((c) => ({ ...c, stato: "PROGRAMMATO" })), ...SOC.pubblicati.map((c) => ({ ...c, stato: "PUBBLICATO" }))];'
i0 = h.index(VECCHIO_CAL_INIZIO)
i1 = h.index('    if (scheda === "report")', i0)

PAGINE = r"""    if (scheda === "griglia") { const M = [...SOC.media];
      if (ordine === "visti") M.sort((a, b) => (b.vis || b.cop) - (a.vis || a.cop)); else if (ordine === "salvati") M.sort((a, b) => b.salv - a.salv);
      const medLike = Math.round(SOC.media.reduce((s, m) => s + m.like, 0) / SOC.media.length), medSalv = Math.round(SOC.media.reduce((s, m) => s + m.salv, 0) / SOC.media.length);
      P.innerHTML = `<div class="sc-numeri sc-n3">${[["POST", SOC.media.length, "ultimi 30 giorni"], ["LIKE MEDI", scNum(medLike), "per post"], ["SALVATAGGI", scNum(medSalv), "medi per post"]].map(([a, b, c]) => `<div><small>${a}</small><b>${b}</b><span>${c}</span></div>`).join("")}</div>
        <div class="sc-riga">${[["recenti", "RECENTI"], ["visti", "PIÙ VISTI"], ["salvati", "PIÙ SALVATI"]].map(([k, n]) => `<button type="button" class="chip" data-ordine="${k}" aria-pressed="${ordine === k}">${n}</button>`).join("")}</div>
        <div class="sc-blocco"><div class="sc-griglia">${M.map((m, i) => `<button type="button" class="sc-g" data-media="${m.id}" style="animation-delay:${i * 35}ms"><canvas width="240" height="320" data-seme="kr${m.id}" data-video=""></canvas>${ordine !== "recenti" ? `<i class="sc-g-rank">${i + 1}</i>` : ""}<em>${m.tipo === "REEL" ? "▶" : m.tipo === "CAROSELLO" ? "❐" : ""}</em><span>${ordine === "salvati" ? "⚑ " + scNum(m.salv) : m.tipo === "REEL" ? "▶ " + scNum(m.vis) : "♥ " + scNum(m.like)}</span>${m.commOn ? "" : `<i class="sc-g-off">COMMENTI OFF</i>`}</button>`).join("")}</div></div>
        <p class="sc-nota">Tocchi un post: i numeri veri, commenti sì o no, e MODIFICA che lo apre nell'app di Instagram. Didascalia e posizione nella griglia si cambiano solo lì: l'API ufficiale non lo permette.</p>`;
      P.querySelectorAll("canvas[data-seme]").forEach((c) => anteprima(c, c.dataset.seme, !!c.dataset.video)); return; }
    if (scheda === "piano") { const Q = [...SOC.coda].sort((a, b) => scChiave(b.quando) - scChiave(a.quando)), posti = Math.max(0, 9 - Q.length);
      P.innerHTML = `<div class="sc-blocco"><div class="sc-et-r"><small class="sc-et">COME SARÀ IL PROFILO</small><small class="sc-et">${Q.length} IN PROGRAMMA</small></div>
        <div class="sc-griglia">${Q.map((c, i) => `<button type="button" class="sc-g prog" data-prog="${SOC.coda.indexOf(c)}" style="animation-delay:${i * 35}ms"><canvas width="240" height="320" data-seme="${c.seme || c.titolo}" data-video=""></canvas><b>${c.quando}</b><em>${c.tipo === "REEL" ? "▶" : c.tipo === "CAROSELLO" ? "❐" : ""}</em></button>`).join("")}${SOC.media.slice(0, posti).map((m) => `<div class="sc-g vecchio"><canvas width="240" height="320" data-seme="kr${m.id}" data-video=""></canvas></div>`).join("")}</div></div>
        <p class="sc-nota">Tratteggiati: i post in programma. Li tenga premuti e li trascini per cambiare l'ordine (si scambiano le ore). Li tocchi per cambiare didascalia e ora. Sbiaditi: quelli già pubblicati.</p>
        <div class="sc-blocco"><small class="sc-et">IN PROGRAMMA</small>${Q.length ? `<div class="sc-lista">${[...Q].reverse().map((c) => `<div class="sc-cal"><div class="sc-cal-d"><b>${c.quando.split(" ")[0]}</b><small>${c.quando.split(" ")[1] || ""}</small></div><div><b>${escSd(c.titolo)}</b><small>${c.tipo} · PROGRAMMATO</small></div><button type="button" class="sc-mini" data-prog="${SOC.coda.indexOf(c)}">CAMBIA</button></div>`).join("")}</div>` : `<p class="sc-nota">Niente in programma.</p>`}</div>
        ${SOC.pubblicati.length ? `<div class="sc-blocco"><small class="sc-et">PUBBLICATI OGGI</small><div class="sc-lista">${SOC.pubblicati.map((c) => `<div class="sc-cal"><div class="sc-cal-d"><b>${c.quando.split(" ")[0]}</b><small>${c.quando.split(" ")[1] || ""}</small></div><div><b>${escSd(c.titolo)}</b><small>${c.tipo} · PUBBLICATO</small></div><span class="sc-ok">✓</span></div>`).join("")}</div></div>` : ""}`;
      P.querySelectorAll("canvas[data-seme]").forEach((c) => anteprima(c, c.dataset.seme, !!c.dataset.video)); return; }
    if (scheda === "orari") { const G = ["LUN", "MAR", "MER", "GIO", "VEN", "SAB", "DOM"], O = [0, 3, 6, 9, 12, 15, 18, 21], mx = Math.max(...SOC.ore.flat());
      const top = SOC.ore.flatMap((r, d) => r.map((v, o) => ({ d, o, v }))).sort((a, b) => b.v - a.v).slice(0, 3), eTop = (d, o) => top.some((t) => t.d === d && t.o === o);
      const sel = oraSel || top[0], v = SOC.ore[sel.d][sel.o];
      P.innerHTML = `<div class="sc-numeri">${top.slice(0, 2).map((t, i) => `<div><small>${i ? "SECONDO" : "IL MIGLIORE"}</small><b>${G[t.d]} ${String(O[t.o]).padStart(2, "0")}</b><span>${String(t.v).replace(".", ",")}K follower online</span></div>`).join("")}</div>
        <div class="sc-blocco"><small class="sc-et">FOLLOWER ONLINE · ULTIMI 30 GIORNI</small><div class="sc-ore"><small></small>${O.map((o) => `<small>${String(o).padStart(2, "0")}</small>`).join("")}
          ${SOC.ore.map((r, d) => `<small class="g">${G[d]}</small>${r.map((x, o) => `<button type="button" class="sc-ora${eTop(d, o) ? " top" : ""}${sel.d === d && sel.o === o ? " sel" : ""}" data-ora="${d},${o}" aria-label="${G[d]} ore ${O[o]}: ${x} mila" style="background:rgba(79,227,255,${(.08 + .92 * (x / mx) ** 1.6).toFixed(2)})"></button>`).join("")}`).join("")}</div>
          <div class="sc-legenda">MENO ${[.12, .35, .6, .9].map((a) => `<i style="background:rgba(79,227,255,${a})"></i>`).join("")} PIÙ</div></div>
        <div class="sc-cal"><div class="sc-cal-d"><b>${G[sel.d]}</b><small>${String(O[sel.o]).padStart(2, "0")}:00</small></div><div><b>${String(v).replace(".", ",")}K follower online</b><small>${eTop(sel.d, sel.o) ? "TRA I 3 ORARI MIGLIORI" : `${Math.round(v / top[0].v * 100)}% DEL MIGLIORE`}</small></div></div>
        <button type="button" class="sc-vai" data-az="programmaOra">PROGRAMMA ${G[sel.d]} ALLE ${String(O[sel.o]).padStart(2, "0")}</button>
        <p class="sc-nota">Dalle statistiche ufficiali di Instagram (follower online, ora per ora). Tocchi una casella per vedere quell'ora. Numeri d'esempio.</p>`; return; }
    if (scheda === "rivali") { const R = SOC.rivali, mx = Math.max(...R.map((r) => r[4]));
      P.innerHTML = `${SOC.fbCollegato ? "" : `<div class="sc-chiuso"><b>DA COLLEGARE</b><p>Per guardare altri account Instagram vuole la pagina Facebook collegata a @kingrusto. È gratis e si fa una volta sola, in circa 5 minuti.</p><button type="button" class="sc-mini" data-az="comeRivali">COME SI COLLEGA</button></div>`}
        <div class="sc-rivali${SOC.fbCollegato ? "" : " sfocato"}">${R.map(([n, f, ps, lk, er, io]) => `<div class="sc-riv${io ? " io" : ""}"><div><b>@${n}</b><div style="height:4px;margin-top:6px;border-radius:2px;background:rgba(79,227,255,.15)"><div style="height:100%;width:${(er / mx * 100).toFixed(0)}%;border-radius:2px;background:var(--ciano)"></div></div></div><span>${scNum(f)}<small>FOLLOWER</small></span><span>${String(ps).replace(".", ",")}<small>POST/SETT</small></span><span>${String(er).replace(".", ",")}%<small>COINVOLG.</small></span></div>`).join("")}</div>
        ${SOC.fbCollegato ? `<button type="button" class="sc-vai" data-az="riassuntoRivali">COME SONO MESSO?</button>` : ""}
        <p class="sc-nota">Si vedono solo account professionali pubblici: follower, post, like e commenti dei loro ultimi post. Le storie e i messaggi degli altri non si vedono. Dati d'esempio.</p>`; return; }
"""
h = h[:i0] + PAGINE + h[i1:]

# aiuti: numeri brevi e chiave d'ordine dei giorni
sost("function social(ok) {",
     "const scNum = (n) => n >= 1000 ? (n / 1000).toFixed(1).replace(\".0\", \"\").replace(\".\", \",\") + \"K\" : String(n);\n"
     "const scChiave = (q) => { const [g, o = \"0:0\"] = q.split(\" \"), [hh, mm] = o.split(\":\").map(Number); return Math.max(0, [\"LUN\", \"MAR\", \"MER\", \"GIO\", \"VEN\", \"SAB\", \"DOM\"].indexOf(g)) * 1440 + hh * 60 + (mm || 0); };\n"
     "function social(ok) {")

# ── click: le azioni nuove ───────────────────────────────────────────────────
CLICK = r"""    if (saltaClick) { saltaClick = false; return; }
    if (b.dataset.ordine) { suona("aTick"); ordine = b.dataset.ordine; pagina(); return; }
    if (b.dataset.media) { suona("aTick"); foglioMedia(SOC.media.find((m) => m.id === b.dataset.media)); return; }
    if (b.dataset.prog) { suona("aTick"); foglioProg(+b.dataset.prog); return; }
    if (b.dataset.ora) { suona("aTick"); const [d, o] = b.dataset.ora.split(",").map(Number); oraSel = { d, o }; pagina(); return; }
    if (b.dataset.az === "programmaOra") { const G = ["LUN", "MAR", "MER", "GIO", "VEN", "SAB", "DOM"], s = oraSel || SOC.ore.flatMap((r, d) => r.map((v, o) => ({ d, o, v }))).sort((a, c) => c.v - a.v)[0];
      suona("aTick"); quando = `${G[s.d]} ${String([0, 3, 6, 9, 12, 15, 18, 21][s.o]).padStart(2, "0")}:00`; scheda = "pubblica"; A.querySelectorAll("[data-sc]").forEach((x) => x.setAttribute("aria-pressed", x.dataset.sc === "pubblica"));
      parlaMock(`Bene, Sir: il prossimo post esce ${quando.toLowerCase().replace(" ", " alle ")}. Scelga cosa pubblicare.`, 2800); pagina(); return; }
    if (b.dataset.az === "comeRivali") { suona("aTick"); foglio(`<div class="sc-f-su"><b>COLLEGARE FACEBOOK</b><button type="button" class="sc-chiudi" data-f="chiudi">Chiudi</button></div>
        <ol class="sc-passi"><li>Nell'app di Instagram: <b>Profilo › Modifica profilo › Pagina</b>.</li><li>Tocchi <b>Crea</b> (o scelga una pagina che ha già). Il nome può essere KING RUSTO.</li><li>Torni qui e tocchi <b>COLLEGA</b>: JARVIS le chiede un solo permesso a Facebook.</li><li>Da lì RIVALI si accende: scelga fino a 10 account da seguire.</li></ol>
        <button type="button" class="sc-vai" data-f="collega">COLLEGA (PROVA)</button><p class="sc-nota">La pagina Facebook non deve pubblicare niente: serve solo come chiave per vedere gli altri account.</p>`); return; }
    if (b.dataset.az === "riassuntoRivali") { suona("aTick"); parlaMock("Lei ha il coinvolgimento più alto dopo rivale_esempio_2, Sir: 8,6 per cento. Chi pubblica di più è rivale_esempio_3, quasi 7 post a settimana: lei ne fa 3. Un Reel in più a settimana la porterebbe davanti.", 6500); return; }
"""
sost("    if (b.dataset.sc) { suona(\"aTick\"); scheda = b.dataset.sc;", CLICK + "    if (b.dataset.sc) { suona(\"aTick\"); scheda = b.dataset.sc;")

# ── fogli (scheda post, post programmato) e trascinamento nel PIANO ─────────
FOGLI = r"""  // il foglio che sale dal basso: la scheda di un post (GRIGLIA), un post in programma (PIANO), i passi per Facebook (RIVALI)
  function foglio(html, dopo) { A.querySelector(".sc-foglio")?.remove(); const F = document.createElement("div"); F.className = "sc-foglio"; F.innerHTML = html; A.appendChild(F); requestAnimationFrame(() => F.classList.add("su"));
    const via = () => { F.classList.remove("su"); setTimeout(() => F.remove(), 300); };
    F.addEventListener("click", (ev) => { const el = ev.target.closest("[data-f]"), k = el?.dataset.f; if (!k) return; ev.stopPropagation(); if (k === "chiudi") { suona("aTick"); via(); return; }
      if (k === "collega") { suona("aPronto"); SOC.fbCollegato = true; via(); parlaMock("Collegato, Sir: ecco i rivali.", 2200); pagina(); return; } dopo?.(k, F, via, el); });
    F.querySelectorAll("canvas[data-seme]").forEach((c) => anteprima(c, c.dataset.seme, !!c.dataset.video)); return F; }
  function foglioMedia(m) { if (!m) return; const med = (k) => SOC.media.reduce((s, x) => s + x[k], 0) / SOC.media.length, r = m.salv / med("salv");
    foglio(`<div class="sc-f-su"><b>${m.tipo} · ${m.quando}</b><button type="button" class="sc-chiudi" data-f="chiudi">Chiudi</button></div>
      <div class="sc-f-ant"><canvas width="300" height="400" data-seme="kr${m.id}" data-video="${m.tipo === "REEL" ? 1 : ""}"></canvas></div>
      <div class="sc-numeri sc-n3">${[["COPERTURA", m.cop], [m.tipo === "REEL" ? "VISUALIZZ." : "SALVATAGGI", m.tipo === "REEL" ? m.vis : m.salv], ["LIKE", m.like], ["COMMENTI", m.comm], ["CONDIVISIONI", m.cond], [m.tipo === "REEL" ? "SALVATAGGI" : "INTERAZIONI", m.tipo === "REEL" ? m.salv : m.like + m.comm + m.salv + m.cond]].map(([a, b]) => `<div><small>${a}</small><b>${scNum(b)}</b></div>`).join("")}</div>
      <p class="sc-auto">${r >= 1.3 ? `Salvato ${r.toFixed(1).replace(".", ",")} volte più della sua media: questo genere funziona, Sir.` : r <= .6 ? "Sotto la sua media di salvataggi, Sir." : "In linea con la sua media, Sir."}</p>
      <div class="sc-blocco"><small class="sc-et">DIDASCALIA</small><p class="sc-testo" style="white-space:pre-line">${escSd(m.dida)}</p></div>
      <div class="sc-et-r"><small class="sc-et">COMMENTI ${m.commOn ? "ATTIVI" : "DISATTIVATI"}</small><button type="button" class="sc-int${m.commOn ? " on" : ""}" data-f="commenti" aria-pressed="${m.commOn}" aria-label="Commenti"><i></i></button></div>
      <button type="button" class="sc-vai" data-f="modifica">MODIFICA SU INSTAGRAM</button>
      <p class="sc-nota">MODIFICA apre questo post nell'app di Instagram: lì si cambiano didascalia, copertina e posizione. Da qui si accendono e spengono i commenti.</p>`,
      (k, F) => { if (k === "commenti") { suona("aTick"); m.commOn = !m.commOn; const t = F.querySelector('[data-f="commenti"]'); t.classList.toggle("on", m.commOn); t.setAttribute("aria-pressed", m.commOn); t.previousElementSibling.textContent = `COMMENTI ${m.commOn ? "ATTIVI" : "DISATTIVATI"}`;
          parlaMock(m.commOn ? "Commenti riaccesi, Sir." : "Commenti spenti su questo post, Sir.", 2000); pagina(); }
        if (k === "modifica") { suona("aTick"); parlaMock("Apro il post nell'app di Instagram, Sir: tocchi i tre puntini › Modifica.", 3000); } }); }
  function foglioProg(i) { const c = SOC.coda[i]; if (!c) return; const ORE = ["LUN 12:00", "MER 18:30", "GIO 21:00", "VEN 13:00", "SAB 18:00"]; let q = c.quando;
    const F = foglio(`<div class="sc-f-su"><b>PROGRAMMATO · ${c.tipo}</b><button type="button" class="sc-chiudi" data-f="chiudi">Chiudi</button></div>
      <div class="sc-f-ant"><canvas width="300" height="400" data-seme="${c.seme || c.titolo}" data-video="${c.tipo === "REEL" ? 1 : ""}"></canvas></div>
      <label class="sc-campo"><span>DIDASCALIA</span><textarea id="scProgDida" rows="4">${escSd(c.dida || c.titolo)}</textarea></label>
      <div class="sc-blocco"><small class="sc-et">QUANDO</small><div class="sc-riga" style="flex-wrap:wrap">${[...new Set([c.quando, ...ORE])].map((o) => `<button type="button" class="chip" style="flex:0 0 auto;padding:8px 10px;white-space:nowrap" data-f="ora" data-o="${o}" aria-pressed="${o === q}">${o}</button>`).join("")}</div></div>
      <div class="sc-riga"><button type="button" class="chip acceso" data-f="salva">SALVA</button><button type="button" class="chip sc-rosso" data-f="togli">TOGLI</button></div>
      <p class="sc-nota">Finché non esce si cambia tutto da qui: il post lo tiene JARVIS e lo pubblica all'ora giusta.</p>`,
      (k, F, via, e) => {
        if (k === "ora") { suona("aTick"); q = e.dataset.o; F.querySelectorAll('[data-f="ora"]').forEach((x) => x.setAttribute("aria-pressed", x === e)); }
        if (k === "salva") { suona("aPronto"); c.dida = F.querySelector("#scProgDida").value; c.titolo = (c.dida.split(/[.!\n]/)[0] || c.titolo).slice(0, 40); c.quando = q; via(); parlaMock(`Salvato, Sir: esce ${q.toLowerCase().replace(" ", " alle ")}.`, 2400); pagina(); }
        if (k === "togli") { suona("aTick"); SOC.coda.splice(i, 1); via(); parlaMock("Tolto dal programma, Sir.", 1800); pagina(); } }); }
  // PIANO: tenere premuto e trascinare un post in programma sopra un altro scambia i due (le ore restano al loro posto)
  P.addEventListener("pointerdown", (e) => { const t = e.target.closest(".sc-g.prog"); if (!t || scheda !== "piano") return; trascina = { el: t, i: +t.dataset.prog, x: e.clientX, y: e.clientY, mosso: false }; t.setPointerCapture(e.pointerId); });
  P.addEventListener("pointermove", (e) => { if (!trascina) return; const dx = e.clientX - trascina.x, dy = e.clientY - trascina.y; if (!trascina.mosso && Math.hypot(dx, dy) < 8) return;
    trascina.mosso = true; trascina.el.classList.add("su"); trascina.el.style.transform = `translate(${dx}px, ${dy}px) scale(1.06)`;
    const sotto = document.elementsFromPoint(e.clientX, e.clientY).find((n) => n.classList?.contains("prog") && n !== trascina.el); P.querySelectorAll(".sc-g.prog").forEach((n) => n.classList.toggle("meta", n === sotto)); });
  const lascia = (e) => { if (!trascina) return; const T = trascina; trascina = null; if (!T.mosso) return; saltaClick = true; setTimeout(() => { saltaClick = false; }, 50);
    const m = P.querySelector(".sc-g.meta"); if (m && e.type === "pointerup") { const a = SOC.coda[T.i], b = SOC.coda[+m.dataset.prog]; const qa = a.quando; a.quando = b.quando; b.quando = qa; suona("aPronto");
      parlaMock(`Scambiati, Sir: «${a.titolo}» esce ${a.quando.toLowerCase().replace(" ", " alle ")}.`, 2600); } pagina(); };
  P.addEventListener("pointerup", lascia); P.addEventListener("pointercancel", lascia);
"""
sost("  // arrivi: dallo Studio (il pezzo per un Reel), da Occhi (la foto), a voce", FOGLI + "  // arrivi: dallo Studio (il pezzo per un Reel), da Occhi (la foto), a voce")

# PROGRAMMA da PUBBLICA: va nel PIANO con didascalia e ora scelta
sost('if (quando !== "ORA") { SOC.coda.unshift({ quando: "LUN 12:00", titolo, tipo: formato }); parlaMock("Programmato per lunedì alle 12, Sir: è l\'orario in cui i suoi follower sono più attivi.", 3000); scheda = "calendario"; A.querySelectorAll("[data-sc]").forEach((x) => x.setAttribute("aria-pressed", x.dataset.sc === "calendario")); pagina(); return; }',
     'if (quando !== "ORA") { SOC.coda.push({ quando, titolo, tipo: formato, dida: didascalia, seme: "nuovo" + Date.now() }); parlaMock(`Programmato per ${quando.toLowerCase().replace(" ", " alle ")}, Sir: lo trova nel PIANO.`, 3000); scheda = "piano"; A.querySelectorAll("[data-sc]").forEach((x) => x.setAttribute("aria-pressed", x.dataset.sc === "piano")); fonte = null; didascalia = ""; quando = "ORA"; pagina(); return; }')
sost('${[["ORA", "ORA"], ["LUN 12:00", "LUN 12:00 · ORARIO MIGLIORE"]].map(',
     '${[["ORA", "ORA"], ...(quando !== "ORA" && quando !== "LUN 12:00" ? [[quando, quando]] : []), ["LUN 12:00", "LUN 12:00 · ORARIO MIGLIORE"]].map(')
sost('${quando === "ORA" ? "PUBBLICO SU @KINGRUSTO?" : "PROGRAMMO PER LUNEDÌ ALLE 12?"}',
     '${quando === "ORA" ? "PUBBLICO SU @KINGRUSTO?" : `PROGRAMMO PER ${quando.replace(" ", " ALLE ")}?`}')

# voce: CALENDARIO porta al PIANO; GRIGLIA, ORARI e RIVALI a voce
sost('else if (typeof da === "string") { scheda = da.toLowerCase();',
     'else if (typeof da === "string") { scheda = da === "CALENDARIO" ? "piano" : da.toLowerCase();')
sost('CALENDARIO: "Il calendario dei post, Sir." }',
     'CALENDARIO: "Il piano dei post, Sir.", PIANO: "Il piano dei post, Sir.", GRIGLIA: "La sua griglia, Sir.", ORARI: "Ecco quando i suoi follower sono online, Sir.", RIVALI: "I rivali, Sir." }')
sost('["Jarvis, cosa ho in programma su Instagram?", "Social", "CALENDARIO"],',
     '["Jarvis, cosa ho in programma su Instagram?", "Social", "PIANO"], ["Jarvis, fammi vedere la mia griglia", "Social", "GRIGLIA"], ["Jarvis, quando sono online i miei follower?", "Social", "ORARI"],')

# testata del commento
sost("CALENDARIO, REPORT, AUTOMAZIONI («commenta LISTA» → link in DM).",
     "GRIGLIA (i post con i numeri, commenti sì/no, MODIFICA nell'app), PIANO (il profilo come sarà, i post in programma si trascinano), REPORT, ORARI (follower online),\n      RIVALI (serve la pagina Facebook collegata), AUTOMAZIONI («commenta LISTA» → link in DM).")

open(dst, "w", encoding="utf-8").write(h)
print("ok", len(h))
