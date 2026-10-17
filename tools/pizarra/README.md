# Pizarra

Tablero compartido del proyecto: tareas, bloqueos que deben resolver personas, decisiones (ADR) y la bitácora de sesiones. Tiene tres partes:

- **Interfaz web** (`web/`): para que las personas vean cómo va el proyecto. Se actualiza en tiempo real.
- **Servidor MCP** (`mcp/`): para que el Claude Code de cada persona lea y escriba en la pizarra.
- **Hook de inicio** (`scripts/resumen.js`): cada chat nuevo de Claude empieza con el resumen del estado.

Todo funciona con el plan **gratuito (Spark)** de Firebase: Firestore, Authentication y Hosting. No usa Cloud Functions.

**Pizarra en línea:** https://la-guerra-del-pacifico.web.app

## Entrar a la pizarra (web)

1. Pide al administrador que te dé acceso (ver [Sumar a una persona](#sumar-a-una-persona)).
2. Entra a https://la-guerra-del-pacifico.web.app con tu correo y la contraseña temporal que te dieron.
3. Para crear tu propia contraseña: en la pantalla de entrada escribe tu correo y presiona **«Olvidé mi contraseña»**. Te llega un enlace por correo (revisa spam).

## Conectar tu Claude Code a la pizarra (MCP)

Hazlo una vez en cada computador. Así tu Claude puede leer y actualizar la pizarra, y cada chat nuevo empieza con el resumen del proyecto.

### Requisitos

- [Node.js](https://nodejs.org) **20 o superior**. Compruébalo con `node -v`.
- [Claude Code](https://claude.com/claude-code) instalado.
- Tener acceso a la pizarra web y **conocer tu contraseña**: tu Claude entra con la misma cuenta.

### Pasos

1. **Clona el repositorio y cámbiate a `develop`:**

   ```bash
   git clone https://github.com/Broof-death/laGuerraDelPacifico.git
   cd laGuerraDelPacifico
   git checkout develop
   ```

2. **Instala las dependencias de la pizarra.** Se crea `node_modules`, que no se sube a git:

   ```bash
   cd tools/pizarra
   npm install
   ```

3. **Crea tu archivo de credenciales.** Copia `.env.example` como `.env`, en la misma carpeta `tools/pizarra`:

   ```bash
   cp .env.example .env        # en PowerShell: Copy-Item .env.example .env
   ```

   Ábrelo y completa tu correo y tu contraseña de la pizarra:

   ```
   PIZARRA_EMAIL=tu-correo@gmail.com
   PIZARRA_PASSWORD=tu-contraseña
   ```

   `.env` está en `.gitignore`: **nunca se sube** y cada persona tiene el suyo.

4. **Comprueba la conexión** antes de abrir Claude. Sigues dentro de `tools/pizarra`:

   ```bash
   npm run resumen
   ```

   Debe mostrar `PIZARRA — La Guerra del Pacífico (sesión de …)` con el estado del proyecto. Si muestra un error, ve a [Problemas frecuentes](#problemas-frecuentes).

5. **Abre Claude Code en la raíz del repositorio**, la carpeta `laGuerraDelPacifico`, no `tools/pizarra`:

   ```bash
   cd ../..
   claude
   ```

   La primera vez te pregunta si quieres usar el servidor MCP **`pizarra`**, definido en `.mcp.json`. Elige **aprobar**.

6. **Verifica dentro de Claude Code:**
   - Escribe `/mcp`: el servidor `pizarra` debe aparecer como conectado.
   - Pregunta *«¿cómo vamos con el proyecto?»*: Claude debe responder con el estado de la pizarra.

Desde ese momento, cada chat nuevo empieza con el resumen de la pizarra: tus bloqueos pendientes, las novedades del equipo y lo que quedó de la última sesión. Claude sigue el protocolo de `CLAUDE.md`.

### Problemas frecuentes

| Mensaje | Solución |
|---|---|
| `Faltan PIZARRA_EMAIL y PIZARRA_PASSWORD` | No existe `tools/pizarra/.env` o le faltan datos (paso 3). |
| `auth/invalid-credential` | Correo o contraseña incorrectos en `.env`. Prueba entrar a la web con los mismos datos. |
| `permission-denied` / «Sin acceso» en la web | Tu correo no está en `firestore.rules`. Pídele al administrador que te agregue. |
| `Cannot find package` / `ERR_MODULE_NOT_FOUND` | Falta `npm install` en `tools/pizarra` (paso 2). |
| `[Pizarra] No disponible` al iniciar un chat | Igual que el anterior, o Node.js no está instalado o no está en el PATH. |
| `/mcp` no muestra `pizarra` | Abriste Claude fuera de la raíz del repositorio, o rechazaste el servidor. Para que vuelva a preguntar: `claude mcp reset-project-choices`. |
| Hiciste `git pull` y algo dejó de funcionar | Ejecuta `npm install` de nuevo en `tools/pizarra` y reinicia Claude Code. |

## Sumar a una persona

Lo hace alguien con acceso al proyecto de Firebase. Hacen falta los tres pasos:

1. **Firebase → Authentication → Usuarios → Agregar usuario**, con su correo y una contraseña temporal.
2. **Agrega su correo a la lista de `firestore.rules`** y publica las reglas. Sin este paso verá «Sin acceso».

   ```bash
   cd tools/pizarra
   firebase deploy --only firestore:rules
   ```

   Después haz commit del cambio, para que nadie lo pierda en un despliegue futuro.
3. En la pizarra web, ve a **Equipo** y regístrala con su nombre y sus áreas. El Orquestador usa las áreas para saber a quién preguntarle cada cosa.

## Configuración del proyecto Firebase (ya está hecha)

Queda como referencia, por si hubiera que montar la pizarra en otro proyecto.

1. Crear el proyecto en la [consola de Firebase](https://console.firebase.google.com), en el plan **Spark** (gratuito).
2. **Authentication → Método de acceso:** habilitar **Correo electrónico/contraseña**. En **Configuración → Acciones del usuario**, desmarcar **Habilitar creación (registro)**.
3. **Firestore Database → Crear base de datos** en modo producción.
4. Registrar una app web y copiar su `firebaseConfig` en `web/config.js`. No es secreta: la seguridad la dan las reglas.
5. Vincular el proyecto en `.firebaserc` (`firebase use --add`) y publicar con `npm run desplegar`.

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
