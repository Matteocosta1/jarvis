#!/usr/bin/env python3
"""Mockup, decisioni del 26 ott sera. TRAVEL al polso: nel mockup JARVIS Mark X, sezione «BUILD 22 · POLSO», un tasto TRAVEL
e la schermata del polso. Sei pagine come l'iPhone (MEZZI · TRENI · VOLI · PIEDI · BICI · TAXI), una per volta: si passa
dall'una all'altra con la Digital Crown o col dito in su e in giù (le pagine verticali di watchOS), i puntini a destra dicono
dove si è. A voce si apre già sulla pagina chiesta («come arrivo da Bea?» → MEZZI, «a che ora parte il treno?» → TRENI…).
Uso: mockup_travel_polso.py sorgente.html destinazione.html"""
import sys

src, dst = sys.argv[1], sys.argv[2]
h = open(src, encoding="utf-8").read()


def sost(vecchio, nuovo, n=1):
    global h
    c = h.count(vecchio)
    if c != n:
        sys.exit(f"ATTESO {n}, TROVATO {c}: {vecchio[:90]!r}")
    h = h.replace(vecchio, nuovo)


CSS = r"""
/* TRAVEL al polso (proposta 26 ott sera): pagine verticali come watchOS, puntini a destra */
.w22 .wpag { position: absolute; right: 6px; top: 50%; transform: translateY(-50%); display: grid; gap: 4px; z-index: 2; }
.w22 .wpag i { width: 4px; height: 4px; border-radius: 2px; background: rgba(79,227,255,.3); cursor: pointer; transition: height .2s, background .2s; }
.w22 .wpag i.on { height: 11px; background: var(--ciano); box-shadow: 0 0 6px var(--ciano); }
.w22 .wtv { width: 100%; display: flex; flex-direction: column; align-items: center; gap: 4px; padding-right: 8px; box-sizing: border-box; touch-action: none; }
.w22 .wtv-ora { font: 700 34px var(--mono); color: var(--ciano); line-height: 1; text-shadow: 0 0 12px rgba(79,227,255,.45); }
.w22 .wtv-fra { font: 10px var(--mono); color: #e6f4f8; }
.w22 .wtv .wl span { min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.w22 .wtv .wl em { flex: none; }
.w22 .wsig { display: inline-grid; place-items: center; width: 17px; height: 17px; border-radius: 50%; font: 700 7px var(--mono); color: #fff; font-style: normal; margin-right: 4px; vertical-align: middle; }
.w22 .wtv .amb { color: #ff9f43; } .w22 .wtv .gia { color: #ffd27a; } .w22 .wtv .ver { color: var(--verde); }
"""
sost(".w22 .wnot b { font: 700 9px var(--mono); letter-spacing: 1px; color: var(--ciano); }",
     ".w22 .wnot b { font: 700 9px var(--mono); letter-spacing: 1px; color: var(--ciano); }" + CSS)

# il tasto TRAVEL tra SATELLITE e SHAZAM
sost('<button class="chip" type="button" data-w22="satellite" aria-pressed="false">SATELLITE</button>',
     '<button class="chip" type="button" data-w22="satellite" aria-pressed="false">SATELLITE</button><button class="chip" type="button" data-w22="travel" aria-pressed="false">TRAVEL</button>')

SCHERMO = r"""      } else if (k === "travel") {                                   // TRAVEL al polso (proposta 26 ott sera): sei pagine verticali, una per volta
        const P = ["mezzi", "treni", "voli", "piedi", "bici", "taxi"], TIT = { mezzi: "MEZZI", treni: "TRENI", voli: "VOLI", piedi: "PIEDI", bici: "BICI", taxi: "TAXI" };
        let pg = P.indexOf(window.TRAVEL_POLSO || "mezzi"); if (pg < 0) pg = 0; window.TRAVEL_POLSO = null; let secondi = 12 * 60, ultimo = 0;
        const sig = (s, c) => `<i class="wsig" style="background:${c}">${s}</i>`;
        const pagina = (verso) => { const p = P[pg]; let x = `<div class="wt">TRAVEL · ${p === "mezzi" ? "BEA" : TIT[p]}</div>`;
          if (p === "mezzi") x += `<div class="ws">ESCI ALLE</div><div class="wtv-ora">19:22</div><div class="wtv-fra" id="wtvFra"></div>
            <div class="wl"><div><span>${sig("M1", "#c8001a")}Duomo → Loreto</span><em>19:27</em></div><div><span>${sig("M2", "#007a2e")}Loreto → [fermata]</span><em>19:39</em></div><div><span>Arrivo da Bea</span><em>19:58</em></div></div>
            <button class="wb${window.DI_TRAVEL ? " on" : ""}" type="button" data-wtv="avvisa">${window.DI_TRAVEL ? "AVVISO 19:17<span>✓</span>" : "AVVISAMI<span>›</span>"}</button>`;
          else if (p === "treni") x += `<div class="ws">Milano Centrale · 20:27</div>
            <div class="wl">${[["20:20", "Tirano", "6", "+1", "gia"], ["20:25", "Catania C.le", "17", "+10", "amb"], ["20:25", "Chiasso", "5", "orario", "ver"], ["20:25", "Torino P.N.", "3", "+2", "gia"], ["20:30", "Bozzolo", "14", "orario", "ver"]].map(([o, d, b, r, c]) => `<div><span><b>${o}</b> ${d}</span><em><span class="${c}">${r}</span> · ${b}</em></div>`).join("")}</div>
            <div class="ws">ritardo · binario</div>`;
          else if (p === "voli") x += `<div class="wn" style="font-size:20px">AZ 2041</div><div class="ws">LIN → FCO · [esempio]</div>
            <div class="wl"><div><span>Parte</span><em>07:00</em></div><div><span>Gate</span><em>A12</em></div><div><span>Stato</span><em class="ver">IN ORARIO</em></div></div>
            <div class="ws">Per Linate: M4 da San Babila · esci alle 05:40</div>`;
          else if (p === "piedi") x += `<div class="ws">A PIEDI</div><div class="wtv-ora">48 min</div><div class="ws">3,6 km · arrivo 20:10 se esce adesso</div>
            <button class="wb" type="button" data-wtv="guida">GUIDA<span>›</span></button>`;
          else if (p === "bici") x += `<div class="wl">${[["[Stazione 1]", "120 m", 6, 2], ["[Stazione 2]", "350 m", 1, 0], ["[Stazione arrivo]", "da Bea", 3, 4]].map(([n, d, b, e]) => `<div><span>${n} <small style="color:var(--tenue)">${d}</small></span><em>${b} · ${e}⚡</em></div>`).join("")}</div>
            <div class="ws">bici · elettriche ⚡ · BikeMi</div>`;
          else x += `<div class="ws">RADIOTAXI</div><div class="wtv-ora" style="font-size:28px">02 8585</div><div class="ws">15 min in auto fino da Bea</div>
            <button class="wb" type="button" data-wtv="taxi">CHIAMA<span>›</span></button>`;
          S.innerHTML = `<div class="wpag">${P.map((_, i) => `<i data-wpg="${i}" class="${i === pg ? "on" : ""}"></i>`).join("")}</div><div class="wtv">${x}</div>`;
          if (verso) S.querySelector(".wtv").animate([{ transform: `translateY(${verso * 26}px)`, opacity: 0 }, { transform: "none", opacity: 1 }], { duration: 260, easing: "cubic-bezier(.2,.8,.2,1)" });
          conta(); };
        const conta = () => { const f = $("wtvFra"); if (f) f.textContent = `fra ${Math.floor(secondi / 60)} min ${String(secondi % 60).padStart(2, "0")} s`; };
        const vai = (d) => { const n = Math.max(0, Math.min(P.length - 1, pg + d)); if (n === pg) return; pg = n; suona("aTick"); try { navigator.vibrate && navigator.vibrate(8); } catch {} pagina(d); };
        pagina(0);
        // la Digital Crown (rotellina) e il dito in su e in giù
        S.onwheel = (e) => { if (id !== gen) return; e.preventDefault(); const t = performance.now(); if (t - ultimo < 320 || Math.abs(e.deltaY) < 4) return; ultimo = t; vai(e.deltaY > 0 ? 1 : -1); };
        let y0 = null; S.onpointerdown = (e) => { y0 = e.clientY; }; S.onpointerup = (e) => { if (y0 == null) return; const dy = e.clientY - y0; y0 = null; if (Math.abs(dy) > 24) vai(dy < 0 ? 1 : -1); };
        S.onclick = (e) => { if (id !== gen) return; const d = e.target.closest("[data-wpg]"); if (d) { const n = +d.dataset.wpg; if (n !== pg) { const v = n > pg ? 1 : -1; pg = n; suona("aTick"); pagina(v); } return; }
          const a = e.target.closest("[data-wtv]")?.dataset.wtv; if (!a) return; suona("aTick");
          if (a === "avvisa") { window.DI_TRAVEL = !window.DI_TRAVEL; if (window.DI_TRAVEL) { suona("aPronto"); notifica("Le dico io quando uscire, Sir: alle 19:17. Il conto alla rovescia è anche nella Dynamic Island.", { titolo: "Travel" }); } pagina(0); }
          else if (a === "guida") { guidaSat(0, () => true, true); mostra("guida"); }
          else if (a === "taxi") notifica("Chiamo il radiotaxi, Sir: 02 8585.", { titolo: "Travel" }); };
        const giro = setInterval(() => { if (id !== gen || !S.isConnected) { clearInterval(giro); S.onwheel = S.onpointerdown = S.onpointerup = S.onclick = null; return; } secondi = secondi > 0 ? secondi - 1 : 12 * 60; conta(); }, 1000);
"""
sost('      } else if (k === "social") {', SCHERMO + '      } else if (k === "social") {')


# ── TAXI (scelto dal signore il 26 ott sera): radiotaxi 02 8585 e l'app inTaxi ──
sost('<button type="button" class="comando" data-tv-az="app">Apri l\'app taxi su «Bea»</button><div class="tv-nota">Stima: 15 min · numero del radiotaxi [da scegliere]</div>',
     '<button type="button" class="comando" data-tv-az="app">Apri inTaxi</button><div class="tv-nota">Radiotaxi 02 8585 · stima del tragitto: 15 min</div>')
sost('notifica(a === "taxi" ? "Chiamo il radiotaxi, Sir." : "Apro l\'app dei taxi con l\'indirizzo di Bea, Sir.")',
     'notifica(a === "taxi" ? "Chiamo il radiotaxi, Sir: 02 8585." : "Apro inTaxi, Sir.")')

# ── SOCIAL › OCCHI (sì del signore, 26 ott sera): apre gli Occhi di JARVIS; lo scatto torna a Social ──
sost('else if (k === "occhi") { fonte = { k, img: SOC.daOcchi || null }; if (!SOC.daOcchi) parlaMock(',
     'else if (k === "occhi" && !SOC.daOcchi && !window.JARVIS_APP) { window.OCCHI_PER_SOCIAL = true; parlaMock("Apro gli Occhi, Sir: inquadri e scatti, la foto torna qui.", 2600); $("chiudiSez").click(); await attesa(450); apriSezione("Occhi"); return; }\n      '
     'else if (k === "occhi") { fonte = { k, img: SOC.daOcchi || null }; if (!SOC.daOcchi) parlaMock(')
sost("A.querySelector('[data-oc=\"scatta\"]').addEventListener(\"click\", async () => { if (occupato) return; occupato = true;",
     "A.querySelector('[data-oc=\"scatta\"]').addEventListener(\"click\", async () => { if (occupato) return; if (window.OCCHI_PER_SOCIAL) { OCCHI_ATTIVI.social(); return; } occupato = true;")

sost('parlaMock("Scattata, Sir: la preparo per Instagram.", 1800); window.SOCIAL_DA = { foto: f.foto, da: "occhi" }; await attesa(500);',
     'parlaMock("Scattata, Sir: la preparo per Instagram.", 1800); window.OCCHI_PER_SOCIAL = false; window.SOCIAL_DA = { foto: f.foto, da: "occhi" }; await attesa(500);')

open(dst, "w", encoding="utf-8").write(h)
print("ok", len(h))
