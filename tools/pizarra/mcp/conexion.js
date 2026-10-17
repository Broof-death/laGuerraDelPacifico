// Conexión a Firebase desde Node (servidor MCP y scripts), autenticada con la cuenta de cada persona.
import { fileURLToPath } from "node:url";
import path from "node:path";
import dotenv from "dotenv";
import { initializeApp } from "firebase/app";
import { getAuth, signInWithEmailAndPassword, connectAuthEmulator } from "firebase/auth";
import * as fs from "firebase/firestore";
import { firebaseConfig, configEmulador, EMULADOR, estaConfigurado } from "../web/config.js";
import { crearNucleo } from "../web/nucleo.js";

const RAIZ = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
dotenv.config({ path: path.join(RAIZ, ".env"), quiet: true });

export const usaEmulador = process.env.PIZARRA_EMULADOR === "1";

export class ErrorConfiguracion extends Error {}

export function problemaDeConfiguracion() {
  if (!usaEmulador && !estaConfigurado(firebaseConfig)) {
    return "Falta la configuración de Firebase en tools/pizarra/web/config.js (ver tools/pizarra/README.md).";
  }
  if (!process.env.PIZARRA_EMAIL || !process.env.PIZARRA_PASSWORD) {
    return "Faltan PIZARRA_EMAIL y PIZARRA_PASSWORD en tools/pizarra/.env (copia .env.example).";
  }
  return null;
}

let conexion = null;

export async function conectar() {
  if (conexion) return conexion;
  const problema = problemaDeConfiguracion();
  if (problema) throw new ErrorConfiguracion(problema);

  const app = initializeApp(usaEmulador ? configEmulador : firebaseConfig);
  const auth = getAuth(app);
  const db = fs.getFirestore(app);
  if (usaEmulador) {
    connectAuthEmulator(auth, EMULADOR.auth, { disableWarnings: true });
    fs.connectFirestoreEmulator(db, EMULADOR.firestoreHost, EMULADOR.firestorePuerto);
  }
  const { user } = await signInWithEmailAndPassword(auth, process.env.PIZARRA_EMAIL, process.env.PIZARRA_PASSWORD);
  conexion = { app, db, fs, usuario: user, nucleo: crearNucleo(fs, db, { email: user.email }) };
  return conexion;
}

export async function desconectar() {
  if (conexion) await fs.terminate(conexion.db);
  conexion = null;
}
