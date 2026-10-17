# Unidades v1 y sus estadísticas

> Tarea: **T-016** (P-003). Agente: game-designer. Estado: propuesta para revisión.
> Fuentes: `docs/historia/ejercitos-1879.md` y `docs/historia/armadas-1879.md` (T-015), `docs/historia/geografia-1879.md` (T-009).
> Decisiones que respeta: ADR-003 (tres facciones con unidades propias), ADR-005 (representación provisional), ADR-006 (6 jugadores × ~500 unidades, simulación a 20 Hz, objetivos a 5 Hz), ADR-007 (UnitDef, WeaponDef, EntityDef), ADR-009 en propuesta (unidades y buques en metros reales, geografía a 1:20).
> Depende de: **T-022** (recursos y edificios) y **T-035** (recursos de la época) para los costos; **T-031** para las bonificaciones de facción.

## 1. Objetivo para el jugador

Formar un ejército y una escuadra pequeños y legibles, en los que cada unidad tenga una función clara y una contra clara:

- **En tierra**, el fusil de retrocarga manda: la infantería de línea es el núcleo, la artillería rompe las masas de infantería, la caballería explora y caza artillería y tropa débil, y la guardia nacional es tropa barata para llenar filas.
- **En el mar**, el blindaje manda: los blindados son casi inmunes a los buques de madera, las torpederas son la amenaza barata contra los blindados, las corbetas cazan torpederas y transportes, y los transportes llevan el ejército de un puerto a otro.
- El **dominio del mar** permite mover el ejército más rápido que a pie (ficha de ejércitos, §5) y es la forma de proyectar fuerza a lo largo de la costa.

Para el prototipo bastan **6 plantillas de tierra y 5 de mar** (11 en total, 2 de ellas únicas de facción por casco y 1 unidad de élite).

## 2. Convenciones de escala (decisión de diseño propuesta)

| Magnitud | Convención v1 | Motivo |
|---|---|---|
| Qué es una entidad de tierra | **Una figura = un soldado o una pieza con sus sirvientes.** No representa una compañía ni respeta la proporción histórica de efectivos | ADR-006 dibuja y simula unidades individuales en formación; 500 por jugador |
| Qué es un buque | **Un buque = un buque**, en metros reales (ADR-009) | Los buques son pocos y reconocibles |
| Distancias de combate | **No hay un factor único.** Fusiles ~1:8 (300 m reales → 40 m); artillería de campaña ~1:35–40 (4–5 km → 120 m), de modo que su ventaja sobre el fusil baja de ~10× a 3×; artillería naval ~1:20, la escala del mapa (§2.2) | Con zoom medio la cámara ve unos 150–250 m; un alcance de 300 m reales no se podría leer en pantalla y uno de 4 km quedaría fuera de ella |
| Cadencias | **Comprimidas ~1:2** respecto de la cadencia histórica, conservando proporciones (con el redondeo de §6.3) | Que los combates de tierra duren 20–60 s y los navales 2–4 min |
| Velocidades | Valores de diseño en m/s de juego, en dos regímenes: táctica y marcha (§2.1). Buques en régimen táctico: **m/s ≈ nudos históricos** de 1879 (redondeados) | ADR-009: las velocidades no se derivan de la geografía |
| Tiempos | Todo cooldown y build_time es múltiplo de 0,05 s (tick de 20 Hz, ADR-006) | Sin restos de tick |

### 2.1 Velocidades: convención de dos regímenes (aprobada por Luis en Q-010)

**El problema (dato de T-010 / ADR-009):** la geografía va a 1:20 y las unidades en metros reales. A paso real de infantería (~1,4 m/s) cruzar los ~121,5 km de juego de Callao a Valparaíso lleva ~24 h, y en buque a 10 m/s, ~3,3 h. Las velocidades de juego tienen que ser mayores que las reales, pero si son muy altas los combates se ven acelerados (una carga de caballería a 25 m/s es instantánea en pantalla).

**Convención:** las velocidades son **valores de diseño en m/s de juego** (no hay un factor de tiempo global, que no se puede aplicar en multijugador con combates simultáneos) y hay **dos regímenes**:

- **Táctica** (`speed`, §4): la que se usa en combate y cerca del enemigo. Se elige para que el combate se lea bien a la escala 1:1 de las figuras: infantería 3,5 m/s (≈ 2,5 × el paso real), caballería 7, artillería 2,5; buques ≈ nudos de 1879 en m/s (≈ 2 × la velocidad real).
- **Marcha** (`march_speed`, **campo nuevo de UnitDef aprobado en Q-010**; falta enmendar ADR-007): se usa cuando la unidad (o su grupo de movimiento, ADR-006) se desplaza sin enemigos visibles a menos de 150 m y sin haber recibido daño en los últimos 5 s. Al aparecer un enemigo, el grupo pasa a velocidad táctica en 1 s (desaceleración, sin parada en seco). En pantalla la columna de marcha se dibuja en formación de columna, para que la velocidad alta se entienda como desplazamiento operativo.

| Unidad | speed táctica (m/s) | march_speed (m/s) |
|---|---|---|
| operario, guardia_nacional, infanteria_linea, colorados_bolivia | 3,5 | 10 |
| caballeria | 7 | 14 |
| artilleria_campana | 2,5 | 8 |
| transporte | 10 | 25 |
| torpedera | 16 | 30 |
| corbeta | 12 | 28 |
| blindado_bateria_chile | 10 | 24 |
| monitor_torre_peru | 11 | 26 |

Los multiplicadores de terreno de §12 se aplican a los dos regímenes.

**Tiempos de cruce resultantes** (línea recta, terreno llano, sin paradas; distancias de juego = distancia real / 20, ficha de geografía §4.4):

| Tramo | km de juego | Infantería táctica (3,5) | Infantería en marcha (10) | Caballería en marcha (14) | Artillería en marcha (8) | Transporte en marcha (25) | Blindado en marcha (24) |
|---|---|---|---|---|---|---|---|
| Arica – Tacna | 2,65 | 12,6 min | 4,4 min | 3,2 min | 5,5 min | — (tierra) | — |
| Pisagua – Iquique | 3,5 | 16,7 min | 5,8 min | 4,2 min | 7,3 min | 2,3 min | 2,4 min |
| Iquique – Arica | 9,75 | 46 min | 16 min | 11,6 min | 20 min | 6,5 min | 6,8 min |
| Antofagasta – Iquique | 19 | 1 h 30 min | 32 min | 23 min | 40 min | 12,7 min | 13,2 min |
| Núcleo 1879–1880 (Antofagasta–Tacna, ~835 km reales) | 41,75 | 3 h 19 min | 70 min | 50 min | 87 min | 28 min | 29 min |
| Teatro completo (Callao–Valparaíso) | 121,5 | 9 h 39 min | 3 h 23 min | 2 h 25 min | 4 h 13 min | 81 min | 84 min |

Lectura para el diseño:

- En marcha, una partida que se juega en una región (p. ej. Tarapacá–Arica) tiene desplazamientos de 5–20 min a pie y 2–7 min por mar: sensación de campaña (Q-001) sin muertos de espera.
- Cruzar el teatro completo a pie no es razonable en una partida (más de 3 h). Es intencional: **el mar es la vía rápida** (unas 2,5 veces más rápido que a pie), igual que en 1879 (ficha de ejércitos §5). En la historia la ventaja era mucho mayor: un vapor a 10 nudos recorre unos 440 km por día (cálculo: 10 × 1,852 km × 24 h), y una columna a pie, del orden de 20–25 km por día (**[P]**: no está en la ficha de T-015; hay que verificarlo con el historiador). El cociente es de ~18–22×; el juego lo comprime a ~2,5× para que el ejército de tierra siga siendo jugable. El terreno (§12) y, más adelante, el agua (T-022/T-031) la amplían en la práctica.
- Equivalencia de tiempo, solo como referencia: una jornada de marcha real (~25 km [P] = 1,25 km de juego) dura ~2 min de juego en marcha.

Luis aprobó esta convención en **Q-010**.

### 2.2 Alcances y la escala de la geografía

- **Fusiles:** comprimidos ~1:8 (40 m de juego por ~300 m reales). A la escala geográfica 1:20 serían 15 m, menos de 10 cuerpos de distancia: ilegible.
- **Artillería de campaña:** 120 m (≈ 4–5 km reales / 35–40). Es una compresión mayor que la del fusil, a propósito: la proporción con el fusil baja de ~10:1 a 3:1 (§6.1).
- **Artillería naval:** 200 m para los cañones pesados, 80–150 m para los ligeros y 120 m para la ametralladora de la corbeta. Coincide con la escala geográfica: 3–5 km reales de alcance de un cañón de 9–10" / 20 ≈ 150–250 m. Es decir, **la artillería naval es la única que se mide con la misma escala que el mapa**, y por eso un buque frente a un puerto domina el puerto, como en 1879.
- **Bahía de Iquique (~3 km reales ≈ 150 m de juego sin ampliar):** sin ampliar, un blindado de 64 m con 200 m de alcance cubriría la bahía entera desde la boca, y dos buques casi no caben para maniobrar. **Q-009 aprobó ampliar los sitios clave de 3 a 5 veces** en el pipeline del mapa (ADR-009 §1b; la lista de sitios la define el historiador en T-040). Desde diseño se pide el **factor ×5** para las bahías con combate naval (Iquique, Arica, Callao, Antofagasta): ~750 m de bahía, unos 3,7 alcances de cañón pesado, con espacio para maniobrar y espolonear. Con ×3 (~450 m) el combate dentro de la bahía sigue siendo posible pero muy apretado. Los alcances navales no cambian con la ampliación.

## 3. Lista de unidades v1

### 3.1 Tierra

| id | Nombre visible | Categoría | Facciones | Rol | Le gana a | Pierde contra |
|---|---|---|---|---|---|---|
| `operario` | Operario | WORKER | las tres | Recolecta y construye (provisional hasta T-022) | — | todo lo armado |
| `guardia_nacional` | Guardia nacional movilizada | INFANTRY | las tres | Tropa barata, rápida de reclutar, con fusil de avancarga. Relleno de filas y defensa temprana | operarios; aguanta a la artillería por su bajo costo | caballería, infantería de línea |
| `infanteria_linea` | Infantería de línea | INFANTRY | las tres | Núcleo del ejército: fusil de retrocarga, buen alcance y cadencia | caballería, guardia nacional | artillería (en masa), Colorados |
| `colorados_bolivia` | Batallón Colorados | INFANTRY | **Bolivia (única)** | Infantería de élite: más vida, algo de protección y más daño | infantería de línea, guardia nacional | artillería, caballería en número |
| `caballeria` | Caballería | CAVALRY | las tres | Exploración, persecución, caza de artillería y de tropa en desorden | artillería, guardia nacional, operarios | infantería de línea |
| `artilleria_campana` | Artillería de campaña | ARTILLERY | las tres | Fuego a distancia con daño de área contra infantería agrupada; bombardeo de costa | infantería y guardia agrupadas | caballería (alcance mínimo), cualquier unidad que llegue a 20 m, **corbetas y buques de línea** (tienen más alcance: 150–200 m contra 120 m). La defensa contra buques es la artillería de costa, que es un edificio (T-022) |

### 3.2 Mar

| id | Nombre visible | Facciones | Rol | Le gana a | Pierde contra |
|---|---|---|---|---|---|
| `transporte` | Transporte | las tres (en Bolivia, vapores mercantes fletados; Q-011) | Lleva tropas por mar y desembarca en la costa | — | todo lo armado |
| `torpedera` | Lancha torpedera | Chile, Perú | Ataque casi suicida contra los buques de línea: llega bajo el fuego lento de los cañones pesados y descarga un torpedo de botalón | blindado y monitor (3 torpederas hunden uno solo), transportes | corbetas (su ametralladora la hunde antes del contacto) |
| `corbeta` | Corbeta | Chile, Perú | Buque de madera rápido, con cañones ligeros y ametralladora: escolta contra torpederas, caza de transportes y bombardeo de costa | torpederas, transportes, tropas y artillería de campaña en la costa | blindado y monitor (no les hace daño) |
| `blindado_bateria_chile` | Blindado de batería central | **Chile (único)** | Buque de línea: mucho blindaje y una batería de banda potente pero lenta | corbetas, monitor en duelo a distancia | torpederas (necesita escolta de corbetas) |
| `monitor_torre_peru` | Monitor de torre | **Perú (único)** | Buque de línea más ágil, con torre giratoria y **espolón** | corbetas, blindado si llega al contacto | torpederas (necesita escolta), blindado a distancia |

**Triángulo naval:** corbeta > torpedera > buque de línea > corbeta. Funciona porque los cañones pesados de los buques de línea tienen cadencia lenta (12–14 s): una torpedera rápida recibe como mucho un disparo antes del contacto. La corbeta, en cambio, lleva fuego rápido (ametralladora) que la hunde en la aproximación, y su armamento ligero no penetra ningún blindaje (armadura ≥ 20). Las cifras están en §7.

**No van en v1** (candidatos a v2 o a T-031): artillería de montaña, ametralladoras de tierra (Gatling, Nordenfelt), zapadores, cañonera, monitor costero (Manco Cápac), montoneros, caballería en mulas como unidad separada, infantería de marina. La artillería de costa y los fuertes son **edificios** (T-022).

### 3.3 Disponibilidad por facción (FactionDef.units)

| Unidad | Chile | Perú | Bolivia |
|---|---|---|---|
| operario, guardia_nacional, infanteria_linea, caballeria, artilleria_campana | sí | sí | sí |
| colorados_bolivia | — | — | sí |
| transporte | sí | sí | sí (fletado, Q-011) |
| torpedera, corbeta | sí | sí | — |
| blindado_bateria_chile | sí | — | — |
| monitor_torre_peru | — | sí | — |

Las unidades compartidas son **un solo .tres** en `data/units/comun/` (ADR-007). El color de la facción viene de FactionDef. Las diferencias de facción (p. ej. carabina de repetición chilena, mulas bolivianas) se agregan en T-031 como variantes o bonificaciones, no aquí.

## 4. Tabla de estadísticas

Recursos **PROVISIONALES** (hasta T-022/T-035): **V** = víveres, **P** = pesos (dinero del salitre, la plata y el guano), **C** = carbón (solo buques). Los nombres y las cantidades pueden cambiar; las **proporciones** entre unidades son lo que se está fijando aquí.

### 4.1 Tierra

| id | max_hp | armor | speed (m/s) | turn_rate (°/s) | radius (m) | vision_range (m) | cost (V / P) | build_time (s) | pop_cost |
|---|---|---|---|---|---|---|---|---|---|
| operario | 40 | 0 | 3,5 | 360 | 0,4 | 50 | 50 / 0 | 20 | 1 |
| guardia_nacional | 50 | 0 | 3,5 | 360 | 0,4 | 55 | 40 / 10 | 15 | 1 |
| infanteria_linea | 60 | 0 | 3,5 | 360 | 0,4 | 60 | 60 / 30 | 22 | 1 |
| colorados_bolivia | 75 | 1 | 3,5 | 360 | 0,4 | 60 | 70 / 50 | 28 | 1 |
| caballeria | 80 | 0 | 7,0 | 270 | 0,8 | 100 | 100 / 60 | 30 | 2 |
| artilleria_campana | 80 | 2 | 2,5 | 90 | 1,5 | 70 | 40 / 150 | 40 | 3 |

### 4.2 Mar

| id | max_hp | armor | speed (m/s) | turn_rate (°/s) | radius (m) | vision_range (m) | cost (V / P / C) | build_time (s) | pop_cost |
|---|---|---|---|---|---|---|---|---|---|
| transporte | 400 | 1 | 10 | 6 | 10 | 150 | 50 / 150 / 50 | 45 | 4 |
| torpedera | 180 | 0 | 16 | 25 | 4 | 140 | 0 / 170 / 55 | 35 | 2 |
| corbeta | 1000 | 3 | 12 | 8 | 10 | 200 | 50 / 300 / 100 | 70 | 6 |
| blindado_bateria_chile | 2400 | 22 | 10 | 6 | 12 | 180 | 100 / 700 / 250 | 140 | 15 |
| monitor_torre_peru | 1800 | 20 | 11 | 9 | 10 | 170 | 100 / 600 / 220 | 130 | 13 |

Cambios tras la revisión de QA: torpedera vida 120 → 180, speed 14 → 16 y costo 0 / 120 / 40 → 0 / 170 / 55 (225: dos torpederas cuestan lo mismo que una corbeta); corbeta vida 900 → 1000; monitor armadura 18 → 20.

`radius` de los buques es el radio de ocupación para la evitación local, no la eslora. La forma alargada la da `placeholder_shape = HULL` (§8).

### 4.3 Armas (WeaponDef)

DPS = damage / cooldown, sin contar armadura. `target_domains` usa el enum `domain` de UnitDef (LAND, SEA). Los edificios cuentan como objetivo LAND.

| id del arma | Lo lleva | damage | range (m) | min_range (m) | cooldown (s) | DPS | target_domains | splash_radius (m) **[propuesta]** |
|---|---|---|---|---|---|---|---|---|
| herramienta | operario | 3 | 1,5 | 0 | 1,5 | 2,0 | LAND | — |
| fusil_avancarga | guardia_nacional | 8 | 30 | 0 | 7,0 | 1,14 | LAND, SEA | — |
| fusil_retrocarga | infanteria_linea | 8 | 40 | 0 | 3,0 | 2,67 | LAND, SEA | — |
| fusil_remington_colorados | colorados_bolivia | 9 | 40 | 0 | 3,0 | 3,0 | LAND, SEA | — |
| carabina | caballeria | 6 | 25 | 0 | 3,0 | 2,0 | LAND, SEA | — |
| sable | caballeria | 11 | 2,5 | 0 | 1,5 | 7,33 | LAND | — |
| canon_campana | artilleria_campana | 30 | 120 | 20 | 8,0 | 3,75 | LAND, SEA | 5 |
| canones_ligeros | corbeta | 20 | 150 | 0 | 3,0 | 6,67 | LAND, SEA | — |
| ametralladora | corbeta | 5 | 120 | 0 | 0,25 | 20,0 | SEA | — |
| torpedo_botalon | torpedera | 900 | 6 | 0 | 45,0 | 20,0 | SEA | — |
| bateria_central_9 | blindado_bateria_chile | 120 | 200 | 0 | 12,0 | 10,0 | LAND, SEA | 4 |
| canones_menores | blindado_bateria_chile | 10 | 80 | 0 | 4,0 | 2,5 | LAND, SEA | — |
| torre_10 | monitor_torre_peru | 150 | 200 | 0 | 14,0 | 10,71 | LAND, SEA | 5 |
| canones_40_libras | monitor_torre_peru | 10 | 80 | 0 | 4,0 | 2,5 | LAND, SEA | — |
| espolon | monitor_torre_peru | 400 | 4 | 0 | 30,0 | 13,3 | SEA | — |

El transporte no lleva armas.

Cambios tras la revisión de QA: fusil_avancarga 9 → 8; sable 10 → 11; corbeta + `ametralladora` (solo SEA); torpedo 600 → 900; bateria_central_9 90 cada 8 s → 120 cada 12 s; canones_menores 15/100 m/3 s → 10/80 m/4 s; torre_10 160 cada 15 s → 150 cada 14 s; canones_40_libras 20/100 m → 10/80 m; canon_campana splash 6 → 5 m y tope de área de 6 → 4 entidades adicionales (§5.5).

## 5. Reglas de combate que estas estadísticas suponen

Todas se pueden implementar con los campos de ADR-007, salvo las marcadas **[propuesta]**.

1. **Daño por impacto:** `daño = max(0, damage − armor)`. Con daño 0 el ataque no tiene efecto y el cliente muestra un indicador de «sin efecto» sobre el objetivo (para que se entienda por qué una corbeta no hace nada contra un blindado). No hay probabilidad de fallo en v1: todo disparo que se decide, acierta.
2. **Elección de objetivo (5 Hz, ADR-006):** la unidad elige el enemigo más cercano dentro de `range` cuyo dominio esté en `target_domains` del arma y contra el que haga daño > 0. Si no hay ninguno, usa el más cercano dentro de `vision_range` y se acerca (salvo con orden de mantener posición). Una unidad con varias armas dispara cada una con su propio cooldown y su propio objetivo.
3. **Fuego a pie firme:** las armas de tierra con `range > 5 m` **solo disparan con la unidad detenida**. Las armas de cuerpo a cuerpo (sable, herramienta) y todas las de los buques disparan en movimiento. Es fiel a la táctica de la época (fuego por descargas) y evita el «kiting» de la caballería con carabina.
   **Carga:** una unidad con arma cuerpo a cuerpo (la caballería) que ataca a un objetivo de tierra se acerca hasta el alcance de esa arma y no se detiene a usar la carabina. La carabina solo dispara si la unidad tiene la orden de mantener posición, o contra objetivos SEA.
4. **Alcance mínimo:** `canon_campana` no puede disparar a menos de 20 m. Si un enemigo entra en ese radio, la pieza solo puede retirarse; es la ventana de la caballería.
5. **Daño de área [propuesta: `WeaponDef.splash_radius`]:** el objetivo recibe el daño completo; las demás entidades enemigas de los `target_domains` del arma que estén dentro de `splash_radius` reciben el 50 %, con un máximo de 4 entidades adicionales por impacto (tope de costo en la SpatialGrid de 64 m). Sin fuego amigo en v1.
6. **Espolón y torpedo:** son armas de contacto (alcance 4–6 m). La unidad solo se acerca a ese alcance si recibe la orden de atacar a ese buque, o si su objetivo ya está a menos de 30 m. Así el monitor no se lanza solo contra todo lo que ve.
7. **Transporte [propuesta: `UnitDef.transport_capacity: int`, en pop]:** el transporte carga **20 de pop**. Las unidades de tierra suben si están a ≤ 15 m del transporte detenido junto a la costa; bajan a razón de **1 de pop por segundo** sobre una celda de costa desembarcable (dato del mapa, T-011). Embarcadas no disparan, no ven y no ocupan entidad visible, pero siguen contando su pop. Si el transporte se hunde, mueren todas las unidades embarcadas.
8. **Población:** tope de **500 de pop por jugador** (provisional, lo fija T-022). Como el pop_cost mínimo es 1, el número de entidades por jugador nunca pasa de 500, que es el presupuesto de ADR-006.

## 6. Justificación histórica y licencias

### 6.1 Por unidad

| Unidad | Base histórica | Confianza de la base | Qué se tomó |
|---|---|---|---|
| operario | Peones, arrieros y bagajeros; la intendencia de campaña | [D] concepto | Solo el concepto; es una unidad económica de juego |
| guardia_nacional | Batallones cívicos movilizados de los tres países; parte con Minié (avancarga) | [D] concepto, [P] lista | Fusil de avancarga, menos vida, recluta barato y rápido |
| infanteria_linea | Regimientos y batallones de línea; Comblain, Gras, Chassepot, Peabody, Remington | [D] | Fusil de retrocarga de un tiro (clase única, §6.2) |
| colorados_bolivia | Batallón Colorados, guardia de Daza, con Remington; actuación destacada en Tacna | [D] | Élite: +25 % de vida, armadura 1, +1 de daño |
| caballeria | Granaderos y Cazadores a Caballo (Chile); escuadrones peruanos y bolivianos | [D] | Rápida, ve lejos, sable más carabina corta |
| artilleria_campana | Krupp de campaña (Chile, ~75 piezas); Blakely, White y Grieve (Perú) | [D] tipos, [P] prestaciones | Alcance 3× el del fusil (proporción [P] de la ficha), cadencia lenta, daño de área |
| transporte | Rímac, Itata, Loa, Chalaco, Limeña... | [D] concepto | Sin armas; el mar como vía logística (ficha de ejércitos §5) |
| torpedera | Lanchas de 30–100 t con torpedo de botalón, en ambos bandos | [D] concepto, [P] buques | Un golpe enorme a contacto, casco frágil; ataque casi suicida («ataque suicida o nocturno», ficha de armadas §3) |
| corbeta | Esmeralda, O'Higgins, Chacabuco, Abtao, Unión | [D]/[C] | Madera (armadura 3), muchos cañones ligeros, la más rápida de las grandes (Unión, 12–13 nudos). La ametralladora es una licencia (§6.3) |
| blindado_bateria_chile | Cochrane y Blanco Encalada (1874–1875): cinta de 114–229 mm, 6 cañones de 9" en batería central | [D] | El más protegido y con la batería más potente; 10 m/s (12 nudos, menos el Blanco con fondos sucios) |
| monitor_torre_peru | Huáscar: torre Coles con 2 de 10", espolón, 2 de 40 libras, cinta de 114 mm | [D] | Torre (golpe fuerte y lento), espolón, menos blindaje que el chileno, más ágil (giro 9 °/s) |

Proporciones que se respetan de la ficha:

- Retrocarga contra avancarga: en la historia la retrocarga dispara unas **3–4 veces más rápido** ([P]); en el juego el DPS es **2,3×** mayor y el alcance un 33 % mayor. Se suaviza para que la guardia nacional no sea inútil (licencia de jugabilidad).
- Artillería contra fusil: el Krupp de campaña alcanza unas **10 veces** el alcance eficaz del Comblain ([P]); en el juego, **3 veces** (120 m contra 40 m). Con 10 veces la artillería dispararía fuera de la pantalla.
- Blindado contra madera: los cañones ligeros no penetraban el blindaje de 114 mm o más; en el juego la corbeta hace **0 de daño** al blindado (armadura 22) y al monitor (armadura 20), porque su arma más fuerte hace 20, y sí puede dañar a otras corbetas, transportes y torpederas.
- Velocidades navales: m/s ≈ nudos de 1879 (Cochrane 12 → 10 por promediar con el Blanco; Huáscar 10–11 → 11; Unión 12–13 → 12; corbeta genérica 12, aunque la Esmeralda iba a 3 nudos por sus calderas).

### 6.2 Licencias creativas propuestas por el historiador

| # | Licencia | Evaluación | Cómo queda en v1 |
|---|---|---|---|
| 1 | Agrupar los fusiles por clase (avancarga, retrocarga de un tiro, repetición) | **Aceptada** | 3 clases de arma: `fusil_avancarga`, `fusil_retrocarga` (y su variante de élite) y, en T-031, `carabina_repeticion` para la caballería chilena. El modelo concreto (Comblain, Chassepot...) se nombra solo en el texto de la enciclopedia, cuando el historiador lo verifique |
| 2 | Convención única de desplazamiento por buque (desplazamiento métrico de diseño) | **Aceptada** para textos y enciclopedia | Las estadísticas no se derivan del desplazamiento: vida, armadura y velocidad son valores de diseño (§4.2). No hace falta campo nuevo |
| 3 | Bonificaciones de facción | **Diferida a T-031**, salvo lo que exige una unidad propia | Aquí solo: `colorados_bolivia` (élite), `blindado_bateria_chile` y `monitor_torre_peru` (cascos propios). Reabastecimiento y artillería chilenos, defensa costera e irregulares peruanos, resistencia en altura boliviana y **caballería en mulas** quedan como candidatos para T-031 (la de mulas, como variante de `caballeria` con speed 6 y vida 95, a decidir allí) |
| 4 | Banderas simplificadas en los prototipos | **Aceptada** (coherente con ADR-005) | Los provisionales usan el color de la facción y una bandera simple. El arte final (T-021) debe usar la bandera de guerra correcta de 1879 (escudo peruano, estrella chilena) |

### 6.3 Otras licencias de este documento

- **Buques por clase, no por nombre:** se construyen «monitores de torre» y «blindados de batería», no «el Huáscar». Peruanos y chilenos pueden tener varios, aunque en 1879 hubo un Huáscar y dos blindados chilenos. Propuesta para el cliente: cada buque construido recibe un nombre histórico de una lista por clase y facción (Huáscar, Independencia...; Cochrane, Blanco Encalada...) en orden de construcción. Es solo visual (placeholder_label o un nombre por instancia que decidirá el arquitecto).
- **La torpedera a 16 m/s** es una suposición de diseño ([P]: no hay datos verificados de las lanchas de 1879). Es la más rápida del juego para que el triángulo naval funcione.
- **Fuego rápido solo en la corbeta:** en 1879 el Huáscar llevaba una Gatling y los blindados chilenos 1–2 Nordenfelt (ficha de armadas). En el juego la ametralladora va solo en la corbeta, y los buques de línea tienen armas secundarias débiles (10 de daño, que contra la madera de la corbeta quedan en 7). Es una licencia de jugabilidad: si los buques de línea tuvieran fuego rápido, la torpedera no tendría con qué amenazarlos y el triángulo naval desaparecería.
- **Cadencia de los cañones pesados** (12–14 s): más rápida que la real (minutos por disparo en los de avancarga de 9–10"), pero la más lenta del juego.
- **Distancias y cadencias comprimidas** (§2).
- **Sin agua, munición ni desgaste en v1.** La ficha (§5) dice que el agua decidió la campaña. Queda como mecánica de logística para T-022/T-031 (p. ej. desgaste de vida fuera del radio de una aguada). En v1 no existe para que el prototipo de combate sea simple.

## 7. Balance: tiempos para matar (TTK) recalculados

**Convención (la misma de QA):** primer disparo en t = 0 y después cada `cooldown`; daño por impacto = max(0, damage − armor); sin fallos. El enfrentamiento empieza cuando el atacante entra en el alcance del defensor, o en su visión si es menor (el defensor no dispara a lo que no ve). El atacante va en línea recta a velocidad táctica y el defensor está quieto. Un disparo que coincide con el instante de llegada no se cuenta. Se ignora el retardo de adquisición de objetivo (≤ 0,2 s, ADR-006). Daño contra corbeta (armadura 3): cañones ligeros 17, ametralladora 2, cañones menores y de 40 libras 7. Contra torpedera (armadura 0): todo el daño.

### 7.1 Triángulo naval: corbeta > torpedera > buque de línea > corbeta

| # | Enfrentamiento | Costo (rec. / pop) | Resultado | Cálculo |
|---|---|---|---|---|
| N1 | 1 corbeta contra 1 torpedera (desde 150 m) | 450 / 6 contra 225 / 2 | **Gana la corbeta sin daño.** Torpedera hundida en t ≈ 7,6 s, a ~28 m | Llegada a 6 m: 144 / 16 = 9,0 s. Cañones: t = 0, 3, 6 → 60. Ametralladora desde 120 m (t = 1,875) cada 0,25 s: 24 disparos hasta t = 7,625 → 120. Total 180 = vida |
| N2 | **1 corbeta contra 2 torpederas a la vez (igual costo)** | **450 / 6 contra 450 / 4** | **Gana la corbeta** con 103 de vida; las 2 torpederas hundidas (t ≈ 14,6 s). Pérdidas: 0 contra 450 | La 1.ª muere en 7,6 s. La 2.ª recibe 5 disparos de ametralladora (25) y llega en t = 9,0 con 155: torpedo 900 − 3 = 897 → corbeta 1000 − 897 = 103. Después: 20 + 6,67 DPS → hundida 5,6 s más tarde. Cooldown del torpedo: 45 s |
| N3 | 1 corbeta contra 3 torpederas a la vez (**1,5 veces el costo** de la corbeta) | 450 / 6 contra 675 / 6 | Ganan las torpederas, perdiendo 1. Pérdidas: 450 contra 225 | 2 impactos (1794) a t = 9,0 s. Hace falta 1,5 veces el costo para ganarle a la corbeta |
| N3b | **2 corbetas contra 4 torpederas (igual costo)** | **900 / 12 contra 900 / 8** | **Ganan las corbetas.** En el peor caso (las 4 contra la misma corbeta) se pierde 1 corbeta y mueren las 4 torpederas. Pérdidas: 450 contra 900. Si se reparten 2 y 2, no se hunde ninguna corbeta (como N2) | Cada corbeta hunde 1 torpedera en 7,6 s. Las otras 2 llegan en t = 9,0 con ~155 cada una: 2 impactos hunden una corbeta. La otra hunde a las 2 restantes en ~12 s (26,7 DPS contra 155 cada una) |
| N4 | 1 torpedera contra 1 blindado solo (desde 180 m, su visión) | 225 / 2 contra 1050 / 15 | Llega con 40 de vida, impacta (878) y muere después | Llegada: 174 / 16 = 10,875 s. Batería: solo t = 0 (120), la siguiente es en t = 12. Cañones menores desde 80 m (t = 6,25): t = 6,25 y 10,25 → 20. 180 − 140 = 40. La batería la hunde en t = 12 |
| N5 | 2 torpederas contra 1 blindado solo | 450 / 4 contra 1050 / 15 | El blindado queda con 644 de vida; las 2 torpederas mueren (t = 12 y t ≈ 34 s) antes de recargar | 2 × 878 = 1756 |
| N6 | **3 torpederas contra 1 blindado solo (64 % del costo)** | **675 / 6 contra 1050 / 15** | **Blindado hundido en t = 10,9 s; sobreviven las 3.** Pérdidas: 1050 contra 0 | Antes del contacto el blindado hace 140 de daño en total. 3 × 878 = 2634 ≥ 2400. Con 4 torpederas (900, igual costo aprox.) el resultado es el mismo con margen |
| N7 | 3 torpederas contra 1 blindado escoltado por 1 corbeta (la corbeta ve a 200 m) | 675 / 6 contra 1500 / 21 | **Gana la escolta:** 1 solo impacto (blindado con 1522), y mueren las 3 torpederas. Pérdidas: 0 contra 675 | Llegada desde 200 m: 12,125 s. Batería en t = 0 y t = 12 + cañones menores → la 1.ª torpedera muere en t = 12. La corbeta hunde la 2.ª en ~10,75 s (cañones desde t = 3,1 y ametralladora desde t = 5). Llega 1 |
| N7b | **6 torpederas contra 1 blindado + 1 corbeta (igual costo aprox.)** | **1350 / 12 contra 1500 / 21** | **Gana la escolta por valor:** el blindado se hunde, pero mueren las 6 torpederas. Pérdidas: 1050 contra 1350 | Antes del contacto mueren 2 (batería y corbeta). Llegan 4: 3 hunden el blindado y 1 deja la corbeta con 103. La corbeta hunde a las 4 restantes en ~27 s (180 cada una a 26,7 DPS), antes de que recarguen (45 s) |
| N7c | 4 torpederas contra 1 blindado + 1 corbeta | 900 / 8 contra 1500 / 21 | **Gana la escolta:** blindado con 644, sin otras pérdidas; mueren las 4 torpederas. Pérdidas: 0 contra 900 | Mueren 2 antes del contacto; llegan 2 (2 × 878) |
| N8 | 1 torpedera contra 1 monitor solo (desde 170 m) | 225 / 2 contra 920 / 13 | Llega con 10 de vida e impacta (880) | Llegada: 164 / 16 = 10,25 s. Torre: solo t = 0 (150). Cañones de 40 libras desde 80 m (t = 5,625): t = 5,625 y 9,625 → 20 |
| N9 | 3 torpederas contra 1 monitor solo (73 % del costo) | 675 / 6 contra 920 / 13 | Monitor hundido (3 × 880 = 2640 ≥ 1800) | Con 2 queda con 40 de vida |
| N10 | 1 blindado contra 1 corbeta | 1050 / 15 contra 450 / 6 | **Gana el blindado sin recibir daño.** TTK 96 s solo con la batería (9 disparos de 117, t = 0…96); 84 s si la corbeta está a menos de 80 m (+7 cada 4 s) | Corbeta contra blindado: 20 − 22 → 0 y 5 − 22 → 0. La corbeta puede huir (12 contra 10 m/s) |
| N11 | 1 monitor contra 1 corbeta | 920 / 13 contra 450 / 6 | **Gana el monitor sin recibir daño.** TTK 84 s con la torre (7 disparos de 147); 70 s a menos de 80 m | Corbeta contra monitor: 20 − 20 → 0 |
| N12 | Blindado contra monitor, a distancia (200 m) | 1050 contra 920 | **Gana el blindado** en t = 204 s y queda con 480 | Blindado: 100 por disparo, 18 disparos → t = 17 × 12 = 204. Monitor: 128 por disparo, 15 disparos hasta t = 196 → 1920 |
| N13 | El monitor fuerza el contacto (de 200 a 4 m a 11 m/s = 17,8 s) | — | **Gana el monitor** en t ≈ 107,8 s y queda con ~900 | Torre: 8 disparos (1024) + espolón en t = 17,8, 47,8, 77,8 y 107,8 (4 × 378 = 1512) = 2536 ≥ 2400. El blindado hace 9 × 100 = 900 |
| N14 | 1 corbeta contra 1 transporte | 450 contra 250 | Transporte hundido en ~17,8 s | 19 cada 3 s + 4 cada 0,25 s ≈ 22,3 DPS contra 400 |
| N15 | 1 corbeta contra 1 artilleria_campana en la costa (desde 150 m) | 450 contra 190 | **Gana la corbeta sin daño** en t = 12 s | 18 por disparo, 5 disparos. La pieza alcanza 120 m: no llega |

### 7.2 Tierra

| # | Enfrentamiento | Costo (rec. / pop) | Resultado | Cálculo |
|---|---|---|---|---|
| L1 | 2 infanteria_linea contra 1 caballeria (la caballería carga desde 40 m) | 180 / 2 contra 160 / 2 | **Gana la infantería sin bajas** (un infante queda con 5 de vida); la caballería muere en t = 12 s | Contacto: 37,5 / 7 = 5,36 s. Fusiles en t = 0, 3, 6, 9 y 12, 16 por descarga → 80. Sable: 11 en t = 5,36, 6,86, 8,36, 9,86 y 11,36 → 55 (el 6.º golpe sería en t = 12,86) |
| L2 | 1 caballeria contra 3 guardia_nacional (carga desde 30 m) | 160 / 2 contra 150 / 3 | **Gana la caballería por poco** (le quedan 8 de vida) en t = 24,9 s | Contacto: 27,5 / 7 = 3,93 s. 5 sablazos por guardia (55 ≥ 50): mueren en t = 9,93, 17,43 y 24,93. Descargas (8 cada una) en t = 0 (×3), 7 (×3), 14 (×2) y 21 (×1) = 72 |
| L3 | 1 caballeria contra 2 guardia_nacional | 160 / 2 contra 100 / 2 | Gana la caballería con 40 de vida | Descargas en t = 0 (×2), 7 (×2) y 14 (×1) = 40 |
| L4 | 1 caballeria contra 1 artilleria_campana (la pieza solo, visión 70 m) | 160 / 2 contra 190 / 3 | **Gana la caballería** con 50 de vida, en t = 21,6 s | 1 disparo (t = 0, 30). Entra en 20 m en t = 7,1 (antes del 2.º disparo). Sable 11 − 2 = 9, 9 golpes contra 80 → 12 s tras el contacto (t = 9,64) |
| L5 | Lo mismo, pero otra unidad le da visión a 120 m | — | Gana la caballería con 20 de vida, en t = 28,8 s | 2 disparos (t = 0 y 8) antes de entrar en 20 m (t = 14,3) |
| L6 | 1 artilleria_campana (con visión a 120 m) contra 8 infanteria_linea **agrupadas** que la asaltan de frente | 190 / 3 contra 720 / 8 | La pieza cae en t ≈ 31,9 s después de matar 5 infantes | Impacto con área: 30 + 4 × 15 = 90 como máximo. La infantería tarda 80 / 3,5 = 22,86 s en llegar a 40 m: recibe disparos en t = 0, 8, 16 y 24 |
| L7 | Lo mismo, con la infantería **dispersa** (más de 5 m entre figuras) | 190 / 3 contra 720 / 8 | La pieza cae en t = 28,9 s después de matar 2 | Sin área: 30 por disparo (t = 0, 8, 16 → muere 1 y otro queda con 30). Al llegar (t = 22,86) disparan 7 infantes (42); en t = 24 la pieza mata al herido; en t = 25,86 disparan 6 (36) y en t = 28,86 otros 6. Cada fusil hace 8 − 2 = 6 |
| L8 | 1 infanteria_linea contra 1 colorados_bolivia | 90 / 1 contra 120 / 1 | Ganan los Colorados con 26 de vida, en t = 18 s | Colorados: 9 por disparo, 7 disparos contra 60. Línea: 8 − 1 = 7 por disparo, 7 disparos = 49 contra 75 |

### 7.3 Lectura

- **Tierra:** infantería > caballería (L1) > guardia (L2–L3) y artillería (L4–L5) > infantería agrupada (L6). L2 queda en el límite a propósito: la guardia nacional sigue siendo útil en defensa, en bloque. La dispersión es la respuesta del jugador a la artillería (L6 contra L7).
- **Mar, a igual costo:** corbeta > torpedera (N2: 1 contra 2, y N3b: 2 contra 4; las torpederas necesitan 1,5 veces el costo para ganar, N3); torpedera > buque de línea solo (N6 y N9: 3 torpederas, el 64 % del costo del blindado y el 73 % del monitor, lo hunden sin pérdidas); buque de línea > corbeta (N10–N11, sin daño). La escolta cierra el triángulo: contra un blindado con 1 corbeta, las torpederas pierden por valor incluso con un costo casi igual (N7b) y pierden claro con menos (N7, N7c).
- **Colorados (para T-031):** rinden ~1,6–1,8 veces más por unidad de pop que la infantería de línea (L8), así que Bolivia casi no construiría línea. Es aceptable en v1; T-031 debe decidir si los limita (tope por jugador, pop 2 o un edificio previo).
- **Duraciones objetivo:** escaramuza de tierra de 10–30 s; duelo naval de 1,5–3,5 min. Se ajustan después de la primera prueba jugable.

## 8. Cómo se ve en pantalla (provisional, ADR-005)

| id | placeholder_shape | placeholder_size (m, x·y·z) | placeholder_label |
|---|---|---|---|
| operario | CAPSULE | 0,5 · 1,7 · 0,5 | OPE |
| guardia_nacional | CAPSULE | 0,5 · 1,75 · 0,5 | GN |
| infanteria_linea | CAPSULE | 0,5 · 1,75 · 0,5 | INF |
| colorados_bolivia | CAPSULE | 0,5 · 1,8 · 0,5 | COL |
| caballeria | BOX | 0,8 · 2,4 · 2,4 | CAB |
| artilleria_campana | BOX | 1,8 · 1,3 · 3,5 | ART |
| transporte | HULL | 10 · 6 · 65 | TRANSP. |
| torpedera | HULL | 3 · 2 · 20 | TORP. |
| corbeta | HULL | 9,8 · 5,5 · 64 | CORB. |
| blindado_bateria_chile | HULL | 14,2 · 6 · 64 | BLIND. |
| monitor_torre_peru | HULL | 10,7 · 4,5 · 60 | MONIT. |

- Medidas en metros reales (ADR-009): corbeta como la Esmeralda corregida por la ficha (64 m sin bauprés), blindado como el Cochrane, monitor como el Huáscar (60 m).
- Barra de vida y etiqueta solo en las unidades seleccionadas o cercanas (ADR-006, punto 7).
- Panel de selección: vida, armadura, cada arma con daño, alcance y cadencia, y en los transportes la carga (x/20).
- Al pasar el ratón sobre un enemigo con una unidad seleccionada, si el daño contra él es 0, el cursor de ataque se muestra tachado.
- Círculo de alcance al seleccionar artillería y buques (exterior = range, interior = min_range).

## 9. Casos borde

- **Armadura ≥ daño:** daño 0, sin efecto (§5.1). La elección automática de objetivos ignora esos objetivos, pero el jugador puede ordenar el ataque (verá el indicador de «sin efecto»).
- **Infantería contra buques:** los fusiles pueden disparar a buques a ≤ 40 m de la costa. Contra la corbeta (armadura 3) hacen 3–6 (carabina 3, avancarga y Remington 5–6, retrocarga 5); contra el transporte (armadura 1), 5–8; contra blindado y monitor, 0. Recuerda a Punta Gruesa, donde la fusilería desde la Covadonga causó bajas en la Independencia.
- **Artillería rodeada:** con todos los enemigos a < 20 m no dispara; la orden de mantener posición no la hace disparar.
- **Espolón contra un buque varado o detenido:** funciona igual; no hay daño propio al espolonear en v1.
- **Transporte hundido con tropas:** mueren todas y se notifica al dueño. El pop se libera.
- **Desembarco sin costa válida:** la orden se rechaza con COMMAND_REJECTED y el motivo «costa no desembarcable».
- **Tope de población:** no se puede encolar una unidad si su pop no cabe; la cola espera sin cobrar.
- **Unidades fuera de la visión:** la artillería (alcance 120, visión 70) y los buques grandes (alcance 200, visión 170–180) necesitan que otra unidad vea el objetivo. Es intencional: obliga a explorar con caballería o corbetas.
- **Muchos impactos de área a la vez:** el tope de 4 entidades adicionales por impacto acota el costo por tick.
- **Cooldown y tick:** todos los valores son múltiplos de 0,05 s; la simulación los resta por tick sin redondeo.

## 10. Decisiones de producto respondidas por Luis

- **Q-010, velocidad de desplazamiento:** dos regímenes, combate y marcha (§2.1). Se aprueba `UnitDef.march_speed`.
- **Q-011, Bolivia y el mar:** Bolivia solo construye **transportes fletados** (vapores mercantes) y **no tiene buques de combate**. Puede mover tropas por mar, pero no disputa el dominio naval. Usa la misma definición `transporte` que Chile y Perú.
- **Q-009, ampliación de sitios clave:** de 3 a 5 veces en el pipeline del mapa (ADR-009 §1b; lista de sitios en T-040). Diseño pide ×5 para las bahías con combate naval (§2.2).

## 11. Campos nuevos para ADR-007 (la forma la decide el arquitecto)

| Campo | Recurso | Tipo | Uso |
|---|---|---|---|
| `splash_radius` | WeaponDef | float (m), 0 = sin área | Artillería y cañones pesados (§5.5) |
| `transport_capacity` | UnitDef | int (pop), 0 = no transporta | Transporte (§5.7) |
| Multiplicador de velocidad por terreno y categoría | datos del mapa o constante | tabla | Ver §12 |
| `march_speed` | UnitDef | float (m/s), 0 = igual a `speed` | Régimen de marcha (§2.1). **Aprobado en Q-010.** Más dos constantes de la simulación: distancia de enemigo que corta la marcha (150 m) y tiempo sin daño para volver a ella (5 s) |

## 12. Terreno y movimiento (propuesta para T-010/T-011)

Basado en la ficha de geografía (§6). Multiplicador de `speed` por tipo de celda y categoría:

| Terreno | INFANTRY / WORKER | CAVALRY | ARTILLERY |
|---|---|---|---|
| Camino o sendero | 1,2 | 1,2 | 1,3 |
| Pampa y llano | 1,0 | 1,0 | 1,0 |
| Arenal o duna | 0,8 | 0,7 | 0,6 |
| Cuesta (subida de la costa a la pampa, precordillera) | 0,6 | 0,6 | 0,4 |
| Altiplano | 0,8 | 0,8 | 0,7 |
| Acantilado costero, cordillera alta fuera de los pasos | intransitable | intransitable | intransitable |

El ferrocarril se trata como edificio o transporte en T-022. El agua y las aguadas, en T-022/T-031.

## 13. Decisiones registradas (propuestas, área diseño)

- **ADR-011:** catálogo de unidades v1 y triángulos de contras.
- **ADR-012:** escala de combate (figuras, alcances, cadencias, velocidades).
- **ADR-013:** evaluación de las licencias creativas de T-015.

## 14. Pendiente

- Costos con los recursos definitivos (T-022, T-035).
- Bonificaciones y variantes de facción (T-031): carabina de repetición chilena, caballería en mulas, defensa costera peruana, artillería boliviana escasa.
- Verificar con el historiador las prestaciones [P] antes de usarlas en textos de la enciclopedia.
- Primera prueba jugable: ajustar §4 con los enfrentamientos de §7.
