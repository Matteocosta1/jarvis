#!/usr/bin/env python3
"""Mockup, 26 ott sera (richiesta del signore): dagli Occhi a Social si sceglie DOVE metterla.
Social › OCCHI apre gli Occhi: lo scatto fa una foto, REC un video (si tocca per partire e per fermare, al massimo 60 s).
Arrivati in Social, sopra la foto: «DOVE LA METTO?» con tre tasti grandi, POST · STORIA · REEL (per un video REEL · STORIA:
su Instagram un video nel profilo è un Reel). Si tocca e si va avanti. La didascalia scritta prima di andare agli Occhi resta.
Uso: mockup_scelta_social.py sorgente.html destinazione.html"""
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
/* 26 ott sera: dagli Occhi a Social, «DOVE LA METTO?» */
.sc-scelta > div { justify-items: center; text-align: center; }
.sc-ft { position: relative; width: min(100%, 36vh); } .sc-ft canvas { width: 100%; aspect-ratio: 1; display: block; border-radius: 12px; border: 1px solid rgba(79,227,255,.35); }
.sc-ft span { position: absolute; left: 8px; bottom: 8px; font: 700 10px var(--mono); letter-spacing: 1px; background: rgba(0,0,0,.6); padding: 3px 7px; border-radius: 6px; color: #fff; }
.sc-tre { width: 100%; display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px; } .sc-tre.due { grid-template-columns: repeat(2, 1fr); }
.sc-tre button { display: grid; justify-items: center; align-content: center; gap: 8px; min-height: 84px; padding: 12px 6px; border-radius: 14px; border: 1px solid rgba(79,227,255,.45); background: rgba(79,227,255,.08); color: var(--ciano); font: 700 11px var(--mono); letter-spacing: 1.5px; cursor: pointer; transition: background .15s; }
.sc-tre button:active { background: rgba(79,227,255,.25); }
.sc-tre i { position: relative; display: block; border: 2px solid currentColor; border-radius: 4px; } .sc-tre i.q { width: 28px; height: 28px; } .sc-tre i.v { width: 21px; height: 36px; }
.sc-tre i.r::after { content: ""; position: absolute; left: 50%; top: 50%; transform: translate(-35%, -50%); border-left: 8px solid currentColor; border-top: 5px solid transparent; border-bottom: 5px solid transparent; }
"""
sost(".sc-conferma b { font: 700 12px var(--mono); letter-spacing: 2px; } .sc-conferma p { margin: 0; font: 13px var(--sans); color: #cfe2e8; }",
     ".sc-conferma b { font: 700 12px var(--mono); letter-spacing: 2px; } .sc-conferma p { margin: 0; font: 13px var(--sans); color: #cfe2e8; }" + CSS)

# Occhi aperti da Social: REC registra un video per Social (tocco = parte, tocco = stop, al massimo 60 s)
sost("""A.querySelector('[data-oc="rec"]').addEventListener("click", async () => { if (occupato) return;""",
     """A.querySelector('[data-oc="rec"]').addEventListener("click", async () => { if (window.OCCHI_PER_SOCIAL) { OCCHI_ATTIVI.socialVideo(); return; } if (occupato) return;""")
sost("""window.OCCHI_PER_SOCIAL = false; window.SOCIAL_DA = { foto: f.foto, da: "occhi" }; await attesa(500); $("chiudiSez").click(); await attesa(450); apriSezione("Social"); }, aggancia:""",
     """window.OCCHI_PER_SOCIAL = false; window.SOCIAL_DA = { foto: f.foto, da: "occhi", dida: window.SOC_DIDA }; await attesa(500); $("chiudiSez").click(); await attesa(450); apriSezione("Social"); },
    socialVideo: async () => { const b0 = A.querySelector(".oc-recbadge"); if (b0) { b0.dataset.fine = "1"; return; }   // secondo tocco: stop
      if (occupato) return; const f0 = fotoAlloStudio(); if (!f0) { parlaMock("Un attimo, Sir: la fotocamera sta ancora mettendo a fuoco.", 2200); return; }
      occupato = true; suona("aTick"); stato("REGISTRO PER SOCIAL");
      const b = document.createElement("div"); b.className = "oc-recbadge"; A.appendChild(b); let s = 0;
      while (!b.dataset.fine && s < 60) { b.innerHTML = `<i></i>REC · ${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`; await attesa(1000); if (!ok() || !A.isConnected) return; s++; }
      b.remove(); suona("aTick"); occupato = false; const f = fotoAlloStudio() || f0; s = Math.max(1, s);
      parlaMock(`Video di ${s} secondi, Sir: lo porto a Social.`, 1800); window.OCCHI_PER_SOCIAL = false;
      window.SOCIAL_DA = { foto: f.foto, da: "occhi", video: s, dida: window.SOC_DIDA }; await attesa(500); $("chiudiSez").click(); await attesa(450); apriSezione("Social"); }, aggancia:""")

# Social › OCCHI: la didascalia scritta resta; JARVIS dice come si fa foto e video
sost("""window.OCCHI_PER_SOCIAL = true; parlaMock("Apro gli Occhi, Sir: inquadri e scatti, la foto torna qui.", 2600);""",
     """window.OCCHI_PER_SOCIAL = true; window.SOC_DIDA = didascalia; parlaMock("Apro gli Occhi, Sir: scatto per una foto, REC per un video.", 2800);""")

# arrivati in Social: «DOVE LA METTO?»
sost("""  const da = window.SOCIAL_DA; window.SOCIAL_DA = null;
  if (da?.foto) { SOC.daOcchi = da.foto; fonte = { k: da.da || "occhi", img: da.foto }; didascalia = DIDA[1]; formato = da.da === "studio" ? "REEL" : "POST"; }""",
     """  function scegliDove() { const v = !!fonte?.video, d = fonte?.durata || 0, F = document.createElement("div"); F.className = "sc-conferma sc-scelta";
    F.innerHTML = `<div><b>DOVE LA METTO?</b><div class="sc-ft"><canvas width="600" height="600"></canvas>${v ? `<span>▶ ${Math.floor(d / 60)}:${String(d % 60).padStart(2, "0")}</span>` : ""}</div><div class="sc-tre${v ? " due" : ""}">${(v ? [["REEL", "v r"], ["STORIA", "v"]] : [["POST", "q"], ["STORIA", "v"], ["REEL", "v r"]]).map(([f, c]) => `<button type="button" data-dove="${f}"><i class="${c}"></i>${f}</button>`).join("")}</div>${v ? "<p>Su Instagram un video nel profilo è un Reel.</p>" : ""}</div>`;
    const im = fonte?.img; if (im) { const cv = F.querySelector("canvas"), x = cv.getContext("2d"), w = im.naturalWidth || im.width, hh = im.naturalHeight || im.height, k = Math.max(600 / w, 600 / hh); try { x.drawImage(im, (600 - w * k) / 2, (600 - hh * k) / 2, w * k, hh * k); } catch (e) {} }
    F.addEventListener("click", (e) => { e.stopPropagation(); const b = e.target.closest("[data-dove]"); if (!b) return; suona("aTick"); formato = b.dataset.dove; F.classList.remove("su"); setTimeout(() => F.remove(), 260); pagina(); });
    A.appendChild(F); requestAnimationFrame(() => F.classList.add("su")); parlaMock(v ? "Reel o storia, Sir?" : "Post, storia o reel, Sir?", 2600); }
  const da = window.SOCIAL_DA; window.SOCIAL_DA = null;
  if (da?.foto) { SOC.daOcchi = da.foto; fonte = { k: da.da || "occhi", img: da.foto, video: !!da.video, durata: da.video || 0 }; didascalia = da.dida || DIDA[1]; window.SOC_DIDA = null; formato = da.da === "studio" || da.video ? "REEL" : "POST";
    if (da.da !== "studio") setTimeout(() => ok() && scegliDove(), 380); }""")

# l'anteprima dice se è un video
sost("""<div class="sc-ant-tipo">${formato}</div>""",
     """<div class="sc-ant-tipo">${formato}${fonte?.video ? ` · VIDEO ${Math.floor(fonte.durata / 60)}:${String(fonte.durata % 60).padStart(2, "0")}` : ""}</div>""")

open(dst, "w", encoding="utf-8").write(h)
print("scritto", dst)
