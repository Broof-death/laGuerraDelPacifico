// Interfaz web de la pizarra: se suscribe a Firestore y se actualiza en tiempo real.
import { initializeApp } from "https://www.gstatic.com/firebasejs/12.19.0/firebase-app.js";
import {
  getAuth,
  onAuthStateChanged,
  signInWithEmailAndPassword,
  sendPasswordResetEmail,
  signOut,
  connectAuthEmulator,
} from "https://www.gstatic.com/firebasejs/12.19.0/firebase-auth.js";
import * as fs from "https://www.gstatic.com/firebasejs/12.19.0/firebase-firestore.js";
import { firebaseConfig, configEmulador, EMULADOR, estaConfigurado } from "./config.js";
import {
  crearNucleo,
  ESTADOS,
  ESTADOS_CERRADOS,
  PRIORIDADES,
  TIPOS_TAREA,
  AGENTES,
  ESTADOS_PROPUESTA,
  ESTADOS_DECISION,
} from "./nucleo.js";

const usaEmulador = new URLSearchParams(location.search).has("emulador") || location.port === "5055";
const raiz = document.getElementById("raiz");
const dialogo = document.getElementById("dialogo");

if (!usaEmulador && !estaConfigurado(firebaseConfig)) {
  raiz.innerHTML = `<div class="acceso"><div class="tarjeta"><h1>Falta configurar Firebase</h1>
    <p class="suave">Completa <code>web/config.js</code> con la configuración de tu proyecto (ver <code>tools/pizarra/README.md</code>).
    Para probar sin Firebase, abre esta página con <code>?emulador</code> mientras corre <code>npm run emulador</code>.</p></div></div>`;
  throw new Error("Firebase sin configurar");
}

const app = initializeApp(usaEmulador ? configEmulador : firebaseConfig);
const auth = getAuth(app);
const db = fs.getFirestore(app);
if (usaEmulador) {
  connectAuthEmulator(auth, EMULADOR.auth, { disableWarnings: true });
  fs.connectFirestoreEmulator(db, EMULADOR.firestoreHost, EMULADOR.firestorePuerto);
}

const VISTAS = {
  inicio: "Cómo vamos",
  tablero: "Tablero",
  bloqueos: "Por resolver",
  propuestas: "Propuestas",
  decisiones: "Decisiones",
  actividad: "Actividad",
  sesiones: "Bitácora",
  equipo: "Equipo",
};

const estado = {
  usuario: null,
  nucleo: null,
  datos: { tareas: [], preguntas: [], propuestas: [], decisiones: [], actividad: [], sesiones: [], equipo: {} },
  cargado: new Set(),
  vista: leerVista(),
  filtros: { texto: "", responsable: "", agente: "", prioridad: "", propuestaId: "", canceladas: false },
  pestanaBloqueos: "mios",
  filtroDecisiones: "",
  tareaAbierta: null,
  borradores: {},
  desuscribir: [],
};

// ---------- utilidades ----------

const esc = (s) =>
  String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

function nombre(email) {
  if (!email) return "Sin responsable";
  return estado.datos.equipo[email]?.nombre || email.split("@")[0];
}

function iniciales(email) {
  if (!email) return "—";
  return nombre(email)
    .split(/\s+/)
    .map((p) => p[0])
    .join("")
    .slice(0, 2)
    .toUpperCase();
}

function quienHizo(a) {
  const persona = nombre(a.quien);
  return a.actor ? `${esc(AGENTES[a.actor]?.nombre || a.actor)} <span class="suave">· Claude de ${esc(persona)}</span>` : esc(persona);
}

function hace(ts) {
  if (!ts?.toDate) return "ahora";
  const seg = (Date.now() - ts.toDate().getTime()) / 1000;
  if (seg < 60) return "hace un momento";
  if (seg < 3600) return `hace ${Math.floor(seg / 60)} min`;
  if (seg < 86400) return `hace ${Math.floor(seg / 3600)} h`;
  if (seg < 86400 * 7) return `hace ${Math.floor(seg / 86400)} d`;
  return ts.toDate().toLocaleDateString("es-CL", { day: "numeric", month: "short" });
}

function fechaCompleta(ts) {
  return ts?.toDate ? ts.toDate().toLocaleString("es-CL", { dateStyle: "medium", timeStyle: "short" }) : "";
}

const chip = (clase, texto) => `<span class="chip chip-${esc(clase)}">${esc(texto)}</span>`;
const chipEstado = (e) => chip(e, ESTADOS[e] || e);
const chipPrioridad = (p) => chip(p, p);
const avatar = (email) => `<span class="avatar" title="${esc(nombre(email))}">${esc(iniciales(email))}</span>`;
const opciones = (mapa, actual, vacio) =>
  (vacio !== undefined ? `<option value="">${esc(vacio)}</option>` : "") +
  Object.entries(mapa)
    .map(([k, v]) => `<option value="${esc(k)}" ${k === (actual ?? "") ? "selected" : ""}>${esc(typeof v === "string" ? v : v.nombre)}</option>`)
    .join("");
const opcionesMiembros = (actual, vacio = "Sin responsable") =>
  opciones(Object.fromEntries(Object.entries(estado.datos.equipo).map(([e, m]) => [e, m.nombre || e])), actual, vacio);

function avisar(texto) {
  const el = document.createElement("div");
  el.className = "aviso";
  el.innerHTML = texto;
  document.getElementById("avisos").append(el);
  setTimeout(() => el.remove(), 6000);
}

async function intentar(fn) {
  try {
    await fn();
  } catch (e) {
    console.error(e);
    avisar(`No se pudo guardar: ${esc(e.message)}`);
  }
}

function leerVista() {
  const v = location.hash.slice(1);
  return v in VISTAS ? v : "inicio";
}

// No repinta una zona mientras la persona está escribiendo en ella.
function pintar(el, html) {
  if (!el) return;
  const activo = document.activeElement;
  if (activo && el.contains(activo) && /^(INPUT|TEXTAREA|SELECT)$/.test(activo.tagName)) {
    el.dataset.pendiente = "1";
    return;
  }
  delete el.dataset.pendiente;
  el.innerHTML = html;
}
document.addEventListener("focusout", () =>
  setTimeout(() => {
    if (document.querySelector("[data-pendiente]")) renderizar();
  }, 0)
);

const misPreguntas = () => estado.datos.preguntas.filter((p) => p.estado === "abierta" && p.dirigidaA === estado.usuario.email);
const tarea = (id) => estado.datos.tareas.find((t) => t.id === id);

// ---------- acceso ----------

function pantallaAcceso(error = "") {
  raiz.innerHTML = `<div class="acceso"><form class="tarjeta" id="form-acceso">
    <div><h1>Pizarra</h1><p class="suave">La Guerra del Pacífico${usaEmulador ? " · <strong>emulador local</strong>" : ""}</p></div>
    <label class="campo">Correo<input name="email" type="email" autocomplete="username" required /></label>
    <label class="campo">Contraseña<input name="clave" type="password" autocomplete="current-password" required /></label>
    ${error ? `<p class="error">${esc(error)}</p>` : ""}
    <button class="boton boton-primario" type="submit">Entrar</button>
    <button class="boton-texto chico" type="button" id="olvide">Olvidé mi contraseña</button>
  </form></div>`;
  const form = document.getElementById("form-acceso");
  form.addEventListener("submit", async (ev) => {
    ev.preventDefault();
    const datos = new FormData(form);
    try {
      await signInWithEmailAndPassword(auth, datos.get("email"), datos.get("clave"));
    } catch (e) {
      pantallaAcceso(e.code === "auth/invalid-credential" ? "Correo o contraseña incorrectos." : e.message);
    }
  });
  document.getElementById("olvide").addEventListener("click", async () => {
    const email = form.email.value;
    if (!email) return pantallaAcceso("Escribe tu correo y vuelve a presionar «Olvidé mi contraseña».");
    await sendPasswordResetEmail(auth, email).catch(() => {});
    avisar("Si el correo está registrado, te llegó un enlace para crear una nueva contraseña.");
  });
}

onAuthStateChanged(auth, (usuario) => {
  estado.desuscribir.forEach((f) => f());
  estado.desuscribir = [];
  estado.cargado = new Set();
  if (!usuario) {
    estado.usuario = null;
    return pantallaAcceso();
  }
  estado.usuario = usuario;
  estado.nucleo = crearNucleo(fs, db, { email: usuario.email });
  montar();
  suscribir();
});

// ---------- datos en tiempo real ----------

function suscribir() {
  const escuchar = (clave, consulta, transformar = (s) => s.docs.map((d) => d.data())) => {
    const quitar = fs.onSnapshot(
      consulta,
      (snap) => {
        if (clave === "actividad" && estado.cargado.has("actividad")) anunciarCambios(snap);
        estado.datos[clave] = transformar(snap);
        estado.cargado.add(clave);
        renderizar();
      },
      (error) => {
        console.error(error);
        if (error.code === "permission-denied") {
          raiz.innerHTML = `<div class="acceso"><div class="tarjeta"><h1>Sin acceso</h1>
            <p class="suave">${esc(estado.usuario.email)} no está en la lista de miembros de la pizarra. Pide que agreguen tu correo en <code>firestore.rules</code>.</p>
            <button class="boton" data-accion="salir">Salir</button></div></div>`;
        }
      }
    );
    estado.desuscribir.push(quitar);
  };
  const col = (n) => fs.collection(db, n);
  escuchar("tareas", col("tareas"));
  escuchar("preguntas", col("preguntas"));
  escuchar("propuestas", col("propuestas"));
  escuchar("decisiones", col("decisiones"));
  escuchar("actividad", fs.query(col("actividad"), fs.orderBy("ts", "desc"), fs.limit(200)));
  escuchar("sesiones", fs.query(col("sesiones"), fs.orderBy("creadaEn", "desc"), fs.limit(50)));
  escuchar("equipo", fs.doc(db, "config", "equipo"), (snap) => (snap.exists() ? snap.data().miembros || {} : {}));
}

function anunciarCambios(snap) {
  for (const cambio of snap.docChanges()) {
    const a = cambio.doc.data();
    if (cambio.type === "added" && a.quien !== estado.usuario.email && !cambio.doc.metadata.hasPendingWrites) {
      avisar(`<strong>${quienHizo(a)}</strong><br>${esc(a.entidadId)}: ${esc(a.resumen)}`);
    }
  }
}

// ---------- estructura ----------

function montar() {
  raiz.innerHTML = `<div class="app">
    <nav class="lateral" aria-label="Secciones">
      <div class="marca"><strong>Pizarra</strong><span>La Guerra del Pacífico</span></div>
      <div id="nav"></div>
      <div class="lateral-pie">
        <div class="fila">${avatar(estado.usuario.email)} <span id="mi-nombre"></span></div>
        <div class="fila">
          <button class="boton boton-chico" data-accion="tema">Tema</button>
          <button class="boton boton-chico" data-accion="salir">Salir</button>
        </div>
        ${usaEmulador ? '<span class="chip chip-en_revision">Emulador local</span>' : ""}
      </div>
    </nav>
    <main class="principal">
      <div class="encabezado" id="encabezado"></div>
      <div id="barra"></div>
      <div id="contenido"></div>
    </main>
  </div>
  <div class="velo" id="velo" hidden data-accion="cerrar-panel"></div>
  <aside class="panel" id="panel" hidden aria-label="Detalle de la tarea"></aside>`;
  renderizarBarra();
  renderizar();
}

window.addEventListener("hashchange", () => {
  estado.vista = leerVista();
  renderizarBarra();
  renderizar();
});

function renderizar() {
  if (!document.getElementById("contenido")) return;
  const pendientes = misPreguntas().length;
  document.title = `${pendientes ? `(${pendientes}) ` : ""}Pizarra · La Guerra del Pacífico`;
  pintar(
    document.getElementById("nav"),
    Object.entries(VISTAS)
      .map(([v, t]) => {
        const insignia = v === "bloqueos" && pendientes ? `<span class="insignia">${pendientes}</span>` : "";
        return `<button class="nav-boton" data-ir="${v}" ${estado.vista === v ? 'aria-current="page"' : ""}>${t}${insignia}</button>`;
      })
      .join("")
  );
  document.getElementById("mi-nombre").textContent = nombre(estado.usuario.email);
  pintar(document.getElementById("encabezado"), encabezado());
  if (estado.cargado.size < 7) {
    pintar(document.getElementById("contenido"), '<p class="vacio">Cargando…</p>');
    return;
  }
  const vistas = { inicio: vistaInicio, tablero: vistaTablero, bloqueos: vistaBloqueos, propuestas: vistaPropuestas, decisiones: vistaDecisiones, actividad: vistaActividad, sesiones: vistaSesiones, equipo: vistaEquipo };
  pintar(document.getElementById("contenido"), vistas[estado.vista]());
  if (estado.tareaAbierta) pintar(document.getElementById("panel"), panelTarea(estado.tareaAbierta));
}

function encabezado() {
  const subtitulos = {
    inicio: `Hola, ${esc(nombre(estado.usuario.email))}. Este es el estado del proyecto ahora mismo.`,
    tablero: "Todas las tareas por estado. Arrastra una tarjeta para moverla o ábrela para ver el detalle.",
    bloqueos: "Preguntas que los agentes no pueden decidir solos. La tarea queda detenida hasta que alguien responda.",
    propuestas: "Cambios grandes que agrupan varias tareas.",
    decisiones: "Decisiones de arquitectura, diseño y desarrollo (ADR). Las propuestas esperan tu aprobación.",
    actividad: "Todo lo que hicieron las personas y los agentes, en orden.",
    sesiones: "Resumen de cada conversación con Claude y lo que viene.",
    equipo: "Personas, sus áreas de responsabilidad y los agentes disponibles.",
  };
  const acciones = {
    tablero: '<button class="boton boton-primario" data-accion="nueva-tarea">Nueva tarea</button>',
    propuestas: '<button class="boton boton-primario" data-accion="nueva-propuesta">Nueva propuesta</button>',
    inicio: '<button class="boton" data-accion="nueva-tarea">Nueva tarea</button>',
  };
  return `<div><h1>${VISTAS[estado.vista]}</h1><p>${subtitulos[estado.vista]}</p></div>${acciones[estado.vista] || ""}`;
}

function renderizarBarra() {
  const barra = document.getElementById("barra");
  if (!barra) return;
  if (estado.vista !== "tablero") return (barra.innerHTML = "");
  const f = estado.filtros;
  barra.innerHTML = `<div class="filtros">
    <input class="control buscar" type="search" placeholder="Buscar por título o ID" data-filtro="texto" value="${esc(f.texto)}" aria-label="Buscar" />
    <select class="control" data-filtro="responsable" aria-label="Responsable"></select>
    <select class="control" data-filtro="agente" aria-label="Agente">${opciones(AGENTES, f.agente, "Todos los agentes")}</select>
    <select class="control" data-filtro="prioridad" aria-label="Prioridad">${opciones(PRIORIDADES, f.prioridad, "Toda prioridad")}</select>
    <select class="control" data-filtro="propuestaId" aria-label="Propuesta"></select>
    <label class="fila chico suave"><input type="checkbox" data-filtro="canceladas" ${f.canceladas ? "checked" : ""}/> Canceladas</label>
  </div>`;
  refrescarFiltrosDinamicos();
}

// Los filtros que dependen de los datos (personas y propuestas) se actualizan sin perder lo escrito en la búsqueda.
function refrescarFiltrosDinamicos() {
  const resp = document.querySelector('[data-filtro="responsable"]');
  const prop = document.querySelector('[data-filtro="propuestaId"]');
  if (resp && document.activeElement !== resp) resp.innerHTML = opcionesMiembros(estado.filtros.responsable, "Todas las personas");
  if (prop && document.activeElement !== prop)
    prop.innerHTML = opciones(Object.fromEntries(estado.datos.propuestas.map((p) => [p.id, `${p.id} · ${p.titulo}`])), estado.filtros.propuestaId, "Todas las propuestas");
}

// ---------- vistas ----------

function tarjetaTarea(t) {
  const bloqueos = estado.datos.preguntas.filter((p) => p.tareaId === t.id && p.estado === "abierta").length;
  return `<article class="tarjeta tarjeta-tarea" draggable="true" data-tarea="${esc(t.id)}" data-prioridad="${esc(t.prioridad)}">
    <div class="fila"><span class="id">${esc(t.id)}</span>${chipPrioridad(t.prioridad)}${bloqueos ? chip("bloqueada", `${bloqueos} bloqueo${bloqueos > 1 ? "s" : ""}`) : ""}</div>
    <div class="titulo">${esc(t.titulo)}</div>
    <div class="meta"><span>${esc(AGENTES[t.agente]?.nombre || "Sin agente")}${t.propuestaId ? ` · ${esc(t.propuestaId)}` : ""}</span>${avatar(t.responsable)}</div>
  </article>`;
}

function filaTarea(t) {
  return `<li class="fila" style="justify-content:space-between"><button class="boton-texto" data-tarea="${esc(t.id)}"><span class="id">${esc(t.id)}</span> ${esc(t.titulo)}</button><span class="fila">${chipPrioridad(t.prioridad)}${chipEstado(t.estado)}</span></li>`;
}

function avancePropuesta(p) {
  const suyas = estado.datos.tareas.filter((t) => t.propuestaId === p.id && t.estado !== "cancelada");
  const hechas = suyas.filter((t) => t.estado === "hecha").length;
  return { suyas, hechas, pct: suyas.length ? Math.round((hechas / suyas.length) * 100) : 0 };
}

function vistaInicio() {
  const { tareas, preguntas, propuestas, sesiones, actividad } = estado.datos;
  const activas = tareas.filter((t) => !ESTADOS_CERRADOS.includes(t.estado));
  const semana = Date.now() - 7 * 86400000;
  const hechasSemana = tareas.filter((t) => t.estado === "hecha" && t.actualizadaEn?.toMillis() > semana).length;
  const abiertas = preguntas.filter((p) => p.estado === "abierta");
  const mias = misPreguntas();
  const ultima = sesiones[0];
  const enCurso = activas.filter((t) => t.estado === "en_progreso" || t.estado === "en_revision").sort((a, b) => a.prioridad.localeCompare(b.prioridad));
  const misTareas = activas.filter((t) => t.responsable === estado.usuario.email).sort((a, b) => a.prioridad.localeCompare(b.prioridad));

  return `<div class="kpis">
    <div class="tarjeta kpi"><strong>${activas.length}</strong><span>tareas activas</span></div>
    <div class="tarjeta kpi"><strong>${activas.filter((t) => t.estado === "en_progreso").length}</strong><span>en progreso</span></div>
    <div class="tarjeta kpi ${abiertas.length ? "kpi-alerta" : ""}"><strong>${abiertas.length}</strong><span>bloqueos abiertos (${mias.length} tuyos)</span></div>
    <div class="tarjeta kpi"><strong>${hechasSemana}</strong><span>hechas en los últimos 7 días</span></div>
  </div>
  <div class="rejilla-inicio">
    <div class="pila">
      <section class="tarjeta seccion"><h2>Te toca resolver</h2>
        ${mias.length ? `<ul class="lista-limpia">${mias.map((p) => `<li class="bloqueo"><strong>${esc(p.pregunta)}</strong><span class="chico suave">${p.tareaId ? `${esc(p.tareaId)} · ` : ""}de ${quienHizo({ quien: p.creadaPor, actor: p.actor })} · ${hace(p.creadaEn)}</span></li>`).join("")}</ul>
          <p><button class="boton boton-primario" data-ir="bloqueos">Responder</button></p>` : '<p class="vacio">Nada pendiente para ti.</p>'}
      </section>
      <section class="tarjeta seccion"><h2>Propuestas activas</h2>
        ${propuestas.filter((p) => p.estado === "activa").map((p) => {
          const a = avancePropuesta(p);
          return `<div class="pila" style="gap:6px;margin-bottom:14px"><div class="fila" style="justify-content:space-between"><button class="boton-texto" data-propuesta="${esc(p.id)}"><strong>${esc(p.titulo)}</strong></button><span class="chico suave">${a.hechas}/${a.suyas.length} tareas · ${a.pct}%</span></div><div class="barra-progreso"><span style="width:${a.pct}%"></span></div></div>`;
        }).join("") || '<p class="vacio">No hay propuestas activas.</p>'}
      </section>
      <section class="tarjeta seccion"><h2>En curso</h2>
        ${enCurso.length ? `<ul class="lista-limpia">${enCurso.map(filaTarea).join("")}</ul>` : '<p class="vacio">Nadie está trabajando en una tarea ahora.</p>'}
      </section>
      <section class="tarjeta seccion"><h2>Tus tareas</h2>
        ${misTareas.length ? `<ul class="lista-limpia">${misTareas.slice(0, 10).map(filaTarea).join("")}</ul>` : '<p class="vacio">No tienes tareas asignadas.</p>'}
      </section>
    </div>
    <div class="pila">
      <section class="tarjeta seccion"><h2>Lo que viene</h2>
        ${ultima ? `<p class="chico suave">Última sesión · ${esc(nombre(ultima.creadaPor))} · ${hace(ultima.creadaEn)}</p><p>${esc(ultima.resumen)}</p>
          ${ultima.proximosPasos?.length ? `<ul>${ultima.proximosPasos.map((x) => `<li>${esc(x)}</li>`).join("")}</ul>` : ""}
          <button class="boton-texto chico" data-ir="sesiones">Ver bitácora</button>` : '<p class="vacio">Todavía no hay sesiones registradas.</p>'}
      </section>
      <section class="tarjeta seccion"><h2>Actividad reciente</h2>
        ${actividad.slice(0, 8).map(evento).join("") || '<p class="vacio">Sin actividad.</p>'}
        <button class="boton-texto chico" data-ir="actividad">Ver toda la actividad</button>
      </section>
    </div>
  </div>`;
}

function evento(a) {
  const enlace = /^T-/.test(a.entidadId) ? `<button class="boton-texto" data-tarea="${esc(a.entidadId)}">${esc(a.entidadId)}</button>` : `<span class="id">${esc(a.entidadId)}</span>`;
  return `<div class="evento">${avatar(a.quien)}<div><p class="chico">${quienHizo(a)} · <time title="${esc(fechaCompleta(a.ts))}">${hace(a.ts)}</time></p><p>${enlace} ${esc(a.resumen)}</p></div></div>`;
}

function tareasFiltradas() {
  const f = estado.filtros;
  const texto = f.texto.trim().toLowerCase();
  return estado.datos.tareas.filter(
    (t) =>
      (!texto || t.titulo.toLowerCase().includes(texto) || t.id.toLowerCase().includes(texto)) &&
      (!f.responsable || t.responsable === f.responsable) &&
      (!f.agente || t.agente === f.agente) &&
      (!f.prioridad || t.prioridad === f.prioridad) &&
      (!f.propuestaId || t.propuestaId === f.propuestaId)
  );
}

function vistaTablero() {
  refrescarFiltrosDinamicos();
  const tareas = tareasFiltradas();
  const columnas = Object.keys(ESTADOS).filter((e) => e !== "cancelada" || estado.filtros.canceladas);
  return `<div class="tablero">${columnas
    .map((e) => {
      const suyas = tareas.filter((t) => t.estado === e).sort((a, b) => a.prioridad.localeCompare(b.prioridad) || a.id.localeCompare(b.id));
      return `<section class="columna columna-${e}" data-columna="${e}" aria-label="${ESTADOS[e]}"><div class="columna-titulo"><span>${ESTADOS[e]}</span><span class="chip">${suyas.length}</span></div>${suyas.map(tarjetaTarea).join("")}</section>`;
    })
    .join("")}</div>`;
}

function tarjetaBloqueo(p) {
  const t = p.tareaId ? tarea(p.tareaId) : null;
  const abierta = p.estado === "abierta";
  return `<article class="bloqueo ${abierta ? "" : "respondido"}">
    <div class="fila" style="justify-content:space-between"><span class="fila"><span class="id">${esc(p.id)}</span>${t ? `<button class="boton-texto chico" data-tarea="${esc(t.id)}">${esc(t.id)} · ${esc(t.titulo)}</button>` : ""}</span><span class="chico suave">para ${esc(nombre(p.dirigidaA))}</span></div>
    <strong>${esc(p.pregunta)}</strong>
    ${p.contexto ? `<p class="texto-largo chico suave">${esc(p.contexto)}</p>` : ""}
    <p class="chico suave" style="margin:0">Planteada por ${quienHizo({ quien: p.creadaPor, actor: p.actor })} · ${hace(p.creadaEn)}</p>
    ${abierta ? formularioRespuesta(p) : `<p style="margin:0"><strong>Respuesta:</strong> ${esc(p.respuesta)} <span class="chico suave">— ${esc(nombre(p.respondidaPor))}, ${hace(p.respondidaEn)}</span></p>`}
  </article>`;
}

function formularioRespuesta(p) {
  return `<form class="pila" style="gap:8px" data-responder="${esc(p.id)}">
    ${p.opciones?.length ? `<div class="fila">${p.opciones.map((o) => `<button type="button" class="boton boton-chico" data-opcion="${esc(o)}">${esc(o)}</button>`).join("")}</div>` : ""}
    <textarea class="control" name="respuesta" data-borrador="${esc(p.id)}" placeholder="Tu respuesta o decisión" required>${esc(estado.borradores[p.id] || "")}</textarea>
    <div class="acciones"><button class="boton boton-primario" type="submit">Responder</button></div>
  </form>`;
}

function vistaBloqueos() {
  const todas = estado.datos.preguntas;
  const pestanas = {
    mios: ["Para mí", misPreguntas()],
    abiertos: ["Todos los abiertos", todas.filter((p) => p.estado === "abierta")],
    respondidos: ["Respondidos", todas.filter((p) => p.estado === "respondida").sort((a, b) => (b.respondidaEn?.toMillis() || 0) - (a.respondidaEn?.toMillis() || 0))],
  };
  const [, lista] = pestanas[estado.pestanaBloqueos];
  return `<div class="pestanas" role="tablist">${Object.entries(pestanas)
    .map(([k, [t, l]]) => `<button class="pestana" role="tab" aria-selected="${estado.pestanaBloqueos === k}" data-pestana="${k}">${t} (${l.length})</button>`)
    .join("")}</div>
    <div class="pila">${lista.map(tarjetaBloqueo).join("") || '<p class="vacio">No hay nada aquí.</p>'}</div>`;
}

function vistaPropuestas() {
  const ps = [...estado.datos.propuestas].sort((a, b) => b.id.localeCompare(a.id));
  if (!ps.length) return '<p class="vacio">Aún no hay propuestas. Pídele a Claude algo como «quiero implementar el combate naval» y el Orquestador creará una.</p>';
  return `<div class="pila">${ps
    .map((p) => {
      const a = avancePropuesta(p);
      const porEstado = Object.keys(ESTADOS)
        .map((e) => [e, a.suyas.filter((t) => t.estado === e).length])
        .filter(([, n]) => n)
        .map(([e, n]) => chip(e, `${ESTADOS[e]}: ${n}`))
        .join("");
      return `<section class="tarjeta seccion pila" style="gap:10px">
        <div class="fila" style="justify-content:space-between"><div class="fila"><span class="id">${esc(p.id)}</span><h2>${esc(p.titulo)}</h2>${chip(p.estado, ESTADOS_PROPUESTA[p.estado])}</div>
          <select class="control" style="width:auto" data-propuesta-estado="${esc(p.id)}" aria-label="Estado de la propuesta">${opciones(ESTADOS_PROPUESTA, p.estado)}</select></div>
        ${p.descripcion ? `<p class="texto-largo" style="margin:0">${esc(p.descripcion)}</p>` : ""}
        ${p.objetivo ? `<p class="chico" style="margin:0"><strong>Objetivo:</strong> ${esc(p.objetivo)}</p>` : ""}
        <div class="barra-progreso"><span style="width:${a.pct}%"></span></div>
        <div class="fila">${porEstado || '<span class="chico suave">Sin tareas</span>'}<button class="boton-texto chico" data-propuesta="${esc(p.id)}">Ver en el tablero</button></div>
      </section>`;
    })
    .join("")}</div>`;
}

function vistaDecisiones() {
  const ds = estado.datos.decisiones.filter((d) => !estado.filtroDecisiones || d.estado === estado.filtroDecisiones).sort((a, b) => b.id.localeCompare(a.id));
  const filtro = `<div class="filtros"><select class="control" data-filtro-decisiones aria-label="Estado">${opciones(ESTADOS_DECISION, estado.filtroDecisiones, "Todos los estados")}</select></div>`;
  if (!ds.length) return `${filtro}<p class="vacio">No hay decisiones registradas.</p>`;
  return `${filtro}<div class="pila">${ds
    .map(
      (d) => `<details class="tarjeta decision" data-id="${esc(d.id)}" ${estado.decisionAbierta === d.id ? "open" : ""}>
      <summary><span class="id">${esc(d.id)}</span><strong>${esc(d.titulo)}</strong>${chip(d.estado, ESTADOS_DECISION[d.estado])}<span class="chip">${esc(d.area)}</span><span class="chico suave">${hace(d.creadaEn)}</span></summary>
      <div class="cuerpo"><dl>
        <dt>Contexto</dt><dd>${esc(d.contexto || "—")}</dd>
        <dt>Decisión</dt><dd>${esc(d.decision || "—")}</dd>
        <dt>Alternativas descartadas</dt><dd>${esc(d.alternativas || "—")}</dd>
        <dt>Consecuencias</dt><dd>${esc(d.consecuencias || "—")}</dd>
      </dl>
      <p class="chico suave" style="margin:0">Registrada por ${quienHizo({ quien: d.creadaPor, actor: d.actor })}${d.tareaId ? ` · tarea ${esc(d.tareaId)}` : ""}${d.reemplazaA ? ` · reemplaza a ${esc(d.reemplazaA)}` : ""}</p>
      ${d.estado === "propuesta" ? `<div class="fila"><button class="boton boton-primario boton-chico" data-decidir="${esc(d.id)}" data-valor="aceptada">Aceptar</button><button class="boton boton-chico" data-decidir="${esc(d.id)}" data-valor="rechazada">Rechazar</button></div>` : ""}
      </div></details>`
    )
    .join("")}</div>`;
}

function vistaActividad() {
  return `<section class="tarjeta seccion">${estado.datos.actividad.map(evento).join("") || '<p class="vacio">Sin actividad.</p>'}</section>`;
}

function vistaSesiones() {
  const lista = (titulo, items) => (items?.length ? `<h3>${titulo}</h3><ul>${items.map((x) => `<li>${esc(x)}</li>`).join("")}</ul>` : "");
  return `<div class="pila">${
    estado.datos.sesiones
      .map(
        (s) => `<section class="tarjeta seccion"><div class="fila" style="justify-content:space-between"><div class="fila"><span class="id">${esc(s.id)}</span>${avatar(s.creadaPor)}<strong>${esc(nombre(s.creadaPor))}</strong></div><time class="chico suave">${esc(fechaCompleta(s.creadaEn))}</time></div>
        <p>${esc(s.resumen)}</p>${lista("Hecho", s.hecho)}${lista("Pendiente", s.pendiente)}${lista("Decisiones", s.decisiones)}${lista("Próximos pasos", s.proximosPasos)}</section>`
      )
      .join("") || '<p class="vacio">Aún no hay sesiones. Claude registra una al terminar cada conversación.</p>'
  }</div>`;
}

function vistaEquipo() {
  const miembros = Object.entries(estado.datos.equipo);
  return `<div class="rejilla-inicio">
    <section class="tarjeta seccion"><h2>Personas</h2>
      <div class="pila">${miembros
        .map(
          ([email, m]) => `<form class="pila" style="gap:8px;padding-bottom:12px;border-bottom:1px solid var(--borde)" data-miembro="${esc(email)}">
          <div class="fila">${avatar(email)}<strong>${esc(m.nombre || email)}</strong><span class="chico suave">${esc(email)}</span></div>
          <div class="controles"><label class="campo">Nombre<input name="nombre" value="${esc(m.nombre || "")}" /></label>
          <label class="campo">Áreas (separadas por coma)<input name="areas" value="${esc((m.areas || []).join(", "))}" /></label></div>
          <div class="acciones"><button class="boton boton-chico" type="submit">Guardar</button></div></form>`
        )
        .join("")}
      <form class="pila" style="gap:8px" data-miembro="">
        <h3>Agregar persona</h3>
        <p class="chico suave" style="margin:0">Además de agregarla aquí, su correo debe estar en <code>firestore.rules</code> y tener una cuenta en Firebase Authentication.</p>
        <div class="controles"><label class="campo">Correo<input name="email" type="email" required /></label><label class="campo">Nombre<input name="nombre" required /></label></div>
        <label class="campo">Áreas (separadas por coma)<input name="areas" placeholder="diseño, arte, historia" /></label>
        <div class="acciones"><button class="boton boton-chico" type="submit">Agregar</button></div>
      </form></div>
    </section>
    <section class="tarjeta seccion"><h2>Agentes</h2><ul class="lista-limpia">${Object.entries(AGENTES)
      .map(([k, a]) => `<li><strong>${esc(a.nombre)}</strong> <span class="id">${esc(k)}</span><br><span class="chico suave">${esc(a.rol)}</span></li>`)
      .join("")}</ul></section>
  </div>`;
}

// ---------- panel de detalle ----------

function abrirTarea(id) {
  estado.tareaAbierta = id;
  document.getElementById("panel").hidden = false;
  document.getElementById("velo").hidden = false;
  pintar(document.getElementById("panel"), panelTarea(id));
}

function cerrarPanel() {
  estado.tareaAbierta = null;
  document.getElementById("panel").hidden = true;
  document.getElementById("velo").hidden = true;
}

function panelTarea(id) {
  const t = tarea(id);
  if (!t) return `<p class="vacio">No se encontró ${esc(id)}.</p><button class="boton" data-accion="cerrar-panel">Cerrar</button>`;
  const preguntas = estado.datos.preguntas.filter((p) => p.tareaId === id);
  const idsRelacionados = new Set([id, ...preguntas.map((p) => p.id)]);
  const historial = estado.datos.actividad.filter((a) => idsRelacionados.has(a.entidadId));
  const propuesta = estado.datos.propuestas.find((p) => p.id === t.propuestaId);
  return `<div class="panel-cabecera"><div class="pila" style="gap:6px"><div class="fila"><span class="id">${esc(t.id)}</span>${chipEstado(t.estado)}${chipPrioridad(t.prioridad)}<span class="chip">${esc(TIPOS_TAREA[t.tipo] || t.tipo)}</span></div><h2>${esc(t.titulo)}</h2>
      ${propuesta ? `<span class="chico suave">Propuesta: ${esc(propuesta.id)} · ${esc(propuesta.titulo)}</span>` : ""}</div>
      <button class="boton boton-chico" data-accion="cerrar-panel" aria-label="Cerrar">Cerrar</button></div>
    <div class="controles" data-editar="${esc(t.id)}">
      <label class="campo">Estado<select data-campo="estado">${opciones(ESTADOS, t.estado)}</select></label>
      <label class="campo">Prioridad<select data-campo="prioridad">${opciones(PRIORIDADES, t.prioridad)}</select></label>
      <label class="campo">Responsable<select data-campo="responsable">${opcionesMiembros(t.responsable)}</select></label>
      <label class="campo">Agente<select data-campo="agente">${opciones(AGENTES, t.agente, "Sin agente")}</select></label>
    </div>
    <section class="pila" style="gap:6px"><h3>Descripción</h3><p class="texto-largo">${esc(t.descripcion || "Sin descripción.")}</p>
      ${t.rama ? `<p class="chico" style="margin:0">Rama: <code>${esc(t.rama)}</code></p>` : ""}
      ${t.dependencias?.length ? `<p class="chico" style="margin:0">Depende de: ${t.dependencias.map((d) => `<button class="boton-texto" data-tarea="${esc(d)}">${esc(d)}</button> ${tarea(d) ? chipEstado(tarea(d).estado) : ""}`).join(" ")}</p>` : ""}</section>
    ${t.criterios?.length ? `<section><h3>Criterios de aceptación</h3><ul>${t.criterios.map((c) => `<li>${esc(c)}</li>`).join("")}</ul></section>` : ""}
    ${preguntas.length ? `<section class="pila" style="gap:8px"><h3>Bloqueos</h3>${preguntas.map(tarjetaBloqueo).join("")}</section>` : ""}
    <section class="pila" style="gap:8px"><h3>Comentar</h3>
      <form class="pila" style="gap:8px" data-comentar="${esc(t.id)}"><textarea class="control" name="texto" data-borrador="c-${esc(t.id)}" placeholder="Deja una nota para el equipo y los agentes" required>${esc(estado.borradores[`c-${t.id}`] || "")}</textarea>
      <div class="acciones"><button class="boton" type="submit">Comentar</button></div></form></section>
    <section><h3>Historial</h3><ul class="historial">${historial
      .map((a) => `<li>${avatar(a.quien)}<div><div class="chico">${quienHizo(a)} · <time title="${esc(fechaCompleta(a.ts))}">${hace(a.ts)}</time></div><div>${esc(a.resumen)}</div></div></li>`)
      .join("") || '<li class="suave">Sin historial.</li>'}</ul></section>`;
}

// ---------- diálogos ----------

function abrirDialogo(html, alEnviar) {
  dialogo.innerHTML = html;
  const form = dialogo.querySelector("form");
  form.addEventListener("submit", async (ev) => {
    ev.preventDefault();
    if (ev.submitter?.value === "cancelar") return dialogo.close();
    await intentar(async () => {
      await alEnviar(new FormData(form));
      dialogo.close();
    });
  });
  dialogo.showModal();
}

function dialogoNuevaTarea() {
  const propuestas = Object.fromEntries(estado.datos.propuestas.filter((p) => p.estado !== "archivada").map((p) => [p.id, `${p.id} · ${p.titulo}`]));
  abrirDialogo(
    `<form><h2>Nueva tarea</h2>
      <label class="campo">Título<input name="titulo" required /></label>
      <label class="campo">Descripción<textarea name="descripcion"></textarea></label>
      <div class="controles">
        <label class="campo">Tipo<select name="tipo">${opciones(TIPOS_TAREA, "feature")}</select></label>
        <label class="campo">Prioridad<select name="prioridad">${opciones(PRIORIDADES, "P2")}</select></label>
        <label class="campo">Responsable<select name="responsable">${opcionesMiembros(estado.usuario.email)}</select></label>
        <label class="campo">Agente<select name="agente">${opciones(AGENTES, "", "Sin agente")}</select></label>
        <label class="campo">Propuesta<select name="propuestaId">${opciones(propuestas, estado.filtros.propuestaId, "Ninguna")}</select></label>
        <label class="campo">Estado<select name="estado">${opciones(ESTADOS, "backlog")}</select></label>
      </div>
      <label class="campo">Criterios de aceptación (uno por línea)<textarea name="criterios"></textarea></label>
      <div class="acciones"><button class="boton" value="cancelar" formnovalidate>Cancelar</button><button class="boton boton-primario" type="submit">Crear</button></div></form>`,
    async (d) => {
      const id = await estado.nucleo.crearTarea({
        titulo: d.get("titulo"),
        descripcion: d.get("descripcion"),
        tipo: d.get("tipo"),
        prioridad: d.get("prioridad"),
        responsable: d.get("responsable") || null,
        agente: d.get("agente") || null,
        propuestaId: d.get("propuestaId") || null,
        estado: d.get("estado"),
        criterios: String(d.get("criterios")).split("\n").map((s) => s.trim()).filter(Boolean),
      });
      avisar(`Tarea ${esc(id)} creada.`);
    }
  );
}

function dialogoNuevaPropuesta() {
  abrirDialogo(
    `<form><h2>Nueva propuesta</h2>
      <label class="campo">Título<input name="titulo" required placeholder="Combate naval" /></label>
      <label class="campo">Qué se quiere lograr y por qué<textarea name="descripcion"></textarea></label>
      <label class="campo">Objetivo (cuándo está terminada)<input name="objetivo" /></label>
      <div class="acciones"><button class="boton" value="cancelar" formnovalidate>Cancelar</button><button class="boton boton-primario" type="submit">Crear</button></div></form>`,
    async (d) => {
      const id = await estado.nucleo.crearPropuesta({ titulo: d.get("titulo"), descripcion: d.get("descripcion"), objetivo: d.get("objetivo") });
      avisar(`Propuesta ${esc(id)} creada.`);
    }
  );
}

// ---------- eventos ----------

document.addEventListener("click", (ev) => {
  const el = ev.target.closest("[data-ir],[data-tarea],[data-accion],[data-propuesta],[data-pestana],[data-opcion],[data-decidir]");
  if (!el) return;
  if (el.dataset.ir) {
    location.hash = el.dataset.ir;
  } else if (el.dataset.tarea && !el.closest("form")) {
    abrirTarea(el.dataset.tarea);
  } else if (el.dataset.propuesta) {
    estado.filtros.propuestaId = el.dataset.propuesta;
    if (estado.vista === "tablero") renderizarBarra();
    location.hash = "tablero";
    renderizar();
  } else if (el.dataset.pestana) {
    estado.pestanaBloqueos = el.dataset.pestana;
    renderizar();
  } else if (el.dataset.opcion) {
    const area = el.closest("form").querySelector("textarea");
    area.value = el.dataset.opcion;
    estado.borradores[area.dataset.borrador] = area.value;
    area.focus();
  } else if (el.dataset.decidir) {
    intentar(() => estado.nucleo.actualizarDecision(el.dataset.decidir, { estado: el.dataset.valor }));
  } else {
    const acciones = {
      salir: () => signOut(auth),
      "cerrar-panel": cerrarPanel,
      "nueva-tarea": dialogoNuevaTarea,
      "nueva-propuesta": dialogoNuevaPropuesta,
      tema: () => {
        const oscuro = document.documentElement.dataset.theme
          ? document.documentElement.dataset.theme === "dark"
          : matchMedia("(prefers-color-scheme: dark)").matches;
        document.documentElement.dataset.theme = oscuro ? "light" : "dark";
        try { localStorage.setItem("pizarra-tema", document.documentElement.dataset.theme); } catch {}
      },
    };
    acciones[el.dataset.accion]?.();
  }
});

document.addEventListener("keydown", (ev) => {
  if (ev.key === "Escape" && estado.tareaAbierta && !dialogo.open) cerrarPanel();
});

document.addEventListener("toggle", (ev) => {
  if (ev.target.matches?.("details.decision") && ev.target.open) estado.decisionAbierta = ev.target.dataset.id;
}, true);

document.addEventListener("input", (ev) => {
  const el = ev.target;
  if (el.dataset.borrador) estado.borradores[el.dataset.borrador] = el.value;
  if (el.dataset.filtro === "texto") {
    estado.filtros.texto = el.value;
    pintarTablero();
  }
});

function pintarTablero() {
  const contenido = document.getElementById("contenido");
  contenido.innerHTML = vistaTablero();
}

document.addEventListener("change", (ev) => {
  const el = ev.target;
  if (el.dataset.filtro && el.dataset.filtro !== "texto") {
    estado.filtros[el.dataset.filtro] = el.type === "checkbox" ? el.checked : el.value;
    pintarTablero();
  } else if (el.dataset.campo) {
    const id = el.closest("[data-editar]").dataset.editar;
    const valor = el.value || null;
    el.blur();
    intentar(() => estado.nucleo.actualizarTarea(id, { [el.dataset.campo]: valor }));
  } else if (el.dataset.propuestaEstado) {
    intentar(() => estado.nucleo.actualizarPropuesta(el.dataset.propuestaEstado, { estado: el.value }));
  } else if (el.hasAttribute("data-filtro-decisiones")) {
    estado.filtroDecisiones = el.value;
    el.blur();
    renderizar();
  }
});

document.addEventListener("submit", (ev) => {
  const form = ev.target;
  if (form.closest("dialog") || form.id === "form-acceso") return;
  ev.preventDefault();
  const datos = new FormData(form);
  if (form.dataset.responder) {
    const id = form.dataset.responder;
    intentar(async () => {
      const r = await estado.nucleo.responderPregunta(id, String(datos.get("respuesta")).trim());
      delete estado.borradores[id];
      form.querySelector("textarea").blur();
      avisar(`Respuesta registrada.${r.desbloqueada ? ` ${esc(r.tareaId)} vuelve a «${ESTADOS[r.desbloqueada]}».` : ""}`);
    });
  } else if (form.dataset.comentar) {
    const id = form.dataset.comentar;
    intentar(async () => {
      await estado.nucleo.comentar("tarea", id, String(datos.get("texto")).trim());
      delete estado.borradores[`c-${id}`];
      form.reset();
      form.querySelector("textarea").blur();
    });
  } else if (form.dataset.miembro !== undefined) {
    const email = (form.dataset.miembro || String(datos.get("email"))).trim().toLowerCase();
    const areas = String(datos.get("areas") || "").split(",").map((s) => s.trim()).filter(Boolean);
    intentar(async () => {
      await estado.nucleo.guardarMiembro(email, { nombre: String(datos.get("nombre")).trim(), areas });
      document.activeElement?.blur();
      avisar("Equipo actualizado.");
    });
  }
});

// Arrastrar tarjetas entre columnas cambia el estado de la tarea.
document.addEventListener("dragstart", (ev) => {
  const tarjeta = ev.target.closest?.("[data-tarea]");
  if (tarjeta) ev.dataTransfer.setData("text/plain", tarjeta.dataset.tarea);
});
document.addEventListener("dragover", (ev) => {
  const col = ev.target.closest?.("[data-columna]");
  if (!col) return;
  ev.preventDefault();
  document.querySelectorAll(".columna.sobre").forEach((c) => c !== col && c.classList.remove("sobre"));
  col.classList.add("sobre");
});
document.addEventListener("dragleave", (ev) => {
  const col = ev.target.closest?.("[data-columna]");
  if (col && !col.contains(ev.relatedTarget)) col.classList.remove("sobre");
});
document.addEventListener("drop", (ev) => {
  const col = ev.target.closest?.("[data-columna]");
  if (!col) return;
  ev.preventDefault();
  col.classList.remove("sobre");
  const id = ev.dataTransfer.getData("text/plain");
  const t = tarea(id);
  if (t && t.estado !== col.dataset.columna) intentar(() => estado.nucleo.actualizarTarea(id, { estado: col.dataset.columna }, { nota: "movida en el tablero" }));
});

try {
  const tema = localStorage.getItem("pizarra-tema");
  if (tema) document.documentElement.dataset.theme = tema;
} catch {}
