// Núcleo de la pizarra: modelo de datos y operaciones sobre Firestore.
// Lo comparten la interfaz web (Firestore desde el CDN) y el servidor MCP (Firestore desde npm),
// por eso recibe las funciones de Firestore como parámetro en vez de importarlas.

export const ESTADOS = {
  backlog: "Backlog",
  por_refinar: "Por refinar",
  lista: "Lista",
  en_progreso: "En progreso",
  bloqueada: "Bloqueada",
  en_revision: "En revisión",
  hecha: "Hecha",
  cancelada: "Cancelada",
};
export const ESTADOS_CERRADOS = ["hecha", "cancelada"];

export const PRIORIDADES = {
  P0: "Crítica",
  P1: "Alta",
  P2: "Media",
  P3: "Baja",
};

export const TIPOS_TAREA = {
  feature: "Funcionalidad",
  bug: "Error",
  decision: "Decisión",
  investigacion: "Investigación",
  documentacion: "Documentación",
  arte: "Arte",
  sonido: "Sonido",
};

export const AGENTES = {
  orquestador: { nombre: "Orquestador", rol: "Divide los pedidos en propuestas y tareas, asigna prioridades, agentes y responsables, y detecta bloqueos." },
  arquitecto: { nombre: "Arquitecto", rol: "Define la estructura técnica en Godot y registra las decisiones de arquitectura (ADR)." },
  "game-designer": { nombre: "Game Designer", rol: "Define mecánicas, reglas, balance y progresión; mantiene el documento de diseño (GDD)." },
  historiador: { nombre: "Historiador", rol: "Vela por la fidelidad histórica de la Guerra del Pacífico y registra las licencias creativas." },
  "dev-godot": { nombre: "Desarrollador Godot", rol: "Implementa en GDScript siguiendo las tareas y decisiones aprobadas." },
  qa: { nombre: "QA / Revisor", rol: "Revisa el código, prueba los criterios de aceptación y aprueba o devuelve tareas." },
  cronista: { nombre: "Cronista", rol: "Resume cada sesión, anuncia los próximos cambios y exporta las decisiones a docs/." },
};

export const ESTADOS_PROPUESTA = { borrador: "Borrador", activa: "Activa", completada: "Completada", archivada: "Archivada" };
export const ESTADOS_DECISION = { propuesta: "Propuesta", aceptada: "Aceptada", rechazada: "Rechazada", reemplazada: "Reemplazada" };

const PREFIJOS = { tareas: "T", propuestas: "P", preguntas: "Q", decisiones: "ADR", sesiones: "S" };

const CAMPOS_TAREA = ["titulo", "descripcion", "tipo", "estado", "prioridad", "agente", "responsable", "propuestaId", "dependencias", "criterios", "rama"];
const CAMPOS_PROPUESTA = ["titulo", "descripcion", "objetivo", "estado"];
const CAMPOS_DECISION = ["titulo", "contexto", "decision", "alternativas", "consecuencias", "area", "estado", "tareaId", "propuestaId", "reemplazaA"];

function validar(valor, permitidos, campo) {
  if (valor !== undefined && valor !== null && !(valor in permitidos)) {
    throw new Error(`Valor no válido para ${campo}: "${valor}". Valores permitidos: ${Object.keys(permitidos).join(", ")}`);
  }
}

function soloCampos(datos, campos) {
  const salida = {};
  for (const c of campos) if (datos[c] !== undefined) salida[c] = datos[c];
  return salida;
}

export function crearNucleo(fs, db, usuario) {
  const yo = usuario.email;
  const ref = (col, id) => fs.doc(db, col, id);

  async function registrarActividad({ accion, entidad, entidadId, resumen, actor = null }) {
    await fs.addDoc(fs.collection(db, "actividad"), {
      ts: fs.serverTimestamp(),
      quien: yo,
      actor,
      accion,
      entidad,
      entidadId,
      resumen,
    });
  }

  // Crea un documento con ID legible (T-001, ADR-003...) usando un contador atómico.
  // `antes(tx)` permite hacer lecturas adicionales dentro de la transacción y devolver escrituras extra.
  async function crearConId(col, datos, antes) {
    return fs.runTransaction(db, async (tx) => {
      const contadores = await tx.get(ref("config", "contadores"));
      const extra = antes ? await antes(tx) : null;
      const n = (contadores.exists() ? contadores.data()[col] || 0 : 0) + 1;
      const id = `${PREFIJOS[col]}-${String(n).padStart(3, "0")}`;
      tx.set(ref("config", "contadores"), { [col]: n }, { merge: true });
      tx.set(ref(col, id), { ...datos, id, creadaPor: yo, creadaEn: fs.serverTimestamp(), actualizadaEn: fs.serverTimestamp() });
      if (extra) extra(id);
      return id;
    });
  }

  async function obtener(col, id) {
    const snap = await fs.getDoc(ref(col, id));
    if (!snap.exists()) throw new Error(`No existe ${id} en ${col}`);
    return snap.data();
  }

  async function listar(col, ...restricciones) {
    const snap = await fs.getDocs(fs.query(fs.collection(db, col), ...restricciones));
    return snap.docs.map((d) => d.data());
  }

  async function equipo() {
    const snap = await fs.getDoc(ref("config", "equipo"));
    return snap.exists() ? snap.data().miembros || {} : {};
  }

  return {
    usuario: yo,
    registrarActividad,
    obtener,
    listar,

    async crearPropuesta({ titulo, descripcion = "", objetivo = "", estado = "activa", actor = null }) {
      validar(estado, ESTADOS_PROPUESTA, "estado");
      const id = await crearConId("propuestas", { titulo, descripcion, objetivo, estado });
      await registrarActividad({ accion: "crear", entidad: "propuesta", entidadId: id, resumen: `Nueva propuesta: ${titulo}`, actor });
      return id;
    },

    async actualizarPropuesta(id, cambios, { actor = null } = {}) {
      const datos = soloCampos(cambios, CAMPOS_PROPUESTA);
      validar(datos.estado, ESTADOS_PROPUESTA, "estado");
      await fs.updateDoc(ref("propuestas", id), { ...datos, actualizadaEn: fs.serverTimestamp() });
      await registrarActividad({ accion: "actualizar", entidad: "propuesta", entidadId: id, resumen: describirCambios(datos), actor });
    },

    async crearTarea(datos, { actor = null } = {}) {
      const t = {
        titulo: datos.titulo,
        descripcion: datos.descripcion || "",
        tipo: datos.tipo || "feature",
        estado: datos.estado || "backlog",
        prioridad: datos.prioridad || "P2",
        agente: datos.agente || null,
        responsable: datos.responsable || null,
        propuestaId: datos.propuestaId || null,
        dependencias: datos.dependencias || [],
        criterios: datos.criterios || [],
        rama: datos.rama || null,
        estadoAnterior: null,
        actualizadaPor: yo,
      };
      validar(t.estado, ESTADOS, "estado");
      validar(t.prioridad, PRIORIDADES, "prioridad");
      validar(t.tipo, TIPOS_TAREA, "tipo");
      validar(t.agente, AGENTES, "agente");
      const id = await crearConId("tareas", t);
      await registrarActividad({ accion: "crear", entidad: "tarea", entidadId: id, resumen: `Nueva tarea ${t.prioridad}: ${t.titulo}`, actor });
      return id;
    },

    async actualizarTarea(id, cambios, { actor = null, nota = "" } = {}) {
      const datos = soloCampos(cambios, CAMPOS_TAREA);
      validar(datos.estado, ESTADOS, "estado");
      validar(datos.prioridad, PRIORIDADES, "prioridad");
      validar(datos.tipo, TIPOS_TAREA, "tipo");
      validar(datos.agente, AGENTES, "agente");
      const antes = await fs.runTransaction(db, async (tx) => {
        const snap = await tx.get(ref("tareas", id));
        if (!snap.exists()) throw new Error(`No existe la tarea ${id}`);
        const previa = snap.data();
        const extra = {};
        if (datos.estado === "bloqueada" && previa.estado !== "bloqueada") extra.estadoAnterior = previa.estado;
        if (datos.estado && datos.estado !== "bloqueada") extra.estadoAnterior = null;
        tx.update(snap.ref, { ...datos, ...extra, actualizadaPor: yo, actualizadaEn: fs.serverTimestamp() });
        return previa;
      });
      let resumen = describirCambios(datos, antes);
      if (nota) resumen += ` — ${nota}`;
      await registrarActividad({ accion: datos.estado ? "estado" : "actualizar", entidad: "tarea", entidadId: id, resumen, actor });
    },

    async comentar(entidad, entidadId, texto, { actor = null } = {}) {
      await registrarActividad({ accion: "comentario", entidad, entidadId, resumen: texto, actor });
    },

    // Registra un bloqueo que debe resolver una persona; si va ligado a una tarea, la deja bloqueada.
    async crearPregunta({ tareaId = null, pregunta, contexto = "", opciones = [], dirigidaA, actor = null }) {
      let previa = null;
      const id = await crearConId(
        "preguntas",
        { tareaId, pregunta, contexto, opciones, dirigidaA, actor, estado: "abierta", respuesta: null, respondidaPor: null, respondidaEn: null },
        tareaId
          ? async (tx) => {
              const snap = await tx.get(ref("tareas", tareaId));
              if (!snap.exists()) throw new Error(`No existe la tarea ${tareaId}`);
              previa = snap.data();
              return () => {
                if (previa.estado !== "bloqueada") {
                  tx.update(snap.ref, { estado: "bloqueada", estadoAnterior: previa.estado, actualizadaPor: yo, actualizadaEn: fs.serverTimestamp() });
                }
              };
            }
          : null
      );
      const miembros = await equipo();
      const destino = miembros[dirigidaA]?.nombre || dirigidaA.split("@")[0];
      await registrarActividad({
        accion: "pregunta",
        entidad: "pregunta",
        entidadId: id,
        resumen: `${tareaId ? `[${tareaId}] ` : ""}Bloqueo para ${destino}: ${pregunta}`,
        actor,
      });
      return id;
    },

    // Responde un bloqueo. Si la tarea ya no tiene más bloqueos abiertos, vuelve a su estado anterior.
    async responderPregunta(id, respuesta, { actor = null } = {}) {
      const p = await obtener("preguntas", id);
      if (p.estado !== "abierta") throw new Error(`La pregunta ${id} ya fue respondida`);
      let otrasAbiertas = 0;
      if (p.tareaId) {
        const abiertas = await listar("preguntas", fs.where("tareaId", "==", p.tareaId), fs.where("estado", "==", "abierta"));
        otrasAbiertas = abiertas.filter((q) => q.id !== id).length;
      }
      let desbloqueada = null;
      await fs.runTransaction(db, async (tx) => {
        const tareaSnap = p.tareaId ? await tx.get(ref("tareas", p.tareaId)) : null;
        tx.update(ref("preguntas", id), { estado: "respondida", respuesta, respondidaPor: yo, respondidaEn: fs.serverTimestamp(), actualizadaEn: fs.serverTimestamp() });
        if (tareaSnap?.exists() && otrasAbiertas === 0 && tareaSnap.data().estado === "bloqueada") {
          desbloqueada = tareaSnap.data().estadoAnterior || "lista";
          tx.update(tareaSnap.ref, { estado: desbloqueada, estadoAnterior: null, actualizadaPor: yo, actualizadaEn: fs.serverTimestamp() });
        }
      });
      await registrarActividad({
        accion: "respuesta",
        entidad: "pregunta",
        entidadId: id,
        resumen: `Respuesta a "${p.pregunta}": ${respuesta}${desbloqueada ? ` (${p.tareaId} vuelve a ${ESTADOS[desbloqueada]})` : ""}`,
        actor,
      });
      return { tareaId: p.tareaId, desbloqueada };
    },

    async registrarDecision(datos, { actor = null } = {}) {
      const d = {
        titulo: datos.titulo,
        contexto: datos.contexto || "",
        decision: datos.decision || "",
        alternativas: datos.alternativas || "",
        consecuencias: datos.consecuencias || "",
        area: datos.area || "general",
        estado: datos.estado || "propuesta",
        tareaId: datos.tareaId || null,
        propuestaId: datos.propuestaId || null,
        reemplazaA: datos.reemplazaA || null,
        actor,
      };
      validar(d.estado, ESTADOS_DECISION, "estado");
      const id = await crearConId("decisiones", d);
      if (d.reemplazaA) {
        await fs.updateDoc(ref("decisiones", d.reemplazaA), { estado: "reemplazada", actualizadaEn: fs.serverTimestamp() });
      }
      await registrarActividad({ accion: "crear", entidad: "decision", entidadId: id, resumen: `${ESTADOS_DECISION[d.estado]}: ${d.titulo}`, actor });
      return id;
    },

    async actualizarDecision(id, cambios, { actor = null } = {}) {
      const datos = soloCampos(cambios, CAMPOS_DECISION);
      validar(datos.estado, ESTADOS_DECISION, "estado");
      await fs.updateDoc(ref("decisiones", id), { ...datos, actualizadaEn: fs.serverTimestamp() });
      await registrarActividad({ accion: "actualizar", entidad: "decision", entidadId: id, resumen: describirCambios(datos), actor });
    },

    async registrarSesion({ resumen, hecho = [], pendiente = [], decisiones = [], proximosPasos = [], actor = "cronista" }) {
      const id = await crearConId("sesiones", { resumen, hecho, pendiente, decisiones, proximosPasos, actor });
      await registrarActividad({ accion: "sesion", entidad: "sesion", entidadId: id, resumen: `Sesión cerrada: ${resumen}`, actor });
      return id;
    },

    async guardarMiembro(email, { nombre, areas }) {
      const cambios = {};
      if (nombre !== undefined) cambios.nombre = nombre;
      if (areas !== undefined) cambios.areas = areas;
      await fs.setDoc(ref("config", "equipo"), { miembros: { [email]: cambios } }, { merge: true });
      await registrarActividad({ accion: "equipo", entidad: "miembro", entidadId: email, resumen: `Equipo actualizado: ${email} ${describirCambios(cambios)}` });
    },

    equipo,

    // Cambios hechos por otras personas desde la última consulta de este usuario.
    async novedades({ marcar = true, maximo = 30 } = {}) {
      const lectura = await fs.getDoc(ref("lecturas", yo));
      const desde = lectura.exists() ? lectura.data().ultima : null;
      const restricciones = [fs.orderBy("ts", "desc"), fs.limit(maximo)];
      if (desde) restricciones.unshift(fs.where("ts", ">", desde));
      const recientes = (await listar("actividad", ...restricciones)).filter((a) => a.ts);
      if (marcar && recientes.length) {
        await fs.setDoc(ref("lecturas", yo), { ultima: recientes[0].ts }, { merge: true });
      } else if (marcar && !desde) {
        await fs.setDoc(ref("lecturas", yo), { ultima: fs.serverTimestamp() }, { merge: true });
      }
      return { primeraVez: !desde, cambios: recientes.filter((a) => a.quien !== yo).reverse() };
    },
  };
}

function describirCambios(datos, antes = {}) {
  return Object.entries(datos)
    .map(([k, v]) => {
      const valor = Array.isArray(v) ? v.join(", ") : v;
      if (k === "estado" && antes.estado) return `estado: ${ESTADOS[antes.estado] || antes.estado} → ${ESTADOS[v] || v}`;
      if (k === "descripcion" || k === "contexto" || k === "decision") return `${k} actualizada`;
      return `${k}: ${valor ?? "—"}`;
    })
    .join("; ");
}
