// Crea usuarios y datos de ejemplo en el emulador local (requiere `npm run emulador` corriendo).
// No toca Firebase real.
import { pathToFileURL } from "node:url";
import { EMULADOR, configEmulador } from "../web/config.js";

process.env.PIZARRA_EMULADOR = "1";

export const USUARIOS_PRUEBA = [
  { email: "luis.delgadillo@solomonk.cl", nombre: "Luis", areas: ["programación", "arquitectura"] },
  { email: "fdoreyesvasquez@gmail.com", nombre: "Compañero", areas: ["diseño", "arte", "historia"] },
];
export const CLAVE_PRUEBA = "pizarra123";

export async function sembrar({ conEjemplos = true } = {}) {
  for (const u of USUARIOS_PRUEBA) {
    const r = await fetch(`${EMULADOR.auth}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=${configEmulador.apiKey}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email: u.email, password: CLAVE_PRUEBA, returnSecureToken: true }),
    });
    const cuerpo = await r.json();
    if (!r.ok && cuerpo.error?.message !== "EMAIL_EXISTS") throw new Error(`No se pudo crear ${u.email}: ${cuerpo.error?.message}`);
  }

  process.env.PIZARRA_EMAIL = USUARIOS_PRUEBA[0].email;
  process.env.PIZARRA_PASSWORD = CLAVE_PRUEBA;
  const { conectar, desconectar } = await import("../mcp/conexion.js");
  const { nucleo } = await conectar();
  for (const u of USUARIOS_PRUEBA) await nucleo.guardarMiembro(u.email, { nombre: u.nombre, areas: u.areas });

  if (conEjemplos) {
    const [li, comp] = USUARIOS_PRUEBA.map((u) => u.email);
    const p = await nucleo.crearPropuesta({ titulo: "Combate naval", descripcion: "Primer prototipo jugable del combate naval de 1879.", objetivo: "Un duelo Huáscar vs. Esmeralda jugable de principio a fin.", actor: "orquestador" });
    const t1 = await nucleo.crearTarea({ titulo: "Definir mecánicas del combate naval", descripcion: "Movimiento, disparo, daño y abordaje.", tipo: "decision", prioridad: "P1", agente: "game-designer", responsable: comp, propuestaId: p, estado: "en_progreso" }, { actor: "orquestador" });
    await nucleo.crearTarea({ titulo: "Ficha histórica de los buques de 1879", descripcion: "Huáscar, Esmeralda, Covadonga, Independencia: armamento, velocidad, tripulación.", tipo: "investigacion", prioridad: "P2", agente: "historiador", responsable: comp, propuestaId: p, estado: "lista" }, { actor: "orquestador" });
    const t3 = await nucleo.crearTarea({ titulo: "ADR: sistema de turnos", descripcion: "Cómo se resuelve el orden de acciones.", tipo: "decision", prioridad: "P1", agente: "arquitecto", responsable: li, propuestaId: p, estado: "lista", dependencias: [t1] }, { actor: "orquestador" });
    await nucleo.crearTarea({ titulo: "Escena base del mar y cámara", descripcion: "Escena Godot con el mar, la cámara y dos buques de prueba.", prioridad: "P1", agente: "dev-godot", responsable: li, propuestaId: p, estado: "hecha", criterios: ["La escena carga sin errores", "La cámara hace zoom y desplazamiento"] }, { actor: "dev-godot" });
    await nucleo.crearPregunta({ tareaId: t3, pregunta: "¿El combate naval es en tiempo real o por turnos?", contexto: "Define toda la arquitectura del sistema de combate.", opciones: ["Por turnos", "Tiempo real con pausa", "Tiempo real"], dirigidaA: li, actor: "arquitecto" });
    await nucleo.registrarDecision({ titulo: "Godot 4 con GDScript", contexto: "Elegir motor y lenguaje.", decision: "Usar Godot 4 y GDScript para todo el juego.", alternativas: "C# (más complejo de exportar), Unity (licencia).", consecuencias: "Todo el equipo trabaja en GDScript.", area: "arquitectura", estado: "aceptada" }, { actor: "arquitecto" });
    await nucleo.registrarSesion({ resumen: "Se armó la pizarra y la propuesta de combate naval.", hecho: ["Escena base del mar"], pendiente: ["Decidir turnos vs. tiempo real"], proximosPasos: ["ADR del sistema de turnos", "Fichas históricas de los buques"] });
  }
  await desconectar();
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  await sembrar();
  console.log(`Emulador listo. Usuarios: ${USUARIOS_PRUEBA.map((u) => u.email).join(", ")} (clave: ${CLAVE_PRUEBA})`);
  process.exit(0);
}
