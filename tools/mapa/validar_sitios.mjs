// Valida tools/mapa/sitios.json con las reglas de ADR-009 §1b (T-040).
// Uso: node tools/mapa/validar_sitios.mjs [ruta/a/sitios.json]
//
// - Proyecta con transversa de Mercator (WGS84, serie de Krüger de orden 3,
//   error << 1 m en la caja) con lon_0 = -72,5 y lat_0 = -22,5 (ADR-009 §1).
// - Calcula R de cada lupa con R = [k·r + w·(k+1)/2 − ρc·(r + w)] / (1 − ρc)
//   y lo comprueba integrando ρ numéricamente (d'(R) = R).
// - Comprueba: k ∈ [3, 5], ρc ∈ [0,5, 1), discos R sin solapes, núcleo
//   ampliado (k·r) dentro de la caja jugable, puntos del núcleo a ≤ r del
//   centro, y dónde caen los sitios sin lupa (núcleo, anillo o fuera).
// Las distancias se dan en km "reales proyectados" (plano a 1:1) y en m de
// juego (÷ 20). Sale con código 1 si alguna regla falla.

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const ruta = process.argv[2] ?? join(dirname(fileURLToPath(import.meta.url)), "sitios.json");
const datos = JSON.parse(readFileSync(ruta, "utf8"));
const P = datos.proyeccion;
const ESCALA = P.escala;

// --- Transversa de Mercator (Karney 2011, serie de Krüger) ---
const a = 6378137.0, f = 1 / 298.257223563;
const n = f / (2 - f);
const A = (a / (1 + n)) * (1 + n * n / 4 + n ** 4 / 64);
const alfa = [n / 2 - (2 / 3) * n * n + (5 / 16) * n ** 3, (13 / 48) * n * n - (3 / 5) * n ** 3, (61 / 240) * n ** 3];
const e2n = (2 * Math.sqrt(n)) / (1 + n);
const rad = (g) => (g * Math.PI) / 180;

function tmCrudo(lat, lon) {
  const phi = rad(lat), dl = rad(lon - P.lon_0);
  const s = Math.sin(phi);
  const t = Math.sinh(Math.atanh(s) - e2n * Math.atanh(e2n * s));
  const xi = Math.atan2(t, Math.cos(dl));
  const eta = Math.atanh(Math.sin(dl) / Math.sqrt(1 + t * t));
  let E = eta, N = xi;
  for (let j = 1; j <= 3; j++) {
    E += alfa[j - 1] * Math.cos(2 * j * xi) * Math.sinh(2 * j * eta);
    N += alfa[j - 1] * Math.sin(2 * j * xi) * Math.cosh(2 * j * eta);
  }
  return { E: P.k_0 * A * E, N: P.k_0 * A * N };
}
const N0 = tmCrudo(P.lat_0, P.lon_0).N;
// Plano a 1:1 en metros: x al este, z al sur (convención de ADR-009 §3).
function proyectar(lat, lon) {
  const { E, N } = tmCrudo(lat, lon);
  return { x: E, z: -(N - N0) };
}
const dist = (p, q) => Math.hypot(p.x - q.x, p.z - q.z);

// --- Lupa ---
const smooth = (t) => t * t * (3 - 2 * t);
function radioR(r, k, w, rc) {
  return (k * r + (w * (k + 1)) / 2 - rc * (r + w)) / (1 - rc);
}
function rho(d, L) {
  const { r, k, w, rc, R } = L;
  if (d <= r) return k;
  if (d <= r + w) return k + (rc - k) * smooth((d - r) / w);
  if (d <= R - w) return rc;
  if (d <= R) return rc + (1 - rc) * smooth((d - (R - w)) / w);
  return 1;
}
function dPrima(d, L, pasos = 20000) {
  if (d >= L.R) return d;
  const h = d / pasos;
  let s = 0;
  for (let i = 0; i < pasos; i++) s += rho((i + 0.5) * h, L) * h; // regla del punto medio
  return s;
}

// --- Borde de la caja, muestreado en el plano ---
const C = datos.caja;
const borde = [];
const paso = 0.01;
for (let lon = C.lon_oeste; lon <= C.lon_este + 1e-9; lon += paso) {
  borde.push(proyectar(C.lat_norte, lon), proyectar(C.lat_sur, lon));
}
for (let lat = C.lat_sur; lat <= C.lat_norte + 1e-9; lat += paso) {
  borde.push(proyectar(lat, C.lon_oeste), proyectar(lat, C.lon_este));
}
const distBorde = (p) => Math.min(...borde.map((b) => dist(p, b)));
const dentroCaja = (lat, lon) => lat <= C.lat_norte && lat >= C.lat_sur && lon >= C.lon_oeste && lon <= C.lon_este;
// Polígono de la caja en el plano (norte O→E, este N→S, sur E→O, oeste S→N),
// para saber si un punto desplazado por una lupa sigue dentro de la caja.
const poligono = [];
for (let lon = C.lon_oeste; lon <= C.lon_este + 1e-9; lon += paso) poligono.push(proyectar(C.lat_norte, lon));
for (let lat = C.lat_norte; lat >= C.lat_sur - 1e-9; lat -= paso) poligono.push(proyectar(lat, C.lon_este));
for (let lon = C.lon_este; lon >= C.lon_oeste - 1e-9; lon -= paso) poligono.push(proyectar(C.lat_sur, lon));
for (let lat = C.lat_sur; lat <= C.lat_norte + 1e-9; lat += paso) poligono.push(proyectar(lat, C.lon_oeste));
function dentroPoligono(p) {
  let dentro = false;
  for (let i = 0, j = poligono.length - 1; i < poligono.length; j = i++) {
    const a_ = poligono[i], b_ = poligono[j];
    if (a_.z > p.z !== b_.z > p.z && p.x < ((b_.x - a_.x) * (p.z - a_.z)) / (b_.z - a_.z) + a_.x) dentro = !dentro;
  }
  return dentro;
}

// --- Validación ---
const defecto = datos.lupa_por_defecto;
const errores = [];
const avisos = [];
const km = (m) => (m / 1000).toFixed(2);
const juego = (m) => (m / ESCALA).toFixed(0);

const lupas = datos.sitios.map((s) => {
  const r = s.radio_real_km * 1000;
  const w = (s.w_factor ?? defecto.w_factor) * r;
  const rc = s.rho_c ?? defecto.rho_c;
  const L = { id: s.id, r, k: s.k, w, rc, c: proyectar(s.lat, s.lon), s };
  L.R = radioR(r, s.k, w, rc);
  for (const campo of ["id", "nombre", "lat", "lon", "radio_real_km", "k", "motivo", "licencia"]) {
    if (s[campo] === undefined || s[campo] === "") errores.push(`${s.id}: falta el campo ${campo}`);
  }
  if (!(s.k >= 3 && s.k <= 5)) errores.push(`${s.id}: k = ${s.k} fuera de [3, 5]`);
  if (!(rc >= 0.5 && rc < 1)) errores.push(`${s.id}: rho_c = ${rc} fuera de [0,5, 1)`);
  if (L.R - w < r + w) errores.push(`${s.id}: el anillo de compresión no cabe (R − w < r + w)`);
  if (!dentroCaja(s.lat, s.lon)) errores.push(`${s.id}: el centro está fuera de la caja`);
  const cierre = dPrima(L.R * 0.999999, L) - L.R * 0.999999;
  if (Math.abs(cierre) > 1) errores.push(`${s.id}: d'(R) ≠ R (diferencia ${cierre.toFixed(2)} m)`);
  L.borde = distBorde(L.c);
  if (s.k * r > L.borde) errores.push(`${s.id}: el núcleo ampliado (${km(s.k * r)} km) se sale de la caja (borde a ${km(L.borde)} km)`);
  L.puntos = (s.puntos_nucleo ?? []).map((p) => {
    const d = dist(L.c, proyectar(p.lat, p.lon));
    if (d > r) errores.push(`${s.id}: "${p.nombre}" está a ${km(d)} km del centro, fuera del núcleo de ${km(r)} km`);
    return { nombre: p.nombre, d };
  });
  return L;
});

const solapes = [];
for (let i = 0; i < lupas.length; i++) {
  for (let j = i + 1; j < lupas.length; j++) {
    const A_ = lupas[i], B_ = lupas[j];
    const d = dist(A_.c, B_.c);
    const holgura = d - (A_.R + B_.R);
    solapes.push({ a: A_.id, b: B_.id, d, holgura });
    if (holgura < 0) errores.push(`${A_.id} y ${B_.id}: los discos R se solapan (${km(-holgura)} km)`);
  }
}

// --- Informe ---
console.log(`Sitios: ${ruta}`);
console.log("\nLUPAS (km reales proyectados; m de juego = km·1000/20)");
console.log("id                     k  ρc   r km   k·r km   R km   R/r   r juego  k·r juego  R juego  borde km");
for (const L of lupas) {
  console.log(
    `${L.id.padEnd(22)} ${L.k}  ${L.rc.toFixed(2)} ${km(L.r).padStart(6)} ${km(L.k * L.r).padStart(8)} ${km(L.R).padStart(7)} ${(L.R / L.r).toFixed(2).padStart(5)} ${juego(L.r).padStart(8)} ${juego(L.k * L.r).padStart(10)} ${juego(L.R).padStart(8)} ${km(L.borde).padStart(9)}`
  );
  console.log(`    centro de juego: x = ${juego(L.c.x)} m, z = ${juego(L.c.z)} m`);
  for (const p of L.puntos) console.log(`    núcleo: ${p.nombre} a ${km(p.d)} km del centro`);
}

console.log("\nPARES MÁS CERCANOS (holgura = distancia − R_a − R_b)");
for (const s of solapes.sort((x, y) => x.holgura - y.holgura).slice(0, 10)) {
  console.log(`  ${s.a} – ${s.b}: d = ${km(s.d)} km, holgura = ${km(s.holgura)} km`);
}

console.log("\nSITIOS SIN LUPA: dónde caen");
for (const p of datos.sin_lupa ?? []) {
  const q = proyectar(p.lat, p.lon);
  let donde = "fuera de toda lupa (1:20 sin deformar)";
  for (const L of lupas) {
    const d = dist(L.c, q);
    if (d < L.R) {
      const zona = d <= L.r ? "NÚCLEO" : d <= L.r + L.w ? "transición interior" : d <= L.R - L.w ? "anillo de compresión" : "transición exterior";
      const dp = dPrima(d, L);
      const q2 = { x: L.c.x + ((q.x - L.c.x) * dp) / d, z: L.c.z + ((q.z - L.c.z) * dp) / d };
      donde = `${zona} de ${L.id} (a ${km(d)} km; se mueve a ${km(dp)} km del centro, ${dp >= d ? "+" : ""}${km(dp - d)} km)`;
      if (dentroCaja(p.lat, p.lon) && !dentroPoligono(q2)) {
        donde += " -> AVISO: la lupa lo empuja FUERA de la caja (queda recortado)";
        avisos.push(`${p.id}: la lupa de ${L.id} lo empuja fuera de la caja`);
      }
    }
  }
  console.log(`  ${p.id}: ${donde}`);
}

// Hasta qué distancia del centro llega lo que sigue dentro de la caja, en la
// dirección del borde más cercano (solo informativo: ADR-009 permite recortar).
console.log("\nRECORTE POR EL BORDE MÁS CERCANO (lupas cuyo disco R sale de la caja)");
for (const L of lupas) {
  if (L.R <= L.borde) continue;
  let lo = 0, hi = L.R;
  for (let i = 0; i < 40; i++) {
    const mid = (lo + hi) / 2;
    if (dPrima(mid, L, 4000) < L.borde) lo = mid; else hi = mid;
  }
  console.log(`  ${L.id}: borde a ${km(L.borde)} km; hacia ese borde solo queda en la caja lo que está a ≤ ${km(lo)} km reales del centro`);
}
if (avisos.length) {
  console.log(`\nAVISOS (${avisos.length}, no bloquean):`);
  for (const a2 of avisos) console.log(`  - ${a2}`);
}
for (const p of datos.fuera_del_mapa ?? []) {
  if (dentroCaja(p.lat, p.lon)) errores.push(`${p.id}: está en fuera_del_mapa pero cae dentro de la caja`);
}

if (errores.length) {
  console.log(`\nERRORES (${errores.length}):`);
  for (const e of errores) console.log(`  - ${e}`);
  process.exit(1);
}
console.log("\nOK: todas las reglas de ADR-009 §1b se cumplen.");
