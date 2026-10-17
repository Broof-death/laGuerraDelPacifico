# Créditos de assets de terceros

Todo modelo, textura, sonido o fuente que no se haya creado en el proyecto se registra aquí: de dónde salió, su autor y su licencia. Antes de agregar un asset, comprueba que su licencia permita el uso comercial.

## Modelos 3D

| Carpeta | Paquete | Autor | Licencia | Origen | Uso en el juego |
|---|---|---|---|---|---|
| `models/kenney/pirate_kit/` | Pirate Kit 2.1 | Kenney | CC0 1.0 | https://kenney.nl/assets/pirate-kit | Barcos de vela, botes, cañones, muelles y torres (provisional) |
| `models/kenney/mini_characters/` | Mini Characters | Kenney | CC0 1.0 | https://kenney.nl/assets/mini-characters | Soldados y trabajadores con animaciones (provisional) |
| `models/kenney/castle_kit/` | Castle Kit | Kenney | CC0 1.0 | https://kenney.nl/assets/castle-kit | Fuertes, murallas y torres (provisional) |
| `models/kenney/fantasy_town_kit/` | Fantasy Town Kit 2.0 | Kenney | CC0 1.0 | https://kenney.nl/assets/fantasy-town-kit | Piezas para armar edificios, carretas y puestos (provisional) |

CC0 permite el uso comercial sin atribución. Igual se acredita a Kenney (www.kenney.nl) en los créditos del juego.

Notas sobre estos paquetes:

- Solo se incluyen los modelos en formato GLB. Del paquete Mini Characters se omitieron los accesorios médicos y las sillas de ruedas.
- Los nombres de archivo se pasaron a `snake_case` (ADR-007). La carpeta `Textures/` conserva su nombre original porque los GLB la referencian con esa ruta exacta.
- **Escala:** los modelos de Kenney no vienen en metros reales. Medidos en Godot 4.7.2: personaje de unos 0,7 m de alto, `ship_large` de 13 m de eslora, `tower_square` de 1,3 m de alto. Al usarlos hay que escalarlos en la escena visual; por ejemplo, ×2,5 para que un soldado mida unos 1,75 m. Los barcos generados por el proyecto sí están en metros.
- Cada personaje de Mini Characters trae 32 animaciones: `idle`, `walk`, `sprint`, `die`, `holding-both-shoot` (disparo con fusil), `attack-melee-right`, `pick-up`, entre otras.

## Modelos generados por el proyecto

| Carpeta | Contenido | Cómo se generan |
|---|---|---|
| `models/barcos/` | Prototipos low-poly del Huáscar y la Esmeralda | `tools/modelos/generar_barcos.py` (ver su encabezado) |
