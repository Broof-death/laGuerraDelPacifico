// Lecturas compuestas que usan tanto el servidor MCP como el hook de inicio de sesión.
import { ESTADOS_CERRADOS } from "../web/nucleo.js";
import { textoResumen } from "./formato.js";

export async function resumenComoTexto({ nucleo, fs }) {
  const [tareas, preguntas, propuestas, sesiones, equipo, novedades] = await Promise.all([
    nucleo.listar("tareas", fs.where("estado", "not-in", ESTADOS_CERRADOS)),
    nucleo.listar("preguntas", fs.where("estado", "==", "abierta")),
    nucleo.listar("propuestas", fs.where("estado", "==", "activa")),
    nucleo.listar("sesiones", fs.orderBy("creadaEn", "desc"), fs.limit(1)),
    nucleo.equipo(),
    nucleo.novedades(),
  ]);
  // Las tareas hechas de las propuestas activas se necesitan para mostrar el avance.
  const ids = propuestas.map((p) => p.id);
  // (se filtra en memoria para no depender de índices compuestos).
  const hechas = ids.length ? (await nucleo.listar("tareas", fs.where("propuestaId", "in", ids.slice(0, 30)))).filter((t) => t.estado === "hecha") : [];
  return textoResumen({ tareas: [...tareas, ...hechas], preguntas, propuestas, sesion: sesiones[0], novedades, equipo, yo: nucleo.usuario });
}

// Acepta un correo, un nombre del equipo o "yo".
export function resolverMiembro(texto, equipo, yo) {
  if (!texto) return null;
  const t = texto.trim().toLowerCase();
  if (t === "yo") return yo;
  if (t.includes("@")) return t;
  const encontrado = Object.entries(equipo).find(([email, m]) => m.nombre?.toLowerCase() === t || email.split("@")[0] === t);
  if (!encontrado) throw new Error(`No conozco a "${texto}" en el equipo. Miembros: ${Object.entries(equipo).map(([e, m]) => `${m.nombre || e} <${e}>`).join(", ") || "(ninguno; usa ver_equipo / actualizar_miembro)"}`);
  return encontrado[0];
}
