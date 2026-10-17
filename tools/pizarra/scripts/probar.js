// Prueba de punta a punta contra el emulador: dos personas, cada una con su servidor MCP,
// trabajando sobre la misma pizarra. Requiere `npm run emulador` corriendo. Borra los datos del emulador.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { initializeApp } from "firebase/app";
import { getAuth, connectAuthEmulator, signInWithEmailAndPassword } from "firebase/auth";
import { getFirestore, connectFirestoreEmulator, getDocs, collection, terminate } from "firebase/firestore";
import { EMULADOR, configEmulador } from "../web/config.js";
import { sembrar, USUARIOS_PRUEBA, CLAVE_PRUEBA } from "./sembrar-emulador.js";

const RAIZ = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const proyecto = configEmulador.projectId;
const [LI, COMP] = USUARIOS_PRUEBA.map((u) => u.email);

await fetch(`http://${EMULADOR.firestoreHost}:${EMULADOR.firestorePuerto}/emulator/v1/projects/${proyecto}/databases/(default)/documents`, { method: "DELETE" });
await fetch(`${EMULADOR.auth}/emulator/v1/projects/${proyecto}/accounts`, { method: "DELETE" });
await sembrar({ conEjemplos: false });

const entorno = (email) => ({ ...process.env, PIZARRA_EMULADOR: "1", PIZARRA_EMAIL: email, PIZARRA_PASSWORD: CLAVE_PRUEBA });

async function claudeDe(email) {
  const cliente = new Client({ name: `prueba-${email}`, version: "1.0.0" });
  await cliente.connect(new StdioClientTransport({ command: process.execPath, args: [path.join(RAIZ, "mcp/server.js")], env: entorno(email), stderr: "inherit" }));
  return async (nombre, args = {}) => {
    const r = await cliente.callTool({ name: nombre, arguments: args });
    const texto = r.content.map((c) => c.text).join("\n");
    if (r.isError) throw new Error(`${nombre}: ${texto}`);
    return texto;
  };
}

let pasos = 0;
const paso = (nombre) => console.log(`✓ ${++pasos}. ${nombre}`);

const li = await claudeDe(LI);
const comp = await claudeDe(COMP);

const herramientas = await (async () => {
  const c = new Client({ name: "lista", version: "1.0.0" });
  await c.connect(new StdioClientTransport({ command: process.execPath, args: [path.join(RAIZ, "mcp/server.js")], env: entorno(LI) }));
  const { tools } = await c.listTools();
  await c.close();
  return tools.map((t) => t.name);
})();
assert.ok(herramientas.length >= 20, `se esperaban 20+ herramientas, hay ${herramientas.length}`);
paso(`El servidor MCP expone ${herramientas.length} herramientas`);

assert.match(await li("ver_equipo"), /Luis <luis.delgadillo@solomonk.cl> \(tú\): programación, arquitectura/);
paso("ver_equipo reconoce a la persona conectada");

const p = (await li("crear_propuesta", { titulo: "Combate naval", descripcion: "Prototipo", actor: "orquestador" })).match(/P-\d+/)[0];
const t = (await li("crear_tarea", { titulo: "Sistema de turnos", descripcion: "Orden de acciones", prioridad: "P1", agente: "arquitecto", responsable: "yo", propuestaId: p, estado: "lista", actor: "orquestador" })).match(/T-\d+/)[0];
const t2 = (await li("crear_tarea", { titulo: "Fichas de buques", descripcion: "Datos 1879", prioridad: "P2", agente: "historiador", responsable: "Compañero", propuestaId: p, actor: "orquestador" })).match(/T-\d+/)[0];
assert.equal(p, "P-001");
assert.equal(t, "T-001");
assert.equal(t2, "T-002");
paso("Se crean propuesta y tareas con IDs legibles, resolviendo responsables por nombre y por 'yo'");

await assert.rejects(li("actualizar_tarea", { id: t, estado: "inventado" }), /Invalid|inválid|enum/i);
paso("Rechaza estados no válidos");

const novComp = await comp("pizarra_resumen");
assert.match(novComp, /Novedades de tu equipo/);
assert.match(novComp, new RegExp(`${t2} \\[Backlog\\] P2 · Fichas de buques`));
paso("El compañero ve en su resumen las novedades hechas por el Claude de Luis y su tarea asignada");

const q = (await comp("crear_pregunta", { tareaId: t, pregunta: "¿Turnos o tiempo real?", opciones: ["Turnos", "Tiempo real"], dirigidaA: "Luis", actor: "game-designer" })).match(/Q-\d+/)[0];
const vistaLi = await li("ver_tarea", { id: t });
assert.match(vistaLi, /\[Bloqueada\]/);
assert.match(vistaLi, /Novedades de tu equipo[\s\S]*Game Designer \(Claude de Compañero\)/);
paso("Un bloqueo creado por el compañero deja la tarea de Luis bloqueada y le llega como novedad");

const resumenLi = await li("pizarra_resumen");
assert.match(resumenLi, /Bloqueos que te toca resolver \(1\):\n- Q-001 \(T-001\) → Luis: ¿Turnos o tiempo real\? Opciones: Turnos \| Tiempo real/);
paso("Luis ve en su resumen el bloqueo dirigido a él");

assert.match(await li("responder_pregunta", { id: q, respuesta: "Turnos" }), /vuelve a "Lista"/);
assert.match(await li("ver_tarea", { id: t }), /\[Lista\][\s\S]*Respuesta a "¿Turnos o tiempo real\?": Turnos/);
await assert.rejects(li("responder_pregunta", { id: q, respuesta: "otra" }), /ya fue respondida/);
paso("Al responder, la tarea vuelve a su estado anterior y la respuesta queda en el historial");

await li("actualizar_tarea", { id: t, estado: "en_progreso", rama: "feature/turnos", actor: "dev-godot" });
await li("actualizar_tarea", { id: t, estado: "hecha", nota: "Aprobado por QA", actor: "qa" });
assert.match(await li("listar_propuestas"), /P-001 \[Activa\] Combate naval — 1\/2 tareas hechas/);
paso("El avance de la propuesta se calcula con las tareas hechas");

const adr = (await li("registrar_decision", { titulo: "Combate por turnos", contexto: "Q-001", decision: "Turnos", estado: "aceptada", area: "diseño", actor: "arquitecto" })).match(/ADR-\d+/)[0];
const adr2 = (await li("registrar_decision", { titulo: "Turnos con iniciativa", contexto: "Ajuste", decision: "Por iniciativa", reemplazaA: adr, actor: "arquitecto" })).match(/ADR-\d+/)[0];
assert.match(await li("listar_decisiones"), new RegExp(`${adr} \\[Reemplazada\\][\\s\\S]*${adr2} \\[Propuesta\\]`));
paso("Las decisiones (ADR) se registran y una nueva puede reemplazar a otra");

await li("cerrar_sesion", { resumen: "Se definió el combate por turnos", proximosPasos: ["Implementar iniciativa"] });
const hook = execFileSync(process.execPath, [path.join(RAIZ, "scripts/resumen.js")], { env: entorno(COMP), encoding: "utf8" });
assert.match(hook, /Última sesión \(S-001[^)]*\): Se definió el combate por turnos/);
assert.match(hook, /- Implementar iniciativa/);
paso("El hook de inicio de chat del compañero muestra la última sesión y los próximos pasos");

assert.doesNotMatch(await comp("pizarra_novedades"), /Novedades de tu equipo/);
paso("Las novedades no se repiten una vez vistas");

// Reglas de seguridad: alguien fuera de la lista no puede leer.
await fetch(`${EMULADOR.auth}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=${configEmulador.apiKey}`, {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ email: "intruso@ejemplo.com", password: CLAVE_PRUEBA }),
});
const app = initializeApp(configEmulador, "intruso");
const auth = getAuth(app);
connectAuthEmulator(auth, EMULADOR.auth, { disableWarnings: true });
const db = getFirestore(app);
connectFirestoreEmulator(db, EMULADOR.firestoreHost, EMULADOR.firestorePuerto);
await signInWithEmailAndPassword(auth, "intruso@ejemplo.com", CLAVE_PRUEBA);
await assert.rejects(getDocs(collection(db, "tareas")), /permission/i);
await terminate(db);
paso("Las reglas de Firestore bloquean a quien no está en la lista");

console.log(`\nTodo bien: ${pasos} pruebas superadas.`);
process.exit(0);
