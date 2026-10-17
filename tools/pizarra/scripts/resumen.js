// Hook SessionStart de Claude Code: imprime el estado de la pizarra para que cada chat nuevo
// empiece sabiendo qué se hizo antes. Nunca falla: si algo sale mal, lo dice en una línea y sale.
import { conectar, desconectar, problemaDeConfiguracion } from "../mcp/conexion.js";
import { resumenComoTexto } from "../mcp/consultas.js";

const LIMITE_MS = 15000;

const problema = problemaDeConfiguracion();
if (problema) {
  console.log(`[Pizarra] No conectada: ${problema}`);
  process.exit(0);
}

try {
  const texto = await Promise.race([
    conectar().then((ctx) => resumenComoTexto(ctx)),
    new Promise((_, rechazar) => setTimeout(() => rechazar(new Error("tiempo de espera agotado")), LIMITE_MS)),
  ]);
  console.log(texto);
  console.log("\n(Resumen automático de la pizarra. Sigue el protocolo de CLAUDE.md.)");
  await desconectar();
} catch (e) {
  console.log(`[Pizarra] No se pudo leer el estado: ${e.message}`);
}
process.exit(0);
