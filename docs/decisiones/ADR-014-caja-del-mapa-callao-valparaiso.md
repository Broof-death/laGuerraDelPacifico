# ADR-014: Licencia creativa: caja del mapa Callao–Valparaíso (11,5–33,5° S, 78–67° W); la Breña y la correría de la Unión a Punta Arenas quedan fuera del mapa

- Estado: Aceptada
- Área: historia
- Fecha: 2026-10-17

## Contexto

Q-006 (respondida por Feño, responsable de historia). La ficha de T-009 (`docs/historia/geografia-1879.md` §4 y §9) propone una caja de 11,5–33,5° S y 78–67° W, que ADR-009 usa para la escala 1:20 (~122 × 51–60 km de juego). La guerra tuvo operaciones fuera de esa caja: la campaña de la Breña (1881–1883, hasta Huamachuco, 7,81° S, 78,05° W) y la correría de la corbeta Unión hasta Punta Arenas (~53° S) en 1879.

## Decisión

El mapa continuo usa la caja propuesta: norte 11,5° S, sur 33,5° S, oeste 78° W, este 67° W (WGS84). La campaña de la Breña y la correría de la Unión a Punta Arenas quedan **fuera** del mapa y se representan como eventos o texto. Cualquier sitio fuera de la caja (Huamachuco, Punta Arenas, San Pablo, etc.) se documenta como fuera del mapa y no tiene lupa.

Nota: parte del valle del Mantaro (Concepción, Huancayo, Marcavalle, Pucará; ~11,9–12,2° S, ~75° W) cae geográficamente dentro de la caja, pero sus combates de la Breña se tratan igual como eventos o texto mientras no se decida otra cosa.

## Alternativas descartadas

- Extender hasta ~7° S para incluir la Breña: mapa de ~2850 km; obligaría a comprimir a 1:22–1:24 según ADR-009 §2.
- Recortar a Antofagasta–Lima por la costa sur (~1300 km) y dejar Valparaíso fuera.

Ambas descartadas por Feño en Q-006.

## Consecuencias

- ADR-009 se mantiene sin cambios (escala 1:20, caja de ~122 km norte–sur).
- `tools/mapa/sitios.json` (T-040) solo pone lupas dentro de la caja y lista aparte los sitios fuera del mapa.
- El juego debe contar la Breña y la correría de la Unión como eventos o textos (tarea futura de diseño).
- Fichas: `docs/historia/geografia-1879.md` §4 y §9, `docs/historia/sitios-clave-escala.md`.
