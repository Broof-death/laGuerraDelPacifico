# Pizarra

Tablero compartido del proyecto: tareas, bloqueos que deben resolver personas, decisiones (ADR) y la bitácora de sesiones. Tiene tres partes:

- **Interfaz web** (`web/`): para que las personas vean cómo va el proyecto. Se actualiza en tiempo real.
- **Servidor MCP** (`mcp/`): para que el Claude Code de cada persona lea y escriba en la pizarra.
- **Hook de inicio** (`scripts/resumen.js`): cada chat nuevo de Claude empieza con el resumen del estado.

Todo funciona con el plan **gratuito (Spark)** de Firebase: Firestore, Authentication y Hosting. No usa Cloud Functions.

## Configuración inicial (una sola vez, la hace una persona)

1. En la [consola de Firebase](https://console.firebase.google.com), crea un proyecto o usa uno existente. Revisa que esté en el plan **Spark**.
2. **Authentication → Método de acceso:** habilita **Correo electrónico/contraseña**.
3. **Authentication → Usuarios:** crea un usuario para cada persona con una contraseña temporal. Cada uno puede cambiarla con «Olvidé mi contraseña» en la pizarra.
4. **Authentication → Configuración → Acciones del usuario:** desmarca **Habilitar creación (registro)**, para que nadie más pueda crear cuentas.
5. **Firestore Database → Crear base de datos** en modo producción. Para Chile y Perú conviene la región `southamerica-east1`.
6. **Configuración del proyecto → Tus apps → Agregar app web.** Copia el objeto `firebaseConfig` en `web/config.js`. Esa configuración no es secreta: la seguridad la dan las reglas de Firestore.
7. En `firestore.rules`, reemplaza `companero@ejemplo.com` por el correo real de tu compañero.
8. Publica las reglas y la interfaz:

   ```bash
   cd tools/pizarra
   npm install
   firebase login --reauth
   firebase use --add          # elige tu proyecto
   npm run desplegar
   ```

   La interfaz queda en `https://<tu-proyecto>.web.app`.
9. Entra a la pizarra y, en **Equipo**, registra a cada persona con su nombre y sus áreas (por ejemplo «programación, arquitectura» o «diseño, arte, historia»). El Orquestador usa estas áreas para saber a quién le toca resolver cada bloqueo.

## Configuración de cada persona

1. Clona el repositorio y ejecuta `npm install` en `tools/pizarra`.
2. Copia `.env.example` como `.env` y escribe tu correo y contraseña de la pizarra. El archivo `.env` no se sube a git.
3. Abre Claude Code en la raíz del repositorio. Te pedirá aprobar el servidor MCP `pizarra` (definido en `.mcp.json`): apruébalo.
4. Prueba con: *«¿Cómo vamos con el proyecto?»*.

## Uso diario

- **Humanos:** entren a la web para ver el estado («Cómo vamos»), mover tareas, responder bloqueos («Por resolver»), aprobar decisiones y leer la bitácora.
- **Con Claude:** pide lo que quieras implementar («quiero implementar el combate naval»). El Orquestador lo convierte en propuesta y tareas, y los agentes trabajan sobre ellas siguiendo `CLAUDE.md`.

## Desarrollo local con el emulador (sin cuenta de Firebase)

```bash
npm run emulador          # en una terminal: Auth, Firestore y la web en http://127.0.0.1:5055
npm run emulador:datos    # en otra: crea usuarios y datos de ejemplo (clave: pizarra123)
npm run probar            # prueba de punta a punta del servidor MCP (borra los datos del emulador)
```

Para que tu Claude use el emulador, agrega `PIZARRA_EMULADOR=1` en `.env`.

## Límites del plan gratuito

Al día: 50 000 lecturas, 20 000 escrituras y 1 GiB de almacenamiento. Un equipo de dos personas usa una fracción de eso. Si alguna vez se supera, Firestore deja de responder hasta el día siguiente; no se cobra nada.

## Modelo de datos (Firestore)

| Colección | Contenido |
|---|---|
| `tareas` | `T-001`…: estado, prioridad, agente, responsable, propuesta, dependencias, criterios, rama |
| `propuestas` | `P-001`…: cambios grandes que agrupan tareas |
| `preguntas` | `Q-001`…: bloqueos dirigidos a una persona; al responderse, la tarea vuelve a su estado anterior |
| `decisiones` | `ADR-001`…: contexto, decisión, alternativas, consecuencias, estado |
| `sesiones` | `S-001`…: resumen de cada conversación y próximos pasos |
| `actividad` | historial de todo lo que hicieron personas y agentes (solo se agrega, nunca se edita) |
| `config/equipo` | personas y sus áreas |
| `lecturas/{correo}` | última actividad vista por cada persona (para las novedades) |

La lógica compartida entre la web y el servidor MCP está en `web/nucleo.js`.
