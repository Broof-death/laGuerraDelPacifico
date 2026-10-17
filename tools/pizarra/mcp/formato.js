// Formato de texto compacto para que Claude lea el estado de la pizarra.
import { ESTADOS, ESTADOS_CERRADOS, PRIORIDADES, AGENTES, ESTADOS_DECISION } from "../web/nucleo.js";

export function nombreDe(equipo, email) {
  if (!email) return "sin responsable";
  return equipo[email]?.nombre || email.split("@")[0];
}

export function fecha(ts) {
  if (!ts?.toDate) return "—";
  return ts.toDate().toLocaleString("es-CL", { dateStyle: "short", timeStyle: "short" });
}

export function lineaTarea(t, equipo) {
  const agente = t.agente ? AGENTES[t.agente]?.nombre || t.agente : "sin agente";
  return `${t.id} [${ESTADOS[t.estado]}] ${t.prioridad} · ${t.titulo} · agente: ${agente} · resp: ${nombreDe(equipo, t.responsable)}${t.propuestaId ? ` · ${t.propuestaId}` : ""}`;
}

export function lineaPregunta(p, equipo) {
  const opciones = p.opciones?.length ? ` Opciones: ${p.opciones.join(" | ")}` : "";
  return `${p.id}${p.tareaId ? ` (${p.tareaId})` : ""} → ${nombreDe(equipo, p.dirigidaA)}: ${p.pregunta}${opciones}`;
}

export function lineaActividad(a, equipo) {
  const quien = a.actor ? `${AGENTES[a.actor]?.nombre || a.actor} (Claude de ${nombreDe(equipo, a.quien)})` : nombreDe(equipo, a.quien);
  return `${fecha(a.ts)} · ${quien} · ${a.entidadId}: ${a.resumen}`;
}

export function detalleTarea(t, preguntas, actividad, equipo) {
  const l = [
    lineaTarea(t, equipo),
    `Tipo: ${t.tipo} · Prioridad: ${t.prioridad} (${PRIORIDADES[t.prioridad]}) · Rama: ${t.rama || "—"}`,
    t.dependencias?.length ? `Depende de: ${t.dependencias.join(", ")}` : null,
    "",
    t.descripcion || "(sin descripción)",
  ];
  if (t.criterios?.length) l.push("", "Criterios de aceptación:", ...t.criterios.map((c) => `- ${c}`));
  if (preguntas.length) {
    l.push("", "Bloqueos:");
    for (const p of preguntas) l.push(`- ${lineaPregunta(p, equipo)} [${p.estado}]${p.respuesta ? ` → ${p.respuesta}` : ""}`);
  }
  if (actividad.length) l.push("", "Historial:", ...actividad.map((a) => `- ${lineaActividad(a, equipo)}`));
  return l.filter((x) => x !== null).join("\n");
}

export function detalleDecision(d) {
  return [
    `${d.id} [${ESTADOS_DECISION[d.estado]}] ${d.titulo} · área: ${d.area}${d.reemplazaA ? ` · reemplaza a ${d.reemplazaA}` : ""}`,
    `Contexto: ${d.contexto || "—"}`,
    `Decisión: ${d.decision || "—"}`,
    `Alternativas: ${d.alternativas || "—"}`,
    `Consecuencias: ${d.consecuencias || "—"}`,
  ].join("\n");
}

export function textoNovedades({ primeraVez, cambios }, equipo) {
  if (primeraVez && !cambios.length) return "";
  if (!cambios.length) return "";
  return [`Novedades de tu equipo desde tu última consulta (${cambios.length}):`, ...cambios.map((a) => `- ${lineaActividad(a, equipo)}`)].join("\n");
}

export function textoResumen({ tareas, preguntas, propuestas, sesion, novedades, equipo, yo }) {
  const activas = tareas.filter((t) => !ESTADOS_CERRADOS.includes(t.estado));
  const conteo = Object.keys(ESTADOS)
    .filter((e) => !ESTADOS_CERRADOS.includes(e))
    .map((e) => `${ESTADOS[e]}: ${activas.filter((t) => t.estado === e).length}`)
    .join(" · ");
  const orden = (a, b) => a.prioridad.localeCompare(b.prioridad) || a.id.localeCompare(b.id);
  const mias = activas.filter((t) => t.responsable === yo).sort(orden);
  const misBloqueos = preguntas.filter((p) => p.dirigidaA === yo);
  const otrosBloqueos = preguntas.filter((p) => p.dirigidaA !== yo);

  const l = [`PIZARRA — La Guerra del Pacífico (sesión de ${nombreDe(equipo, yo)})`, `Tareas activas: ${activas.length} (${conteo})`];
  if (propuestas.length) {
    l.push("", "Propuestas activas:");
    for (const p of propuestas) {
      const suyas = tareas.filter((t) => t.propuestaId === p.id && t.estado !== "cancelada");
      l.push(`- ${p.id} ${p.titulo}: ${suyas.filter((t) => t.estado === "hecha").length}/${suyas.length} hechas`);
    }
  }
  l.push("", `Bloqueos que te toca resolver (${misBloqueos.length}):`, ...(misBloqueos.length ? misBloqueos.map((p) => `- ${lineaPregunta(p, equipo)}`) : ["- ninguno"]));
  if (otrosBloqueos.length) l.push("", "Bloqueos esperando a otras personas:", ...otrosBloqueos.map((p) => `- ${lineaPregunta(p, equipo)}`));
  l.push("", `Tus tareas (${mias.length}):`, ...(mias.length ? mias.slice(0, 15).map((t) => `- ${lineaTarea(t, equipo)}`) : ["- ninguna"]));
  if (sesion) {
    l.push("", `Última sesión (${sesion.id}, ${fecha(sesion.creadaEn)}, ${nombreDe(equipo, sesion.creadaPor)}): ${sesion.resumen}`);
    if (sesion.proximosPasos?.length) l.push("Próximos pasos:", ...sesion.proximosPasos.map((x) => `- ${x}`));
  }
  const nov = textoNovedades(novedades, equipo);
  if (nov) l.push("", nov);
  return l.join("\n");
}
