#!/usr/bin/env node
// Servidor MCP de la pizarra (stdio). Cada persona lo ejecuta en su equipo con su propia cuenta.
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { ESTADOS, ESTADOS_CERRADOS, PRIORIDADES, TIPOS_TAREA, AGENTES, ESTADOS_PROPUESTA, ESTADOS_DECISION } from "../web/nucleo.js";
import { conectar, ErrorConfiguracion } from "./conexion.js";
import { resumenComoTexto, resolverMiembro } from "./consultas.js";
import { lineaTarea, lineaPregunta, lineaActividad, detalleTarea, detalleDecision, textoNovedades, nombreDe } from "./formato.js";

const claves = (o) => Object.keys(o);
const enumDe = (o) => z.enum(claves(o));

const actor = enumDe(AGENTES).optional().describe("Agente que realiza la acción (omitir si la acción la pidió directamente la persona).");
const miembro = z.string().describe('Correo, nombre de un miembro del equipo o "yo".');

const INSTRUCCIONES = `Pizarra compartida del proyecto La Guerra del Pacífico (videojuego en Godot).
Es la fuente de verdad del avance: tareas, bloqueos que deben resolver personas, decisiones (ADR) y resúmenes de sesión. La usan dos personas, cada una con su propio Claude, en tiempo real.
Protocolo:
- Al empezar, llama a pizarra_resumen para saber qué pasó antes y qué está pendiente.
- Si una tarea requiere una decisión humana, crea un bloqueo con crear_pregunta y NO avances esa tarea hasta que esté respondida. Si el bloqueo es para la persona con la que hablas, pregúntale en el chat y registra su respuesta con responder_pregunta.
- Mantén los estados al día (en_progreso al empezar, en_revision al terminar, hecha cuando QA aprueba).
- Registra las decisiones importantes con registrar_decision.
- Antes de terminar la conversación, llama a cerrar_sesion con un resumen.
Las respuestas incluyen las novedades del equipo desde tu última consulta; menciónalas a la persona si son relevantes.`;

const servidor = new McpServer({ name: "pizarra", version: "0.1.0" }, { instructions: INSTRUCCIONES });

// Envuelve cada herramienta: conecta, ejecuta, agrega novedades y convierte errores en texto legible.
function herramienta(nombre, descripcion, entrada, fn, { conNovedades = true } = {}) {
  servidor.registerTool(nombre, { description: descripcion, inputSchema: entrada }, async (args) => {
    try {
      const ctx = await conectar();
      const equipo = await ctx.nucleo.equipo();
      let texto = await fn(args, { ...ctx, equipo, yo: ctx.nucleo.usuario });
      if (conNovedades) {
        const nov = textoNovedades(await ctx.nucleo.novedades(), equipo);
        if (nov) texto += `\n\n${nov}`;
      }
      return { content: [{ type: "text", text: texto }] };
    } catch (e) {
      const prefijo = e instanceof ErrorConfiguracion ? "La pizarra no está configurada" : "Error";
      return { isError: true, content: [{ type: "text", text: `${prefijo}: ${e.message}` }] };
    }
  });
}

herramienta(
  "pizarra_resumen",
  "Estado general del proyecto: conteo de tareas, propuestas activas, bloqueos pendientes, tus tareas, la última sesión y las novedades del equipo. Úsala al empezar cada conversación.",
  {},
  async (_, ctx) => resumenComoTexto(ctx),
  { conNovedades: false }
);

herramienta(
  "pizarra_novedades",
  "Solo los cambios que hizo el resto del equipo desde tu última consulta.",
  {},
  async (_, { nucleo, equipo }) => textoNovedades(await nucleo.novedades(), equipo) || "Sin novedades del equipo.",
  { conNovedades: false }
);

herramienta(
  "listar_tareas",
  "Lista tareas con filtros opcionales. Por defecto excluye las hechas y canceladas.",
  {
    estado: enumDe(ESTADOS).optional(),
    responsable: miembro.optional(),
    agente: enumDe(AGENTES).optional(),
    prioridad: enumDe(PRIORIDADES).optional(),
    propuestaId: z.string().optional(),
    incluirCerradas: z.boolean().optional(),
  },
  async (f, { nucleo, fs, equipo, yo }) => {
    const responsable = resolverMiembro(f.responsable, equipo, yo);
    const restricciones = f.propuestaId ? [fs.where("propuestaId", "==", f.propuestaId)] : [];
    let tareas = await nucleo.listar("tareas", ...restricciones);
    tareas = tareas.filter(
      (t) =>
        (f.estado ? t.estado === f.estado : f.incluirCerradas || !ESTADOS_CERRADOS.includes(t.estado)) &&
        (!responsable || t.responsable === responsable) &&
        (!f.agente || t.agente === f.agente) &&
        (!f.prioridad || t.prioridad === f.prioridad)
    );
    tareas.sort((a, b) => a.prioridad.localeCompare(b.prioridad) || a.id.localeCompare(b.id));
    return tareas.length ? tareas.map((t) => lineaTarea(t, equipo)).join("\n") : "No hay tareas con esos filtros.";
  }
);

herramienta(
  "ver_tarea",
  "Detalle completo de una tarea: descripción, criterios, bloqueos e historial.",
  { id: z.string().describe("ID de la tarea, p. ej. T-012") },
  async ({ id }, { nucleo, fs, equipo }) => {
    const t = await nucleo.obtener("tareas", id);
    const preguntas = await nucleo.listar("preguntas", fs.where("tareaId", "==", id));
    // El historial incluye lo ocurrido en sus bloqueos (que se registran con el ID de la pregunta).
    const ids = [id, ...preguntas.map((p) => p.id)].slice(0, 30);
    const actividad = await nucleo.listar("actividad", fs.where("entidadId", "in", ids));
    actividad.sort((a, b) => (a.ts?.toMillis() || 0) - (b.ts?.toMillis() || 0));
    return detalleTarea(t, preguntas, actividad.slice(-20), equipo);
  }
);

herramienta(
  "crear_propuesta",
  "Crea una propuesta (un cambio grande que agrupa varias tareas, como 'Combate naval').",
  {
    titulo: z.string(),
    descripcion: z.string().describe("Qué se quiere lograr y por qué."),
    objetivo: z.string().optional().describe("Resultado esperado / definición de terminado."),
    estado: enumDe(ESTADOS_PROPUESTA).optional(),
    actor,
  },
  async (a, { nucleo }) => {
    const id = await nucleo.crearPropuesta(a);
    return `Propuesta creada: ${id} — ${a.titulo}`;
  }
);

herramienta(
  "actualizar_propuesta",
  "Cambia el título, descripción, objetivo o estado de una propuesta.",
  { id: z.string(), titulo: z.string().optional(), descripcion: z.string().optional(), objetivo: z.string().optional(), estado: enumDe(ESTADOS_PROPUESTA).optional(), actor },
  async ({ id, actor: quien, ...cambios }, { nucleo }) => {
    await nucleo.actualizarPropuesta(id, cambios, { actor: quien });
    return `Propuesta ${id} actualizada.`;
  }
);

herramienta(
  "crear_tarea",
  "Crea una tarea en la pizarra.",
  {
    titulo: z.string(),
    descripcion: z.string(),
    tipo: enumDe(TIPOS_TAREA).optional(),
    prioridad: enumDe(PRIORIDADES).describe("P0 crítica, P1 alta, P2 media, P3 baja"),
    agente: enumDe(AGENTES).optional().describe("Agente que debe ejecutarla."),
    responsable: miembro.optional().describe("Persona responsable de la tarea y de resolver sus bloqueos."),
    propuestaId: z.string().optional(),
    dependencias: z.array(z.string()).optional().describe("IDs de tareas que deben terminar antes."),
    criterios: z.array(z.string()).optional().describe("Criterios de aceptación."),
    estado: enumDe(ESTADOS).optional().describe("Por defecto backlog."),
    actor,
  },
  async ({ actor: quien, ...datos }, { nucleo, equipo, yo }) => {
    datos.responsable = resolverMiembro(datos.responsable, equipo, yo);
    const id = await nucleo.crearTarea(datos, { actor: quien });
    return `Tarea creada: ${id} — ${datos.titulo}`;
  }
);

herramienta(
  "actualizar_tarea",
  "Cambia el estado u otros campos de una tarea. Para bloquearla por una decisión humana usa crear_pregunta.",
  {
    id: z.string(),
    estado: enumDe(ESTADOS).optional(),
    prioridad: enumDe(PRIORIDADES).optional(),
    agente: enumDe(AGENTES).optional(),
    responsable: miembro.optional(),
    titulo: z.string().optional(),
    descripcion: z.string().optional(),
    criterios: z.array(z.string()).optional(),
    dependencias: z.array(z.string()).optional(),
    rama: z.string().optional().describe("Rama de git donde se trabaja."),
    nota: z.string().optional().describe("Explicación breve del cambio, queda en el historial."),
    actor,
  },
  async ({ id, actor: quien, nota, ...cambios }, { nucleo, equipo, yo }) => {
    if (cambios.responsable) cambios.responsable = resolverMiembro(cambios.responsable, equipo, yo);
    if (!Object.keys(cambios).length && !nota) throw new Error("No indicaste ningún cambio.");
    if (Object.keys(cambios).length) await nucleo.actualizarTarea(id, cambios, { actor: quien, nota });
    else await nucleo.comentar("tarea", id, nota, { actor: quien });
    return `Tarea ${id} actualizada.`;
  }
);

herramienta(
  "comentar",
  "Agrega un comentario al historial de una tarea, propuesta o decisión.",
  { entidadId: z.string().describe("ID, p. ej. T-012, P-003 o ADR-002"), texto: z.string(), actor },
  async ({ entidadId, texto, actor: quien }, { nucleo }) => {
    const entidad = entidadId.startsWith("ADR") ? "decision" : entidadId.startsWith("P-") ? "propuesta" : "tarea";
    await nucleo.comentar(entidad, entidadId, texto, { actor: quien });
    return `Comentario agregado a ${entidadId}.`;
  }
);

herramienta(
  "crear_pregunta",
  "Registra un bloqueo que debe resolver una persona. Si se liga a una tarea, la tarea queda 'bloqueada' hasta que se responda. No avances la tarea mientras esté bloqueada.",
  {
    pregunta: z.string(),
    dirigidaA: miembro.describe("Persona que debe decidir (según las áreas del equipo)."),
    tareaId: z.string().optional(),
    contexto: z.string().optional().describe("Por qué hace falta decidir y qué implica cada opción."),
    opciones: z.array(z.string()).optional(),
    actor,
  },
  async ({ dirigidaA, actor: quien, ...datos }, { nucleo, equipo, yo }) => {
    const destino = resolverMiembro(dirigidaA, equipo, yo);
    const id = await nucleo.crearPregunta({ ...datos, dirigidaA: destino, actor: quien });
    const paraMi = destino === yo;
    return `Bloqueo registrado: ${id}${datos.tareaId ? ` (tarea ${datos.tareaId} bloqueada)` : ""}. ${
      paraMi ? "Es para la persona con la que hablas: pregúntale en el chat y registra su respuesta con responder_pregunta." : `Es para ${nombreDe(equipo, destino)}; lo verá en la pizarra. Continúa con otras tareas.`
    }`;
  }
);

herramienta(
  "responder_pregunta",
  "Registra la respuesta de una persona a un bloqueo. Si la tarea no tiene más bloqueos, vuelve a su estado anterior.",
  { id: z.string().describe("ID de la pregunta, p. ej. Q-004"), respuesta: z.string(), actor },
  async ({ id, respuesta, actor: quien }, { nucleo }) => {
    const r = await nucleo.responderPregunta(id, respuesta, { actor: quien });
    return `Respuesta registrada en ${id}.${r.desbloqueada ? ` La tarea ${r.tareaId} vuelve a "${ESTADOS[r.desbloqueada]}".` : r.tareaId ? ` ${r.tareaId} sigue con otros bloqueos abiertos.` : ""}`;
  }
);

herramienta(
  "listar_preguntas",
  "Lista los bloqueos (por defecto solo los abiertos).",
  { dirigidaA: miembro.optional(), incluirRespondidas: z.boolean().optional() },
  async ({ dirigidaA, incluirRespondidas }, { nucleo, fs, equipo, yo }) => {
    const destino = resolverMiembro(dirigidaA, equipo, yo);
    let preguntas = await nucleo.listar("preguntas", ...(incluirRespondidas ? [] : [fs.where("estado", "==", "abierta")]));
    if (destino) preguntas = preguntas.filter((p) => p.dirigidaA === destino);
    return preguntas.length
      ? preguntas.map((p) => `${lineaPregunta(p, equipo)} [${p.estado}]${p.respuesta ? ` → ${p.respuesta}` : ""}`).join("\n")
      : "No hay bloqueos.";
  }
);

herramienta(
  "registrar_decision",
  "Registra una decisión de arquitectura, diseño o desarrollo (ADR).",
  {
    titulo: z.string(),
    contexto: z.string().describe("Problema y restricciones."),
    decision: z.string().describe("Qué se decidió."),
    alternativas: z.string().optional().describe("Opciones descartadas y por qué."),
    consecuencias: z.string().optional(),
    area: z.string().optional().describe("arquitectura, diseño, historia, arte, desarrollo..."),
    estado: enumDe(ESTADOS_DECISION).optional().describe("propuesta (por defecto) o aceptada si la persona ya la aprobó."),
    tareaId: z.string().optional(),
    propuestaId: z.string().optional(),
    reemplazaA: z.string().optional().describe("ADR que esta decisión reemplaza."),
    actor,
  },
  async ({ actor: quien, ...datos }, { nucleo }) => {
    const id = await nucleo.registrarDecision(datos, { actor: quien });
    return `Decisión registrada: ${id} — ${datos.titulo}`;
  }
);

herramienta(
  "actualizar_decision",
  "Cambia el estado o contenido de una decisión (p. ej. aceptarla cuando la persona la aprueba).",
  {
    id: z.string(),
    estado: enumDe(ESTADOS_DECISION).optional(),
    titulo: z.string().optional(),
    contexto: z.string().optional(),
    decision: z.string().optional(),
    alternativas: z.string().optional(),
    consecuencias: z.string().optional(),
    actor,
  },
  async ({ id, actor: quien, ...cambios }, { nucleo }) => {
    await nucleo.actualizarDecision(id, cambios, { actor: quien });
    return `Decisión ${id} actualizada.`;
  }
);

herramienta(
  "listar_decisiones",
  "Lista las decisiones (ADR), con filtros opcionales.",
  { estado: enumDe(ESTADOS_DECISION).optional(), area: z.string().optional(), completas: z.boolean().optional().describe("Incluir el texto completo de cada decisión.") },
  async ({ estado, area, completas }, { nucleo }) => {
    let ds = await nucleo.listar("decisiones");
    ds = ds.filter((d) => (!estado || d.estado === estado) && (!area || d.area === area)).sort((a, b) => a.id.localeCompare(b.id));
    if (!ds.length) return "No hay decisiones registradas.";
    return completas ? ds.map(detalleDecision).join("\n\n") : ds.map((d) => `${d.id} [${ESTADOS_DECISION[d.estado]}] ${d.titulo} · ${d.area}`).join("\n");
  }
);

herramienta(
  "ver_decision",
  "Texto completo de una decisión (ADR).",
  { id: z.string() },
  async ({ id }, { nucleo }) => detalleDecision(await nucleo.obtener("decisiones", id))
);

herramienta(
  "listar_propuestas",
  "Lista las propuestas con su avance.",
  { estado: enumDe(ESTADOS_PROPUESTA).optional() },
  async ({ estado }, { nucleo, fs }) => {
    const [propuestas, tareas] = await Promise.all([nucleo.listar("propuestas", ...(estado ? [fs.where("estado", "==", estado)] : [])), nucleo.listar("tareas")]);
    if (!propuestas.length) return "No hay propuestas.";
    return propuestas
      .sort((a, b) => a.id.localeCompare(b.id))
      .map((p) => {
        const suyas = tareas.filter((t) => t.propuestaId === p.id && t.estado !== "cancelada");
        return `${p.id} [${ESTADOS_PROPUESTA[p.estado]}] ${p.titulo} — ${suyas.filter((t) => t.estado === "hecha").length}/${suyas.length} tareas hechas`;
      })
      .join("\n");
  }
);

herramienta(
  "ver_actividad",
  "Historial reciente de actividad del equipo (humanos y agentes).",
  { cantidad: z.number().int().min(1).max(100).optional() },
  async ({ cantidad = 30 }, { nucleo, fs, equipo }) => {
    const act = await nucleo.listar("actividad", fs.orderBy("ts", "desc"), fs.limit(cantidad));
    return act.length ? act.reverse().map((a) => lineaActividad(a, equipo)).join("\n") : "Sin actividad.";
  }
);

herramienta(
  "cerrar_sesion",
  "Guarda el resumen de la conversación para que la próxima sesión (tuya o de tu compañero) sepa qué se hizo. Llamar antes de terminar.",
  {
    resumen: z.string().describe("Una o dos frases."),
    hecho: z.array(z.string()).optional(),
    pendiente: z.array(z.string()).optional(),
    decisiones: z.array(z.string()).optional().describe("IDs o descripción breve de las decisiones tomadas."),
    proximosPasos: z.array(z.string()).optional().describe("Cambios que vienen; se muestran a todo el equipo."),
    actor,
  },
  async (datos, { nucleo }) => {
    const id = await nucleo.registrarSesion({ ...datos, actor: datos.actor || "cronista" });
    return `Sesión guardada: ${id}.`;
  }
);

herramienta(
  "ver_equipo",
  "Miembros del equipo con sus áreas de responsabilidad, y los agentes disponibles.",
  {},
  async (_, { equipo, yo }) => {
    const miembros = Object.entries(equipo).map(([email, m]) => `- ${m.nombre || email} <${email}>${email === yo ? " (tú)" : ""}: ${(m.areas || []).join(", ") || "sin áreas"}`);
    const agentes = Object.entries(AGENTES).map(([k, a]) => `- ${k} (${a.nombre}): ${a.rol}`);
    return ["Personas:", ...(miembros.length ? miembros : ["- (ninguna registrada; usa actualizar_miembro)"]), "", "Agentes:", ...agentes].join("\n");
  }
);

herramienta(
  "actualizar_miembro",
  "Registra o actualiza el nombre y las áreas de responsabilidad de una persona del equipo.",
  { email: z.string(), nombre: z.string().optional(), areas: z.array(z.string()).optional().describe("p. ej. programación, arquitectura, diseño, arte, historia") },
  async ({ email, nombre, areas }, { nucleo }) => {
    await nucleo.guardarMiembro(email.toLowerCase(), { nombre, areas });
    return `Miembro ${email} actualizado.`;
  }
);

await servidor.connect(new StdioServerTransport());
