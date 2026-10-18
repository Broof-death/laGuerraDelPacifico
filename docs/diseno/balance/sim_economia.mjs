// Simulacion simple de la economia v1 (paso de 1 s). T-022, docs/diseno/economia.md 9.4.
// Uso: node sim_economia.mjs RITMO PRECIO_CARBON [OPERARIOS_OBJETIVO]
// Ejemplo: node sim_economia.mjs 1.0 2.0   (Peru, ritmo medio)
// Supuestos: sin perdidas ni ataques; construccion con 2 operarios (x0,67); gasto militar solo en infanteria de linea.
const RATE = parseFloat(process.argv[2] ?? '1');
const COAL_PRICE = parseFloat(process.argv[3] ?? '2');
const ECON_TARGET = parseInt(process.argv[4] ?? '110');
// [costoV, costoP, build_s, puestos, tasa/operario/min, recurso, pop_porteadores, P_porteadores, V_porteadores, carbon/min]
const B = {
  hacienda: [0, 100, 45, 5, 20, 'V', 0, 0, 0, 0],
  paradas: [0, 200, 60, 6, 15, 'P', 3, 120, 120, 0],
  shanks: [0, 600, 150, 8, 30, 'P', 2, 650, 0, 10],
  shanks2: [0, 600, 150, 8, 30, 'P', 2, 250, 0, 10],
  covadera: [0, 150, 60, 5, 18, 'P', 0, 0, 0, 0],
  muelle: [0, 250, 60, 0, 0, 'P', 0, 0, 0, 0],
  carbonera: [0, 250, 60, 0, 0, 'P', 0, 0, 0, 0],
  cuartel: [0, 200, 60, 0, 0, 'P', 0, 0, 0, 0],
  centro: [200, 600, 180, 0, 0, 'P', 0, 0, 0, 0],
};
const plan = ['hacienda', 'paradas', 'muelle', 'hacienda', 'cuartel', 'hacienda', 'paradas', 'carbonera', 'shanks',
  'hacienda', 'centro', 'covadera', 'hacienda', 'cuartel', 'shanks2', 'hacienda', 'hacienda', 'cuartel',
  'covadera', 'hacienda', 'hacienda', 'hacienda'];
let V = 400, P = 600, idle = 6, pop = 6, cap = 50, centros = 1, cuarteles = 0;
let slots = [], working = { V: 0, P: 0 }, coal = 0, pending = [], pi = 0, tq = [], mq = [], mil = 0, carriers = 0;
const log = [], first = {};
let cumV = 0, cumP = 0, c40 = null, planDone = null;
for (let t = 0; t < 90 * 60; t++) {
  const dv = working.V * RATE / 60;
  const dp = working.P * RATE / 60 + 60 * centros / 60 - coal * COAL_PRICE / 60;
  V += dv; P += dp; cumV += dv; cumP += dp;
  for (const x of pending.filter(x => x[0] <= t)) {
    pending.splice(pending.indexOf(x), 1);
    const n = x[1];
    if (n === 'poblacion') { cap = Math.min(500, cap + 50); continue; }
    const b = B[n];
    for (let i = 0; i < b[3]; i++) slots.push([b[4], b[5]]);
    if (n === 'centro') { centros++; cap = Math.min(500, cap + 50); }
    if (n === 'cuartel') cuarteles++;
    coal += b[9];
  }
  while (idle > 0 && slots.length) { const [r, res] = slots.shift(); working[res] += r; idle--; }
  if (pop + 8 >= cap && cap < 500 && V >= 50 && P >= 100 && !pending.some(x => x[1] === 'poblacion')) {
    V -= 50; P -= 100; pending.push([t + 27, 'poblacion']);
  }
  if (pi < plan.length) {
    const n = plan[pi], b = B[n];
    if (V >= b[0] + b[8] && P >= b[1] + b[7] && pop + b[6] <= cap) {
      V -= b[0] + b[8]; P -= b[1] + b[7]; pop += b[6]; carriers += b[6];
      pending.push([t + Math.floor(b[2] / 1.5), n]); pi++;
      if (pi === plan.length) planDone = t / 60;
    }
  }
  const econ = pop - mil - carriers;
  if (tq.length < centros && econ + tq.length < ECON_TARGET && V >= 50 && pop + tq.length + mq.length < cap) { V -= 50; tq.push(t + 20); }
  for (const x of tq.filter(x => x <= t)) { tq.splice(tq.indexOf(x), 1); pop++; idle++; }
  const reserve = pi < plan.length;
  if (mq.length < cuarteles && V >= 60 + (reserve ? 150 : 0) && P >= 30 + (reserve ? 300 : 0) && pop + tq.length + mq.length < cap) { V -= 60; P -= 30; mq.push(t + 22); }
  for (const x of mq.filter(x => x <= t)) { mq.splice(mq.indexOf(x), 1); pop++; mil++; }
  if (!reserve && V > 600 && P > 400 && cuarteles < 10 && !pending.some(x => x[1] === 'cuartel')) { P -= 200; pending.push([t + 40, 'cuartel']); }
  if (t % 300 === 0 && t <= 3600) log.push([t / 60, pop, cap, mil, Math.round(working.V * RATE), Math.round(working.P * RATE + 60 * centros - coal * COAL_PRICE), Math.round(V), Math.round(P), cuarteles].join(' '));
  for (const k of [30, 100, 200, 300, 380]) if (mil >= k && !(k in first)) first[k] = (t / 60).toFixed(1);
  if (t === 40 * 60) c40 = [Math.round(cumV), Math.round(cumP)];
}
console.log('RATE', RATE, 'COAL_PRICE', COAL_PRICE, 'ECON_TARGET', ECON_TARGET);
console.log('min pop cap mil V/min Pneto/min V P cuarteles');
log.forEach(l => console.log(l));
console.log('plan economico terminado (min):', planDone?.toFixed(1));
console.log('militares alcanzados (min):', JSON.stringify(first));
console.log('acumulado a los 40 min (V, P neto):', JSON.stringify(c40));


