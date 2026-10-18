# ADR-018: Licencia estética: interfaz como cartografía impresa de 1879 y mundo 3D naturalista

- Estado: Aceptada
- Área: arte
- Fecha: 2026-10-17

## Contexto

T-034 reunió mapas de 1879 de dominio público (Bertrand, Turner, Prieto, Paz Soldán, Ondarza) con un lenguaje visual reconocible: papel crema, tinta sepia, relieve con normales, coloreado a mano. Había que decidir cuánto de ese estilo llega al juego (Q-017). Feño eligió la opción A.

## Decisión

El minimapa, el mapa estratégico, los menús y las cartelas imitan un mapa impreso de 1879: papel y tinta sepia, tipografía y simbología tomadas de las leyendas de época (`docs/diseno/estilo-visual.md` §2.1, §3 y §4).

El mundo 3D (terreno, buques, tropas, edificios) es naturalista y sobrio, con luz natural y la paleta desaturada del desierto, el mar frío y el adobe (§2.3), sin filtros de grabado. Los tres bandos reciben el mismo cuidado visual.

## Alternativas descartadas

- B: todo el juego con aspecto de grabado o litografía. Descartada por su costo en shaders y arte, y por el riesgo para el presupuesto de 60 FPS de ADR-010.
- C: interfaz moderna sin referencias de época. Descartada por perder la identidad histórica que dan los mapas.

## Consecuencias

- La interfaz y el shader del minimapa necesitan texturas de papel y una paleta de tinta.
- El arte final (T-021, T-026) sigue una línea naturalista.
- Los valores de la guía son una base que el área de arte puede afinar.
- Se registra como licencia estética: el juego no reproduce un mapa concreto, sino que se inspira en la cartografía de la época.
