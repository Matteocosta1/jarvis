# ── LiDAR → STUDIO nell'app: la scansione vera dell'iPhone al posto dei dati d'esempio (incluse da studio_app.py) ──
# L'app manda window.STUDIO_DA = { lidarVero: {...} } (LidarStudio.swift):
#   · tipo "stanza" / "setup": la sala vera (poligono, porte e finestre sulle pareti, altezza) e l'allestimento calcolato → plastico()
#   · tipo "maglia": terreno (già solido), oggetto o persona (Object Capture), in millimetri e in scala → un pezzo «unito» sul banco
#   · tipo "corpo": le giunture vere della postura → la sagoma con quelle proporzioni → ologramma (come la sagoma del mockup)
# Nel mockup (senza JARVIS_APP) non arriva mai lidarVero: tutto resta com'era.

def toppe_lidar(s, toppa):
    s = toppa(s, '  function plastico(k) {\n    const S = SALA, sc = 10, sp = 3, H = S.h * sc, pz = [];',
              '  function plastico(k, vero) {\n    const S = vero?.sala || SALA, sc = vero?.sc || 10, sp = 3, H = S.h * sc, pz = [];')
    s = toppa(s, 'pz.push({ forma: "scatola", misure: { l: d.l * sc, p: sp * 3, h: 21 }, pos: [ax + ux * t + nx, 2 + 10.5, az + uz * t + nz], rot: [0, ang, 0], foro: true }); });',
              'const hh = ((d.alto ?? 2.1) - (d.basso ?? 0)) * sc, yb = (d.basso ?? 0) * sc; pz.push({ forma: "scatola", misure: { l: d.l * sc, p: sp * 3, h: hh }, pos: [ax + ux * t + nx, 2 + yb + hh / 2, az + uz * t + nz], rot: [0, ang, 0], foro: true }); });')
    s = toppa(s, 'pz.push({ forma: "scatola", misure: { l: d.l * sc, p: sp * 3, h: 12 }, pos: [ax + ux * t + nx, 2 + 9 + 6, az + uz * t + nz], rot: [0, ang, 0], foro: true }); }); }); };',
              'const hh = ((d.alto ?? 2.1) - (d.basso ?? 0.9)) * sc, yb = (d.basso ?? 0.9) * sc; pz.push({ forma: "scatola", misure: { l: d.l * sc, p: sp * 3, h: hh }, pos: [ax + ux * t + nx, 2 + yb + hh / 2, az + uz * t + nz], rot: [0, ang, 0], foro: true }); }); }); };')
    s = toppa(s, '    if (k === "stanza") { sala(); nome = "Plastico sala 1:100";',
              '''    if (vero) { sala(); nome = vero.nome; righe = vero.righe;
      const R2 = (r, h, y0 = 2) => { const [x, z] = P(r.c[0], r.c[1]); return { forma: "scatola", misure: { l: r.l * sc, p: r.p * sc, h }, pos: [x, y0 + h / 2, z], rot: [0, -Math.atan2(r.u[1], r.u[0]) * 180 / Math.PI, 0] }; };
      (vero.posati || []).forEach((r) => pz.push(R2(r, r.h * sc)));
      (vero.stand || []).forEach((r) => { pz.push(R2(r, 1)); const n = [-r.u[1], r.u[0]], v = r.verso ?? -1, o = r.p / 2 - .075; pz.push(R2({ c: [r.c[0] + n[0] * v * o, r.c[1] + n[1] * v * o], u: r.u, l: r.l, p: .15 }, 2.5 * sc)); }); }
    else if (k === "stanza") { sala(); nome = "Plastico sala 1:100";''')
    s = toppa(s, 'parlaMock(`Ecco il plastico, Sir: ${mm(g.l)} per ${mm(g.p)} millimetri. ${k === "esterno" ? "Scala 1 a 50." : "Scala 1 a 100: pareti, porte e finestre sono quelle scansionate."}`, 3600);',
              'parlaMock(`Ecco il plastico, Sir: ${mm(g.l)} per ${mm(g.p)} millimetri. ${vero ? `Scala ${vero.scala.replace(":", " a ")}: pareti, porte e finestre sono quelle scansionate.` : k === "esterno" ? "Scala 1 a 50." : "Scala 1 a 100: pareti, porte e finestre sono quelle scansionate."}`, 3600);')
    # la scansione vera arriva sul banco
    s = toppa(s, '    else if (window.STUDIO_DA?.lidar) {',
              '    else if (window.STUDIO_DA?.lidarVero) { const d = window.STUDIO_DA.lidarVero; window.STUDIO_DA = null; await attesa(700); lidarVero(d); }\n    else if (window.STUDIO_DA?.lidar) {')
    s = toppa(s, '  // ── PLASTICI dal LiDAR: la sala (pareti, porte, finestre), il terreno, l\'allestimento, in scala per la stampa ──',
              '''  // APP · la scansione vera del LiDAR dell'iPhone (LidarStudio.swift): sala e allestimento → plastico; terreno, oggetto, persona → maglia; postura → sagoma
  function lidarVero(d) {
    if (!B || !d) return;
    if (d.tipo === "stanza" || d.tipo === "setup") { plastico(d.tipo, d); return; }
    if (d.tipo === "maglia") { const f = (x) => new Float32Array(Uint8Array.from(atob(x), (c) => c.charCodeAt(0)).buffer);
      const kk = "l" + Date.now().toString(36); GEO_DATI.set(kk, { pos: f(d.pos), norm: f(d.norm) });
      const o = nuovo("unito", { k: kk }, nomeLibero(d.nome), { anim: "vacuform" }), g = B.ingombro(o), ch = B.chiuso(o);
      info([...d.righe, `${mm(g.l)} × ${mm(g.p)} × ${mm(g.h)} MM · ${ch ? "STAMPABILE" : "DA CONTROLLARE"}`]);
      parlaMock(d.parla.replace("{L}", mm(g.l)).replace("{P}", mm(g.p)).replace("{H}", mm(g.h)) + (ch ? "" : " La scansione ha dei buchi: prima di stampare va controllata."), 4200); return; }
    if (d.tipo === "corpo") leggiFoto(sagomaVera(d), "corpo dal LiDAR", "oggetto");
  }
  window.__lidarVero = (d) => vivo() && lidarVero(d);
  // la sagoma con le giunture vere (vista di fronte): come sagomaStatua, ma con le proporzioni e la posa della scansione
  function sagomaVera(d) {
    const c = document.createElement("canvas"); c.width = 300; c.height = 600; const x = c.getContext("2d"); x.fillStyle = "#101418"; x.fillRect(0, 0, 300, 600);
    const J = d.giunture || {}, ks = Object.keys(J); if (!ks.length) return sagomaStatua();
    const xs = ks.map((k) => J[k][0]), xc = (Math.min(...xs) + Math.max(...xs)) / 2, s = 540 / Math.max(1, d.altezza || 1.78), Q = (k) => J[k] && [150 + (J[k][0] - xc) * s, 580 - J[k][1] * s];
    const g = x.createLinearGradient(60, 0, 240, 0); g.addColorStop(0, "#8d969b"); g.addColorStop(.5, "#e9eef0"); g.addColorStop(1, "#7d868b"); x.fillStyle = g; x.strokeStyle = g; x.lineCap = "round"; x.lineJoin = "round";
    const busto = ["spSx", "spDx", "anDx", "anSx"].map(Q); if (busto.every(Boolean)) { x.beginPath(); busto.forEach(([a, b], i) => (i ? x.lineTo(a, b) : x.moveTo(a, b))); x.closePath(); x.lineWidth = .12 * s; x.stroke(); x.fill(); }
    const spessore = { collo: .1, spSx: .09, spDx: .09, goSx: .07, goDx: .07, bac: .2, anSx: .15, anDx: .15, giSx: .11, giDx: .11 };
    (d.ossa || []).forEach(([a, b]) => { const p = Q(a), q = Q(b); if (!p || !q) return; x.lineWidth = (spessore[a] ?? .08) * s; x.beginPath(); x.moveTo(...p); x.lineTo(...q); x.stroke(); });
    const t = Q("testa"); if (t) { x.beginPath(); x.ellipse(t[0], t[1] - .02 * s, .1 * s, .125 * s, 0, 0, Math.PI * 2); x.fill(); }
    return c;
  }
  // ── PLASTICI dal LiDAR: la sala (pareti, porte, finestre), il terreno, l'allestimento, in scala per la stampa ──''')
    # «fai il plastico della stanza» detto nello Studio dell'app: la sala la dà l'app (l'ultima scansione salvata), non quella d'esempio
    s = toppa(s, '{ plastico(/giardin|terren|estern/.test(t) ? "esterno" : /evento|allestiment|palco|setup/.test(t) ? "setup" : "stanza"); return ""; }',
              '{ const kp = /giardin|terren|estern/.test(t) ? "esterno" : /evento|allestiment|palco|setup/.test(t) ? "setup" : "stanza"; if (window.JARVIS_APP) window.webkit.messageHandlers.jarvis.postMessage({ tipo: "plastico", k: kp }); else plastico(kp); return ""; }')
    # i tasti LIDAR e OCCHI dello Studio (e «scansiona…» a voce): nell'app aprono il LiDAR e gli Occhi veri (lo Studio si chiude;
    # il tasto STUDIO di LiDAR e degli Occhi riporta sul banco la scansione e la foto vere). Nel mockup restano le prove d'esempio.
    s = toppa(s, '  async function scansioneLidar(forma = "tazza") {',
              '  async function scansioneLidar(forma = "tazza") {\n    if (window.JARVIS_APP) { window.webkit.messageHandlers.jarvis.postMessage({ tipo: "vaiA", dove: "lidar" }); return; }')
    s = toppa(s, '  async function daOcchi() {',
              '  async function daOcchi() { if (window.JARVIS_APP) { window.webkit.messageHandlers.jarvis.postMessage({ tipo: "vaiA", dove: "occhi" }); return; }')
    # altri resti del mockup nello Studio dell'app (controllo del 26 ott):
    #  · «trasforma questa foto in 3D», «fotografa il disegno» a voce: la fotocamera vera, non il mirino con le PROVE d'esempio
    s = toppa(s, '  function fotocamera() {', '  function fotocamera() {\n    if (window.JARVIS_APP) { window.webkit.messageHandlers.jarvis.postMessage({ tipo: "foto" }); return; }')
    #  · «scansiona questa tazza» a voce: il LiDAR vero anche se la frase nomina un oggetto (nel mockup creava una tazza)
    s = toppa(s, '    if (!creare && /scansion|lidar/.test(t)) { scansioneLidar(); return null; }',
              '    if ((!creare || (window.JARVIS_APP && /^(scansiona|scansione|lidar)\\b/.test(t))) && /scansion|lidar/.test(t)) { scansioneLidar(); return null; }')
    #  · CREA libero: se il cervello non risponde, niente «ricetta di prova del mockup»
    s = toppa(s, '    if (!ric?.pezzi?.length) { const k = Object.keys(SD_RICETTE)', '    if (!ric?.pezzi?.length && !window.JARVIS_APP) { const k = Object.keys(SD_RICETTE)')
    #  · STAMPA/CONDIVIDI non riuscito: nell'app non si dice «nell'app va in File»
    s = toppa(s, ': "Qui il salvataggio non è disponibile: nell\'app va in File.";',
              ': window.JARVIS_APP ? "Il salvataggio non è riuscito, Sir: riprovi." : "Qui il salvataggio non è disponibile: nell\'app va in File.";')
    #  · SALVA STL nell'app: niente zip (l'STL va al foglio di condivisione così com'è), la frase lo dice giusto
    s = toppa(s, 'notifica(esitoSalva(r, `Salvato ${o.nome}.stl (${mm(g.l)} × ${mm(g.p)} × ${mm(g.h)} mm), dentro uno zip`)',
              'notifica(esitoSalva(r, `Salvato ${o.nome}.stl (${mm(g.l)} × ${mm(g.p)} × ${mm(g.h)} mm)${window.JARVIS_APP ? "" : ", dentro uno zip"}`)')
    #  · CONDIVIDI › Copia nell'app: copia davvero l'immagine del banco negli appunti dell'iPhone
    s = toppa(s, 'else notifica("Copiato, Sir.", { titolo: "Studio" }); }));',
              'else { if (window.JARVIS_APP) window.webkit.messageHandlers.jarvis.postMessage({ tipo: "copia", b64: B.istantanea(true).split(",")[1] }); notifica("Copiato, Sir.", { titolo: "Studio" }); } }));')
    #  · CONDIVIDI › le app (AirDrop, Messaggi, Mail, WhatsApp, Telegram): nell'app il file vero del formato scelto (immagine, video 360°
    #    montato dall'iPhone, modello AR USDZ, STL) e il foglio di condivisione di iOS, dove si tocca l'app. Nel mockup resta la prova.
    s = toppa(s, '  // ── CONDIVIDI: il foglio di iOS.',
              '''  // APP · CONDIVIDI vero: il file del formato scelto, poi il foglio di condivisione di iOS
  async function condividiVero(o, fmt) {
    const nome = o.nome.replace(/[^\\w-]+/g, "_"), chiedi = window.__jarvisChiedi;
    if (fmt === "img") return scarica(B.istantanea(true), `${nome}.jpg`);
    if (fmt === "3d") return scarica(B.stl(o, B.stampaInfo(o).m), `${nome}.stl`);
    if (fmt === "ar") return chiedi("modelloAR", { nome, stl: B.stl(o) }).then(() => "ok").catch((e) => e?.code || "errore");
    const fot = []; for (let k = 0; k < 72; k++) { fot.push(B.fotogramma360(k / 72 * Math.PI * 2).split(",")[1]); if (k % 6 === 5) await attesa(0); }
    return chiedi("video360", { nome, fotogrammi: fot }).then(() => "ok").catch((e) => e?.code || "errore");
  }
  // ── CONDIVIDI: il foglio di iOS.''')
    s = toppa(s, '      if (!(await prepara())) return; suona("aPronto"); notifica(`${{ img: "Immagine", video: "Video a 360°", ar: "Modello AR", "3d": "File per la stampa" }[fmt]} di «${o.nome}» inviato con ${b.dataset.app}.`, { titolo: "Studio" }); F.querySelector("[data-chiudi]").click(); }));',
              '      if (window.JARVIS_APP) { const bar = F.querySelector(".sd-barra"); if (bar && fmt === "video") bar.hidden = false; const r = await condividiVero(o, fmt); if (bar) bar.hidden = true; if (r === "ok") suona("aPronto");'
              ' notifica(esitoSalva(r, `${{ img: "Immagine", video: "Video a 360°", ar: "Modello AR", "3d": "File per la stampa" }[fmt]} di «${o.nome}» pronto`), { titolo: "Studio" }); if (F.isConnected) F.querySelector("[data-chiudi]").click(); return; }\n'
              '      if (!(await prepara())) return; suona("aPronto"); notifica(`${{ img: "Immagine", video: "Video a 360°", ar: "Modello AR", "3d": "File per la stampa" }[fmt]} di «${o.nome}» inviato con ${b.dataset.app}.`, { titolo: "Studio" }); F.querySelector("[data-chiudi]").click(); }));')
    # il fotogramma del giro: la camera a un angolo preciso attorno al pezzo, poi l'immagine (per il VIDEO 360° vero)
    s = toppa(s, '    giro360() { giroT = performance.now(); },',
              '    giro360() { giroT = performance.now(); },\n    fotogramma360(a) { const R = raggio, t = teta + a; cam.position.set(bersaglio.x + R * Math.sin(fi) * Math.sin(t), bersaglio.y + R * Math.cos(fi), bersaglio.z + R * Math.sin(fi) * Math.cos(t)); cam.lookAt(bersaglio); ren.render(scena, cam); return ren.domElement.toDataURL("image/jpeg", .82); },')
    #  · Salva in Foto / Salva su File col formato VIDEO 360° o MODELLO AR: il file vero di quel formato (prima salvava una foto)
    s = toppa(s, 'if (b.dataset.az === "foto") { const r = await scarica(B.istantanea(true), `${o.nome}.jpg`);',
              'if (b.dataset.az === "foto") { const r = window.JARVIS_APP && fmt === "video" ? await condividiVero(o, "video") : await scarica(B.istantanea(true), `${o.nome}.jpg`);')
    s = toppa(s, 'else if (b.dataset.az === "file") { const r = fmt === "3d"',
              'else if (b.dataset.az === "file") { const r = window.JARVIS_APP && (fmt === "video" || fmt === "ar") ? await condividiVero(o, fmt) : fmt === "3d"')
    #  · SERVICE nell'app: Vectorealism (Milano; scelto dal signore il 26 ott). Non ha un'API: l'STL va su File (zip sopra i 9 MB:
    #    il loro limite è 10 MB) e si apre la loro pagina di stampa 3D, dove lo si carica, si sceglie materiale e colore e si fa il preventivo.
    s = toppa(s, 'F.querySelector(\'[data-st="servizio"]\')?.addEventListener("click", () => { suona("aPronto"); notifica(`Mandato al servizio di stampa [da scegliere] in 3MF',
              'F.querySelector(\'[data-st="servizio"]\')?.addEventListener("click", async () => { if (window.JARVIS_APP) { suona("aTick"); '
              'parlaMock("Salvo il file e apro Vectorealism, Sir: lo carichi lì, scelga materiale e colore e tocchi Calcola il preventivo.", 4200); '
              'let st = B.stl(o, pi.m), nm = `${o.nome.replace(/[^\\w-]+/g, "_")}.stl`; if (st.length > 9e6) { st = zipUno(nm, new TextEncoder().encode(st)); nm = nm.replace(/\\.stl$/i, ".zip"); } '
              'const r = await scarica(st, nm); if (r === "ok") window.webkit.messageHandlers.jarvis.postMessage({ tipo: "apriURL", url: "https://www.vectorealism.com/it/stampa-3d/" }); '
              'else notifica(esitoSalva(r, ""), { titolo: "Studio" }); return; } suona("aPronto"); notifica(`Mandato al servizio di stampa [da scegliere] in 3MF')
    return s
