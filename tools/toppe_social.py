# ── SOCIAL nell'app: le toppe sulla pagina del mockup (incluse da studio_app.py) ──
# Dati veri dal cervello (funzione «social»), pubblicazione, risposte, calendario, automazione. Solo con window.JARVIS_APP:
# nel mockup tutto resta com'era.

def toppe_social(s, toppa):
    s = toppa(s, '<div class="sc-num"><b>12,4K</b>', '<div class="sc-num"><b data-soc="follower">${window.JARVIS_APP ? "…" : "12,4K"}</b>')
    s = toppa(s, "<small>INSTAGRAM · ACCOUNT&nbsp;CREATOR · DATI&nbsp;D'ESEMPIO</small>",
              "<small data-soc=\"sotto\">${window.JARVIS_APP ? \"INSTAGRAM · ACCOUNT&nbsp;CREATOR · CARICO…\" : \"INSTAGRAM · ACCOUNT&nbsp;CREATOR · DATI&nbsp;D'ESEMPIO\"}</small>")
    s = toppa(s, '  function pagina() { giro++; contaPosta();',
              '  if (window.JARVIS_APP) { window.__socRidisegna = () => { if (!A.isConnected) return; const v = SOC.vero; if (v) { const f = A.querySelector(\'[data-soc="follower"]\'); if (f) f.textContent = v.profilo ? v.profilo.followerTesto : "—"; '
              'const so = A.querySelector(\'[data-soc="sotto"]\'); if (so) so.innerHTML = v.errore ? "INSTAGRAM · " + escSd(v.errore).toUpperCase() : "INSTAGRAM · ACCOUNT&nbsp;CREATOR"; } const f = document.activeElement; if (f && P.contains(f) && /TEXTAREA|INPUT/.test(f.tagName)) contaPosta(); else pagina(); }; '
              'window.__socFonte = (im, k, v) => { fonte = { k: k || "galleria", img: im, video: !!v }; if (v) formato = "REEL"; if (!didascalia) didascalia = DIDA[k === "studio" ? 0 : 1]; pagina(); }; '
              'window.webkit.messageHandlers.jarvis.postMessage({ tipo: "socialStato" }); }\n  function pagina() { giro++; contaPosta();')
    s = toppa(s, 'else { const c = document.createElement("canvas"); c.width = 360; c.height = 640; anteprima(c, "galleria" + Date.now()); fonte = { k, img: c }; }',
              'else if (window.JARVIS_APP) { window.webkit.messageHandlers.jarvis.postMessage({ tipo: "socialFoto", da: "galleria" }); return; } else { const c = document.createElement("canvas"); c.width = 360; c.height = 640; anteprima(c, "galleria" + Date.now()); fonte = { k, img: c }; }')
    s = toppa(s, 'else if (k === "occhi") { fonte = { k, img: SOC.daOcchi || null }; if (!SOC.daOcchi) parlaMock(',
              'else if (k === "occhi" && window.JARVIS_APP && !SOC.daOcchi) { window.webkit.messageHandlers.jarvis.postMessage({ tipo: "socialFoto", da: "occhi" }); return; } else if (k === "occhi") { fonte = { k, img: SOC.daOcchi || null }; if (!SOC.daOcchi) parlaMock(')
    s = toppa(s, 'Commenti e messaggi arrivano subito (webhook). Ai messaggi si risponde entro 24 ore, regola di Instagram.',
              '${window.JARVIS_APP ? "Commenti e messaggi degli ultimi 5 post e della chat, aggiornati a ogni apertura. Finché l’app Meta è in sviluppo, Instagram mostra solo quelli degli account di prova. Ai messaggi si risponde entro 24 ore." : "Commenti e messaggi arrivano subito (webhook). Ai messaggi si risponde entro 24 ore, regola di Instagram."}')
    s = toppa(s, '[["FOLLOWER", "12,4K", "+184 in 7 giorni"], ["COPERTURA", "38,2K", "account raggiunti · 7 giorni"], ["INTERAZIONI", "4,1K", "like, commenti, salvataggi"], ["ORARIO MIGLIORE", "LUN 12", "quando i suoi follower sono online"]]',
              '(SOC.vero?.report?.numeri || [["FOLLOWER", "12,4K", "+184 in 7 giorni"], ["COPERTURA", "38,2K", "account raggiunti · 7 giorni"], ["INTERAZIONI", "4,1K", "like, commenti, salvataggi"], ["ORARIO MIGLIORE", "LUN 12", "quando i suoi follower sono online"]])')
    s = toppa(s, '<div class="sc-cal"><div class="sc-cal-d"><b>REEL</b></div><div><b>Giacca custom · stencil KR</b><small>14,8K visualizzazioni · 1,2K like · 86 commenti</small></div></div>',
              '${SOC.vero?.report ? (SOC.vero.report.top ? `<div class="sc-cal"><div class="sc-cal-d"><b>${SOC.vero.report.top.tipo}</b></div><div><b>${escSd(SOC.vero.report.top.titolo)}</b><small>${SOC.vero.report.top.dettaglio}</small></div></div>` : `<p class="sc-nota">Ancora niente da mostrare.</p>`) : `<div class="sc-cal"><div class="sc-cal-d"><b>REEL</b></div><div><b>Giacca custom · stencil KR</b><small>14,8K visualizzazioni · 1,2K like · 86 commenti</small></div></div>`}')
    s = toppa(s, "<p class=\"sc-nota\">Numeri d'esempio. Nell'app arrivano dalle statistiche ufficiali di Instagram.</p>",
              "<p class=\"sc-nota\">${SOC.vero?.report ? \"Dalle statistiche ufficiali di Instagram.\" : \"Numeri d'esempio. Nell'app arrivano dalle statistiche ufficiali di Instagram.\"}</p>")
    s = toppa(s, 'v = [3.1, 4.4, 3.8, 9.6, 5.2, 6.9, 5.2], mx = 10,', 'v = SOC.vero?.report?.giorni?.length ? SOC.vero.report.giorni : [3.1, 4.4, 3.8, 9.6, 5.2, 6.9, 5.2], mx = Math.max(1, ...v) * 1.08,')
    s = toppa(s, 'x.fillText(["L", "M", "M", "G", "V", "S", "D"][i], X + w * .2, c.height - 4);',
              'x.fillText((SOC.vero?.report?.etichette || ["L", "M", "M", "G", "V", "S", "D"])[i] || "", X + w * .2, c.height - 4);')
    s = toppa(s, 'v.forEach((n, i) => { const w = c.width / 7,', 'v.forEach((n, i) => { const w = c.width / v.length,')
    s = toppa(s, 'if (b.dataset.az === "riassunto") { suona("aTick"); parlaMock("Settimana buona, Sir:',
              'if (b.dataset.az === "riassunto" && SOC.vero?.report) { suona("aTick"); parlaMock(SOC.vero.report.riassunto, 6000); return; }\n'
              '    if (b.dataset.az === "riassunto" && window.JARVIS_APP) { suona("aTick"); if (SOC.vero?.errore) parlaMock("Instagram non risponde, Sir: " + SOC.vero.errore, 3600); else { window.__socRiassunto = true; parlaMock("Leggo le statistiche, Sir: un attimo.", 2000); } return; }\n'
              '    if (b.dataset.az === "riassunto") { suona("aTick"); parlaMock("Settimana buona, Sir:')
    s = toppa(s, 'if (b.dataset.invia) { const i = +b.dataset.invia, m = SOC.posta[i]; m.bozza = A.querySelector(`[data-bozza="${i}"]`)?.value || m.bozza; if (!m.bozza.trim()) { parlaMock("La risposta è vuota, Sir.", 1800); return; } suona("aPronto");',
              'if (b.dataset.invia && window.JARVIS_APP) { const i = +b.dataset.invia, m = SOC.posta[i]; m.bozza = A.querySelector(`[data-bozza="${i}"]`)?.value || m.bozza; if (!m.bozza.trim()) { parlaMock("La risposta è vuota, Sir.", 1800); return; } b.textContent = "…";\n'
              '      const r = await window.__jarvisChiedi("socialRispondi", { tipoMsg: m.tipo, idMsg: m.id, a: m.a || "", testo: m.bozza }).then((t) => JSON.parse(t)).catch((e) => ({ errore: e.message || String(e) }));\n'
              '      if (r.errore) { b.textContent = "INVIA"; parlaMock("Non è partita, Sir: " + r.errore, 3600); return; } suona("aPronto"); m.fatto = true; parlaMock(`Risposta mandata a @${m.chi}, Sir.`, 2000); pagina(); return; }\n'
              '    if (b.dataset.invia) { const i = +b.dataset.invia, m = SOC.posta[i]; m.bozza = A.querySelector(`[data-bozza="${i}"]`)?.value || m.bozza; if (!m.bozza.trim()) { parlaMock("La risposta è vuota, Sir.", 1800); return; } suona("aPronto");')
    s = toppa(s, 'if (b.dataset.annulla) { suona("aTick"); SOC.coda.splice(+b.dataset.annulla, 1);',
              'if (b.dataset.annulla && window.JARVIS_APP) { suona("aTick"); const c = SOC.coda[+b.dataset.annulla]; if (c?.id) window.__jarvisChiedi("socialAnnulla", { idCoda: c.id }).catch(() => {}); SOC.coda.splice(+b.dataset.annulla, 1); parlaMock("Tolto dal calendario, Sir.", 1800); pagina(); return; }\n'
              '    if (b.dataset.annulla) { suona("aTick"); SOC.coda.splice(+b.dataset.annulla, 1);')
    s = toppa(s, 'if (b.dataset.az === "auto") { suona("aTick"); SOC.auto.on = !SOC.auto.on;',
              'if (b.dataset.az === "auto") { suona("aTick"); SOC.auto.on = !SOC.auto.on; if (window.JARVIS_APP) window.__socAuto();')
    s = toppa(s, 'P.querySelector("#scParola").addEventListener("input", (e) => { a.parola = e.target.value.toUpperCase(); e.target.value = a.parola; }); P.querySelector("#scAutoT").addEventListener("input", (e) => { a.testo = e.target.value; }); }',
              'P.querySelector("#scParola").addEventListener("input", (e) => { a.parola = e.target.value.toUpperCase(); e.target.value = a.parola; window.JARVIS_APP && window.__socAuto(); }); P.querySelector("#scAutoT").addEventListener("input", (e) => { a.testo = e.target.value; window.JARVIS_APP && window.__socAuto(); }); }')
    vecchio = '        const titolo = (didascalia || "Nuovo contenuto").split(/[.!\\n]/)[0].slice(0, 40);'
    s = toppa(s, vecchio, vecchio + '''
        if (window.JARVIS_APP) { const L = document.createElement("div"); L.className = "sc-carica"; L.innerHTML = `<i></i><b>PREPARO IL ${formato}</b><span></span>`; A.appendChild(L);
          const media = await window.__socMedia(fonte, formato); L.querySelector("b").textContent = quando === "ORA" ? "CARICO SU INSTAGRAM" : "PROGRAMMO";
          const r = await window.__jarvisChiedi("socialPubblica", { formato: media.formato, quando, didascalia, media: media.b64, mime: media.mime }).then((t) => JSON.parse(t)).catch((e) => ({ errore: e.message || String(e) }));
          L.remove(); if (!ok()) return;
          if (r.errore) { parlaMock("Non è andata, Sir: " + r.errore, 4200); return; }
          suona("aPronto"); parlaMock(r.programmato ? `Programmato per ${r.programmato}, Sir: è l'orario migliore.` : (media.nota || "Pubblicato su @kingrusto, Sir."), 3200); fonte = null; didascalia = "";
          window.webkit.messageHandlers.jarvis.postMessage({ tipo: "socialStato" }); return; }''')
    # nell'app niente dati d'esempio: posta, calendario e automazione arrivano dal cervello (window.__socStato, chiamata dall'app)
    s = toppa(s, 'CONTENUTI.Social = `<div id="social"></div>`;',
              'if (window.JARVIS_APP) { SOC.posta = []; SOC.coda = []; SOC.pubblicati = []; SOC.auto = { on: false, parola: "LISTA", testo: "" }; }\n'
              'window.__socStato = (r) => { if (!r || r.errore) { SOC.vero = { errore: (r && r.errore) || "non risponde" }; } else { SOC.vero = r; SOC.posta = r.posta || []; SOC.coda = r.coda || []; SOC.pubblicati = r.pubblicati || []; if (r.auto) SOC.auto = r.auto; } window.__socRidisegna && window.__socRidisegna(); if (window.__socRiassunto) { window.__socRiassunto = false; if (SOC.vero.report) parlaMock(SOC.vero.report.riassunto, 6000); else parlaMock("Instagram non risponde, Sir: " + SOC.vero.errore, 3600); } };\n'
              'CONTENUTI.Social = `<div id="social"></div>`;')
    # il pezzo dello Studio per Instagram: nell'app si tiene anche l'immagine grande del banco (la miniatura da 160 px faceva un Reel sgranato)
    s = toppa(s, 'if (conMini) miniatura((m) => { if (m && progAtt() === p) { p.mini = m;',
              'if (conMini) miniatura((m) => { if (m && progAtt() === p) { p.mini = m; if (window.JARVIS_APP) try { p.grande = B.istantanea(true); } catch {}')
    s = toppa(s, 'return p ? { mini: p.mini, nome: p.nome || "Progetto" } : null; }',
              'return p ? { mini: (window.JARVIS_APP && p.grande) || p.mini, nome: p.nome || "Progetto" } : null; }')
    # POSTA vuota nell'app: si dice (prima restava uno spazio bianco); mentre carica, «Carico…»
    s = toppa(s, 'P.innerHTML = `<div class="sc-lista">${SOC.posta.map((m, i) =>',
              'P.innerHTML = `${window.JARVIS_APP && !SOC.posta.length ? `<p class="sc-nota">${SOC.vero ? (SOC.vero.errore ? "Instagram non risponde: " + escSd(SOC.vero.errore) + "." : "Nessun commento o messaggio da rispondere.") : "Carico commenti e messaggi…"}</p>` : ""}<div class="sc-lista">${SOC.posta.map((m, i) =>')
    # REPORT nell'app senza dati (sta caricando o Instagram non risponde): niente numeri d'esempio, i trattini
    ESEMPIO = '[["FOLLOWER", "12,4K", "+184 in 7 giorni"], ["COPERTURA", "38,2K", "account raggiunti · 7 giorni"], ["INTERAZIONI", "4,1K", "like, commenti, salvataggi"], ["ORARIO MIGLIORE", "LUN 12", "quando i suoi follower sono online"]]'
    s = toppa(s, '(SOC.vero?.report?.numeri || ' + ESEMPIO + ')',
              '(SOC.vero?.report?.numeri || (window.JARVIS_APP ? [["FOLLOWER", "—", SOC.vero?.errore ? "Instagram non risponde" : "carico…"], ["COPERTURA", "—", "account raggiunti · 7 giorni"], ["INTERAZIONI", "—", "like, commenti, salvataggi"], ["POST", "—", "pubblicati in tutto"]] : ' + ESEMPIO + '))')
    s = toppa(s, 'v = SOC.vero?.report?.giorni?.length ? SOC.vero.report.giorni : [3.1,',
              'v = SOC.vero?.report?.giorni?.length ? SOC.vero.report.giorni : window.JARVIS_APP ? [] : [3.1,')
    s = toppa(s, '${SOC.vero?.report ? (SOC.vero.report.top ?', '${SOC.vero?.report || window.JARVIS_APP ? (SOC.vero?.report?.top ?')
    s = toppa(s, '"Dalle statistiche ufficiali di Instagram." : "Numeri d\'esempio. Nell\'app arrivano dalle statistiche ufficiali di Instagram."',
              '"Dalle statistiche ufficiali di Instagram." : window.JARVIS_APP ? (SOC.vero?.errore ? "Instagram non risponde: " + escSd(SOC.vero.errore) + "." : "Carico le statistiche di Instagram…") : "Numeri d\'esempio. Nell\'app arrivano dalle statistiche ufficiali di Instagram."')
    return s
