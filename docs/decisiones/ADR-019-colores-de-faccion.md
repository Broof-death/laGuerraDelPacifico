# ADR-019: Colores de facción: un color de cada bandera sin repetir (Chile azul, Perú carmín, Bolivia verde con acento amarillo)

- Estado: Aceptada
- Área: arte
- Fecha: 2026-10-17

## Contexto

`FactionDef.color` era provisional y T-017 pinta las vistas con una paleta por jugador (`TeamColors.from_factions` está listo para leer el color de la facción). Las tres banderas comparten el rojo, y la convención del mapa de Turner (1879: Perú ocre, Bolivia verde, Chile rosado) se lee mal sobre el desierto. Feño eligió la opción A en Q-018.

## Decisión

Cada facción usa un color dominante de su bandera, sin repetir: Chile azul, Perú rojo carmín, Bolivia verde con amarillo como acento.

Valores iniciales [J] (`docs/diseno/estilo-visual.md` §2.4):

| Facción | Color |
|---|---|
| Chile | `#2B4C8C` |
| Perú | `#9B1B30` |
| Bolivia | `#2F8F5B` |
| Acento de Bolivia | `#E3B23C` |

Todo símbolo, unidad o edificio coloreado por facción lleva **contorno o halo oscuro**, también el acento amarillo de Bolivia. Bolivia lleva siempre el acento amarillo como segunda señal. El ajuste fino corresponde al área de arte.

## Alternativas descartadas

- B: convención de Turner 1879 (Perú ocre, Bolivia verde, Chile rosado). Descartada porque el ocre y el rosado se confunden con el desierto.
- C: mixto (bandera para unidades y Turner para el territorio). Descartada en favor de una sola convención.
- D: colores neutros no nacionales. Descartada por perder la identificación inmediata.

## Consecuencias

- `FactionDef.color` de Chile, Perú y Bolivia, y `TeamColors.from_factions`, toman estos valores. En el mapa estratégico de papel el territorio se pinta con ellos como tinta plana y transparente.
- Contraste WCAG sobre el papel `#D4C9A9` y sobre el desierto `#B9A98A`: Chile 5,06 y 3,62; Perú 4,91 y 3,51; Bolivia 2,45 y 1,75; acento 1,19 y 1,18. Bolivia y el acento quedan por debajo de 3:1 (WCAG 1.4.11), de ahí la regla del borde oscuro.
- Chile y Perú tienen entre sí un contraste de 1,03:1: en gris son idénticos y solo se distinguen por el tono.
- En la simulación de deuteranopía (Machado 2009), Perú y Bolivia pasan de 0,040 a 0,165 en RGB lineal y de 15,0 a 17,3 en ΔE*76 respecto de la primera versión (`#A51F34` y `#1B6B42`), así que el modo daltónico necesita además un patrón o una forma.
