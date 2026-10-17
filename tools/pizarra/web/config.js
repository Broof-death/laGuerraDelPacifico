// Configuración pública de Firebase (no es secreta: la seguridad la dan las reglas de Firestore).
// Cópiala desde la consola de Firebase: Configuración del proyecto → Tus apps → App web → SDK config.
export const firebaseConfig = {
  apiKey: "AIzaSyBmxJYe6NmFYaqhy6hnIf7dbnGbtTCGLLc",
  authDomain: "la-guerra-del-pacifico.firebaseapp.com",
  projectId: "la-guerra-del-pacifico",
  storageBucket: "la-guerra-del-pacifico.firebasestorage.app",
  messagingSenderId: "492366804379",
  appId: "1:492366804379:web:fce7a538069de124b81d3e",
};

// Configuración usada contra el emulador local (no necesita cuenta de Firebase).
export const configEmulador = {
  apiKey: "demo-clave",
  authDomain: "demo-pizarra.firebaseapp.com",
  projectId: "demo-pizarra",
};

export const EMULADOR = { auth: "http://127.0.0.1:9199", firestoreHost: "127.0.0.1", firestorePuerto: 8180 };

export const estaConfigurado = (cfg) => !String(cfg.projectId).startsWith("REEMPLAZAR");
