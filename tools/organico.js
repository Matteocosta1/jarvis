// ── CREA ORGANICO (26 ott sera): i pezzi del cervello non si incollano più come geometria, si FONDONO in una superficie unica e
// morbida (campi di distanza con unione dolce + surface nets): un gatto sembra scolpito, non fatto di sfere. Chiuso e stampabile.
const ORG = (() => {
  const rad = Math.PI / 180, L2 = (x, y) => Math.sqrt(x * x + y * y), L3 = (x, y, z) => Math.sqrt(x * x + y * y + z * z);
  const cl = (v, d) => Math.max(.6, Math.min(250, Number.isFinite(+v) ? +v : d));
  function prepara(q) {
    const m = q.misure || {}, L = cl(m.l ?? m.d, 20), P = cl(m.p ?? m.d ?? m.l, 20), H = cl(m.h ?? m.d, 20), D = cl(m.d ?? Math.max(m.l || 0, m.p || 0), 20);
    const r = q.rot || [0, 0, 0], ax = (+r[0] || 0) * rad, ay = (+r[1] || 0) * rad, az = (+r[2] || 0) * rad, c = q.pos || [0, 0, 0];
    // mondo = Rz·Ry·Rx·locale + c  →  locale = Rxᵀ·Ryᵀ·Rzᵀ·(p − c)
    const cx = Math.cos(ax), sx = Math.sin(ax), cy = Math.cos(ay), sy = Math.sin(ay), cz = Math.cos(az), sz = Math.sin(az);
    const f = { forma: q.forma, foro: !!q.foro, c: [+c[0] || 0, +c[1] || 0, +c[2] || 0], L, P, H, D, d2: cl(m.d2, 0), s: cl(m.s, 6) };
    f.loc = (x, y, z) => { x -= f.c[0]; y -= f.c[1]; z -= f.c[2];
      let t = cz * x + sz * y; y = -sz * x + cz * y; x = t;          // Rzᵀ
      t = cy * x - sy * z; z = sy * x + cy * z; x = t;               // Ryᵀ
      t = cx * y + sx * z; z = -sx * y + cx * z; y = t;              // Rxᵀ
      return [x, y, z]; };
    const R = { sfera: L3(D, H, D) / 2, scatola: L3(L, H, P) / 2, cilindro: L2(D, H) / 2, cono: L2(D, H) / 2, piramide: L2(D, H) / 2,
      toro: D / 2 + f.s, cuneo: L3(L, H, P) / 2 }[q.forma] ?? 20;
    f.raggio = R;
    f.sdf = (x, y, z) => { const [a, b, g] = f.loc(x, y, z);
      switch (f.forma) {
        case "sfera": { const rx = D / 2, ry = H / 2, rz = D / 2, k0 = L3(a / rx, b / ry, g / rz), k1 = L3(a / rx / rx, b / ry / ry, g / rz / rz); return k1 > 1e-9 ? k0 * (k0 - 1) / k1 : -Math.min(rx, ry); }
        case "scatola": { const qx = Math.abs(a) - L / 2, qy = Math.abs(b) - H / 2, qz = Math.abs(g) - P / 2; return L3(Math.max(qx, 0), Math.max(qy, 0), Math.max(qz, 0)) + Math.min(Math.max(qx, qy, qz), 0); }
        case "cilindro": { const dx = L2(a, g) - D / 2, dy = Math.abs(b) - H / 2; return Math.min(Math.max(dx, dy), 0) + L2(Math.max(dx, 0), Math.max(dy, 0)); }
        case "cono": case "piramide": { const r1 = D / 2, r2 = f.forma === "cono" ? f.d2 / 2 : 0, h = H / 2, qx = L2(a, g), qy = b;   // cono tronco (Inigo Quilez)
          const k1x = r2, k1y = h, k2x = r2 - r1, k2y = 2 * h, cax = qx - Math.min(qx, qy < 0 ? r1 : r2), cay = Math.abs(qy) - h;
          const kk = k2x * k2x + k2y * k2y, tt = Math.max(0, Math.min(1, ((k1x - qx) * k2x + (k1y - qy) * k2y) / kk)), cbx = qx - k1x + k2x * tt, cby = qy - k1y + k2y * tt;
          const sg = cbx < 0 && cay < 0 ? -1 : 1; return sg * Math.sqrt(Math.min(cax * cax + cay * cay, cbx * cbx + cby * cby)); }
        case "toro": { const Rm = Math.max(f.s, D / 2 - f.s / 2); return L2(L2(a, g) - Rm, b) - f.s / 2; }
        case "cuneo": { const y0 = b + H / 2, n = L2(H, L / 2), s1 = (H * Math.abs(a) + (L / 2) * y0 - H * L / 2) / n, tri = Math.max(-y0, s1), wz = Math.abs(g) - P / 2;
          return Math.min(Math.max(tri, wz), 0) + L2(Math.max(tri, 0), Math.max(wz, 0)); }
        default: return 1e9;
      } };
    return f;
  }
  const smin = (a, b, k) => { const h = Math.max(k - Math.abs(a - b), 0) / k; return Math.min(a, b) - h * h * k * .25; };
  const smax = (a, b, k) => -smin(-a, -b, k);
  return function (pezzi, stile) {
    const F = pezzi.slice(0, 28).map(prepara), pieni = F.filter((f) => !f.foro), buchi = F.filter((f) => f.foro);
    if (!pieni.length) return null;
    // dimensione dell'oggetto e unione dolce in proporzione (organico) o quasi spigolosa (meccanico)
    let mn = [1e9, 1e9, 1e9], mx = [-1e9, -1e9, -1e9];
    for (const f of pieni) for (let i = 0; i < 3; i++) { mn[i] = Math.min(mn[i], f.c[i] - f.raggio); mx[i] = Math.max(mx[i], f.c[i] + f.raggio); }
    const dim = Math.max(mx[0] - mn[0], mx[1] - mn[1], mx[2] - mn[2]);
    const K = stile === "m" ? Math.max(.6, dim * .008) : Math.max(1.5, dim * .045), KF = K * .5;
    const campo = (x, y, z) => { let d = 1e9;
      for (const f of pieni) { const lb = L3(x - f.c[0], y - f.c[1], z - f.c[2]) - f.raggio; if (lb > d + K) continue; d = d > 1e8 ? f.sdf(x, y, z) : smin(d, f.sdf(x, y, z), K); }
      for (const f of buchi) { const lb = L3(x - f.c[0], y - f.c[1], z - f.c[2]) - f.raggio; if (lb > KF - d) continue; d = smax(d, -f.sdf(x, y, z), KF); }
      return Math.max(d, -y);                                              // niente sotto il piano di stampa
    };
    // la griglia: circa 110 celle sul lato lungo (passo minimo 0,5 mm)
    const h = Math.max(.5, dim / 110), M = 2 * h + K;
    const o = [mn[0] - M, Math.max(mn[1] - M, -h), mn[2] - M], n = [0, 1, 2].map((i) => Math.ceil((mx[i] + M - o[i]) / h) + 1);
    const nx = n[0], ny = n[1], nz = n[2], V = new Float32Array(nx * ny * nz), id = (i, j, k) => (k * ny + j) * nx + i;
    for (let k = 0; k < nz; k++) for (let j = 0; j < ny; j++) for (let i = 0; i < nx; i++) V[id(i, j, k)] = campo(o[0] + i * h, o[1] + j * h, o[2] + k * h);
    // surface nets: un vertice per ogni cella attraversata dalla superficie, un quadrato per ogni spigolo che la attraversa
    const cella = new Int32Array((nx - 1) * (ny - 1) * (nz - 1)).fill(-1), cid = (i, j, k) => (k * (ny - 1) + j) * (nx - 1) + i;
    const vp = [], vn = [], SP = [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]];
    const g = new Float32Array(8);
    for (let k = 0; k < nz - 1; k++) for (let j = 0; j < ny - 1; j++) for (let i = 0; i < nx - 1; i++) {
      let neg = 0; for (let c = 0; c < 8; c++) { g[c] = V[id(i + (c & 1), j + ((c >> 1) & 1), k + ((c >> 2) & 1))]; if (g[c] < 0) neg++; }
      if (neg === 0 || neg === 8) continue;
      let sx = 0, sy = 0, sz = 0, nn = 0;
      for (const [a, b] of SP) { const A = g[a], B = g[b]; if ((A < 0) === (B < 0)) continue; const t = A / (A - B);
        sx += (a & 1) + t * ((b & 1) - (a & 1)); sy += ((a >> 1) & 1) + t * (((b >> 1) & 1) - ((a >> 1) & 1)); sz += ((a >> 2) & 1) + t * (((b >> 2) & 1) - ((a >> 2) & 1)); nn++; }
      const x = o[0] + (i + sx / nn) * h, y = o[1] + (j + sy / nn) * h, z = o[2] + (k + sz / nn) * h;
      const e = h * .5, gx = campo(x + e, y, z) - campo(x - e, y, z), gy = campo(x, y + e, z) - campo(x, y - e, z), gz = campo(x, y, z + e) - campo(x, y, z - e), gl = L3(gx, gy, gz) || 1;
      cella[cid(i, j, k)] = vp.length / 3; vp.push(x, y, z); vn.push(gx / gl, gy / gl, gz / gl);
    }
    const tri = [], nor = [], put = (a) => { tri.push(vp[a * 3], vp[a * 3 + 1], vp[a * 3 + 2]); nor.push(vn[a * 3], vn[a * 3 + 1], vn[a * 3 + 2]); };
    const quad = (a, b, c, d, giro) => { if (a < 0 || b < 0 || c < 0 || d < 0) return; if (giro) { put(a); put(b); put(c); put(a); put(c); put(d); } else { put(a); put(c); put(b); put(a); put(d); put(c); } };
    for (let k = 1; k < nz - 1; k++) for (let j = 1; j < ny - 1; j++) for (let i = 0; i < nx - 1; i++) {   // spigoli lungo x
      const A = V[id(i, j, k)], B = V[id(i + 1, j, k)]; if ((A < 0) === (B < 0)) continue;
      quad(cella[cid(i, j - 1, k - 1)], cella[cid(i, j, k - 1)], cella[cid(i, j, k)], cella[cid(i, j - 1, k)], A < 0); }
    for (let k = 1; k < nz - 1; k++) for (let j = 0; j < ny - 1; j++) for (let i = 1; i < nx - 1; i++) {   // lungo y
      const A = V[id(i, j, k)], B = V[id(i, j + 1, k)]; if ((A < 0) === (B < 0)) continue;
      quad(cella[cid(i - 1, j, k - 1)], cella[cid(i - 1, j, k)], cella[cid(i, j, k)], cella[cid(i, j, k - 1)], A < 0); }
    for (let k = 0; k < nz - 1; k++) for (let j = 1; j < ny - 1; j++) for (let i = 1; i < nx - 1; i++) {   // lungo z
      const A = V[id(i, j, k)], B = V[id(i, j, k + 1)]; if ((A < 0) === (B < 0)) continue;
      quad(cella[cid(i - 1, j - 1, k)], cella[cid(i, j - 1, k)], cella[cid(i, j, k)], cella[cid(i - 1, j, k)], A < 0); }
    return { t: new Float32Array(tri), n: new Float32Array(nor) };
  };
})();
