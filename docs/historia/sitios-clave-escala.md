# Sitios clave ampliados y licencias de escala

Ficha histórica de la tarea **T-040** (propuesta P-002). Define las **lupas** del pipeline del mapa: los sitios que se amplían de 3 a 5 veces sobre la escala general 1:20, según ADR-009 §1b y Q-009. Los datos que lee el pipeline están en `tools/mapa/sitios.json` y se comprueban con `node tools/mapa/validar_sitios.mjs`.

**Decisiones en las que se apoya**

- **ADR-009** (arquitectura): escala 1:20, mapa de 131 072 m, proyección transversa de Mercator con meridiano de 72,5° W y origen en 22,5° S, y el mecanismo de las lupas.
- **Enmienda de ADR-009 §1b del 17-10-2026** (anillo por sitio): permite un anillo de compresión más estrecho, con `w_factor` ≥ 0,5 y `rho_c` ≥ 0,5, solo en los sitios clave muy cercanos entre sí: Arica, Alto de la Alianza, Pisagua, Dolores y Tarapacá. Cualquier otro sitio que lo necesite requiere un nuevo visto bueno de arquitectura.
- **Q-012** (Feño, respondida): se elige el anillo más estrecho (w = 0,5·r, ρc = 0,5) en esos cinco sitios, para que todos tengan su núcleo completo.
- **Q-013** (Luis, respondida): se acepta enmendar ADR-009 §1b. La deformación extra se revisa en el mapa de distorsión de T-011.
- **ADR-014** (historia, licencia creativa, Q-006): caja del mapa de 11,5° a 33,5° S y de 78° a 67° W. La campaña de la Breña y la correría de la *Unión* a Punta Arenas quedan fuera del mapa, como eventos o texto.
- **ADR-015** (historia, licencia creativa, Q-007): fronteras de 1879 con la propuesta neutral (curso bajo del Loa y divisoria de aguas andina), con una nota en el juego. Ninguna lupa cae sobre el tramo discutido del Loa.

**Ficha base.** Las coordenadas marcadas «geografia-1879» vienen de `docs/historia/geografia-1879.md` (T-009), que hoy está en la rama `feature/T-009-geografia-1879` y todavía no se ha fusionado en `develop`.

**Cómo leer la ficha**

- **Documentado:** fecha o hecho con consenso entre las historiografías de los tres países.
- **Discutido:** hay versiones distintas; se indica quién sostiene cada una.
- **Pendiente:** no se pudo verificar en esta sesión. No usarlo como dato firme.
- Las coordenadas van en grados decimales WGS84, con latitud sur y longitud oeste negativas.

---

## 1. Qué es una licencia de escala

Con la geografía a 1:20 y las unidades, buques y edificios a tamaño real (ADR-009 §1), un campo de batalla de 3 km mide 150 m de juego: no cabe ni un batallón. La lupa amplía un **núcleo** de radio *r* (en km reales) *k* veces, de forma uniforme y sin deformar formas, y compensa el área comprimiendo un **anillo** alrededor hasta el radio *R*. Fuera de *R* el mapa queda igual.

Cada lupa es una **licencia creativa**: dentro del núcleo las distancias son *k* veces mayores que las reales a escala 1:20 (es decir, una escala local de 1:20/*k*, entre 1:6,7 y 1:4), y en el anillo las distancias están comprimidas hasta un 40 % (anillo por defecto) o un 50 % (anillo estrecho). Por eso, en el juego:

- las distancias **dentro** de un sitio son proporcionales a las reales (multiplicadas por *k*);
- las distancias **cerca** de un sitio, en el anillo, **no** son proporcionales a las reales;
- las distancias **entre** sitios lejanos (fuera de los anillos) son las reales a 1:20.

Esto debe explicarse en la ayuda del mapa del juego junto a la nota de fronteras de ADR-015.

## 2. Fórmulas y cálculos (ADR-009 §1b y su enmienda)

Unidades: *r*, *w* y *R* en km reales, medidos en el plano de la proyección. En metros de juego se dividen por 20 (1 km real = 50 m de juego).

- **Estiramiento radial** ρ(d): vale *k* en el núcleo (d ≤ r); baja de *k* a ρc con smoothstep entre r y r + w; vale ρc en el anillo; sube de ρc a 1 con smoothstep entre R − w y R; vale 1 fuera.
- **Nueva distancia al centro:** d′ = ∫₀ᵈ ρ(s) ds.
- **Parámetros por sitio** (enmienda): w = `w_factor`·r, con `w_factor` ≥ 0,5 (por defecto 1,0, en `lupa_por_defecto`), y ρc = `rho_c`, con 0,5 ≤ ρc < 1 (por defecto 0,6).
- **Radio exterior** (de la condición d′(R) = R):
  R = [k·r + w·(k + 1)/2 − ρc·(r + w)] / (1 − ρc)
- **Anillo por defecto** (w = r, ρc = 0,6): R = 9,5·r (k = 3), 13,25·r (k = 4) y 17·r (k = 5).
- **Anillo estrecho** (los mínimos, w = 0,5·r y ρc = 0,5): R = (2,5·k − 1)·r, es decir 6,5·r (k = 3), 9·r (k = 4) y 11,5·r (k = 5). Lo usan Arica, el Alto de la Alianza, Pisagua, Dolores y Tarapacá.

**Reglas que se comprueban** (las del pipeline de ADR-009 más dos del historiador):

1. k ∈ [3, 5], `w_factor` ≥ 0,5 y ρc ∈ [0,5, 1). Solo los cinco sitios de la enmienda pueden usar `w_factor` < 1.
2. Los discos de radio R no se solapan: la distancia entre centros debe ser ≥ R₁ + R₂.
3. El núcleo ampliado (radio k·r) queda dentro de la caja jugable (ADR-014). El disco R sí puede salirse de la caja.
4. Cada punto histórico listado en `puntos_nucleo` está a ≤ r del centro.
5. La lupa no pliega el terreno: det J = ρ·d′/d > 0 y d′/d ≥ 1 en todo el disco.
6. Aviso (no bloquea): si un lugar de la caja queda empujado fuera de ella por una lupa.

**Cómo se calcula.** `tools/mapa/validar_sitios.mjs` proyecta con la transversa de Mercator sobre el elipsoide WGS84 (serie de Krüger de orden 3, k₀ = 1), muestrea el borde de la caja cada 0,01°, calcula R con la fórmula y la comprueba integrando ρ numéricamente (d′(R) = R con error < 1 m), y mide las distancias entre centros y al borde. También informa, por lupa, la **anisotropía** máxima (estiramiento tangencial d′/d frente al radial ρ) y el mínimo de det J. Las distancias son del plano proyectado; el error de escala de la proyección es ≤ 0,44 % (ADR-009), despreciable frente a las holguras.

## 3. Sitios con lupa

Resultado del validador sobre `tools/mapa/sitios.json` (km reales proyectados; entre paréntesis, metros de juego). Los sitios van de norte a sur.

| id | k | w/r | ρc | r | k·r (núcleo ampliado) | R | Borde de la caja | Anisotropía máx. |
|---|---|---|---|---|---|---|---|---|
| `lima_callao` | 4 | 1,0 | 0,6 | 15,0 km (750 m) | 60,0 km (3000 m) | 198,8 km (9938 m) | 68,2 km | 5,3 en 2·r |
| `ilo_pacocha` | 3 | 1,0 | 0,6 | 2,0 km (100 m) | 6,0 km (300 m) | 19,0 km (950 m) | 461 km | 4,0 en 2·r |
| `los_angeles_moquegua` | 3 | 1,0 | 0,6 | 5,0 km (250 m) | 15,0 km (750 m) | 47,5 km (2375 m) | 418 km | 4,0 en 2·r |
| `alto_alianza_tacna` | 3 | 0,5 | 0,5 | 4,5 km (225 m) | 13,5 km (675 m) | 29,3 km (1463 m) | 347 km | 5,2 en 1,5·r |
| `arica` | 3 | 0,5 | 0,5 | 3,5 km (175 m) | 10,5 km (525 m) | 22,8 km (1138 m) | 351 km | 5,2 en 1,5·r |
| `pisagua` | 3 | 0,5 | 0,5 | 1,8 km (90 m) | 5,4 km (270 m) | 11,7 km (585 m) | 338 km | 5,2 en 1,5·r |
| `dolores` | 3 | 0,5 | 0,5 | 2,5 km (125 m) | 7,5 km (375 m) | 16,3 km (813 m) | 310 km | 5,2 en 1,5·r |
| `tarapaca` | 3 | 0,5 | 0,5 | 5,5 km (275 m) | 16,5 km (825 m) | 35,8 km (1788 m) | 266 km | 5,2 en 1,5·r |
| `iquique` | 4 | 1,0 | 0,6 | 2,5 km (125 m) | 10,0 km (500 m) | 33,1 km (1656 m) | 330 km | 5,3 en 2·r |
| `calama_topater` | 4 | 1,0 | 0,6 | 4,0 km (200 m) | 16,0 km (800 m) | 53,0 km (2650 m) | 197 km | 5,3 en 2·r |
| `antofagasta` | 4 | 1,0 | 0,6 | 3,0 km (150 m) | 12,0 km (600 m) | 39,8 km (1988 m) | 348 km | 5,3 en 2·r |
| `valparaiso` | 3 | 1,0 | 0,6 | 3,0 km (150 m) | 9,0 km (450 m) | 28,5 km (1425 m) | 50,3 km | 4,0 en 2·r |

El mínimo de det J es 0,61 con el anillo por defecto y 0,51 con el estrecho: ninguna lupa pliega el terreno. Los valores de anisotropía coinciden con los de la enmienda (4,0 / 5,3 por defecto con k = 3 / 4; 5,2 con el anillo estrecho y k = 3).

**Pares más cercanos** (holgura = distancia entre centros − R₁ − R₂; debe ser ≥ 0):

| Par | Distancia | Holgura |
|---|---|---|
| `pisagua` – `dolores` | 28,8 km | 0,9 km |
| `alto_alianza_tacna` – `arica` | 53,0 km | 1,0 km |
| `dolores` – `tarapaca` | 53,5 km | 1,5 km |
| `ilo_pacocha` – `los_angeles_moquegua` | 68,6 km | 2,1 km |
| `tarapaca` – `iquique` | 71,7 km | 2,8 km |
| `dolores` – `iquique` | 63,6 km | 14,2 km |

Todas las reglas se cumplen. Ningún núcleo ampliado se sale de la caja; el más justo es Lima (60 km frente a 68,2 km al borde norte). Con estas holguras, ninguno de los cinco sitios del anillo estrecho puede subir r más de unos 100–200 m sin solaparse con su vecino.

Los centros son **elección de diseño del historiador** (un punto que deja dentro del núcleo todo lo listado), no lugares históricos. Los radios son estimaciones a partir de las distancias entre los puntos de cada sitio más un margen; la extensión exacta de cada campo de batalla queda **pendiente** de contrastar con la cartografía de las obras de referencia (§7).

<a id="lima_callao"></a>
### 3.1 Lima, Callao, Chorrillos y Miraflores (`lima_callao`)

- **Hechos (documentado):** el Callao era el puerto principal y la base naval del Perú, bloqueado por Chile en 1880. Batallas de San Juan y Chorrillos (13 ene 1881) y de Miraflores (15 ene 1881); ocupación de Lima (17 ene 1881).
- **Extensión:** la línea de San Juan medía unos 15 km, del Morro Solar a los cerros de Pamplona, a unos 12 km de Lima; la de Miraflores, unos 12 km, de la costa al río Surco (los dos datos, de Wikipedia en español; el artículo de Miraflores tiene cifras internas que no cuadran: diez reductos a 900 m suman ~8 km).
- **Núcleo:** centro en (−12,115; −77,05) y r = 15 km. Quedan dentro el Callao (12,4 km), Lima (7,7), Miraflores (2,3), Chorrillos (6,6), la coordenada del artículo de la batalla de San Juan (12,2) y la ubicación aproximada de los reductos de Miraflores (4,8). Se agrupan en un solo sitio, como pide ADR-009.
- **k = 4:** es el complejo de batallas más grande de la guerra y la capital peruana. El núcleo ampliado mide 3 km de radio de juego.
- **Fuera del núcleo:** el desembarco de Curayaco y el campamento de Lurín (~24,6 km del centro) quedan en la transición: se desplazan a ~89 km del centro (4,5 km de juego). La isla San Lorenzo tampoco entra (en el mar rige la escala del mapa, ADR-012).
- **Licencia y consecuencia:** el disco R (199 km) sale por el norte de la caja. Hacia el borde norte solo queda dentro lo que está a ≤ 17 km reales del centro: **Ancón** (40 km al norte) y la costa hasta 11,5° S quedan empujados fuera de la caja y recortados. Ancón no fue campo de batalla (es el lugar del tratado de 1883) y se puede contar como texto. Pisco (~200 km) queda fuera de la lupa.
- **Pendiente:** la posición del extremo oriental de la línea de San Juan (cerros de Pamplona) y de Monterrico. Si queda a más de 15 km del centro, hay que subir r o mover el centro (con k = 4, cada km más de r suma 13 km a R; no hay otros sitios cerca, el límite es el borde norte).

<a id="ilo_pacocha"></a>
### 3.2 Ilo y Pacocha (`ilo_pacocha`)

- **Hechos (documentado):** puerto del desembarco chileno de febrero y marzo de 1880, base de la campaña de Tacna y Arica, cabecera del ferrocarril a Moquegua.
- **Núcleo:** r = 2 km sobre el puerto (geografia-1879, precisión A). k = 3, por ser un puerto y no un campo de batalla.

<a id="los_angeles_moquegua"></a>
### 3.3 Los Ángeles y Moquegua (`los_angeles_moquegua`)

- **Hechos (documentado):** combate de Los Ángeles (22 mar 1880), en el cerro de ese nombre, un contrafuerte de la meseta sobre dos quebradas profundas.
- **Coordenadas (discutido):** el artículo de Wikipedia en español da (−17,1506; −70,8984), a unos 6 km de Moquegua, pero su texto dice «unos 20 km al noreste de Moquegua». La ficha de T-009 daba (−17,10; −70,90), precisión B. Se usa la coordenada del artículo y se marca **pendiente**.
- **Núcleo:** centro entre el cerro y la ciudad, r = 5 km (cada uno a ~3,1 km del centro). k = 3. Si la distancia real fuera de 20 km, este núcleo no cubriría el combate y habría que mover el centro al cerro.

<a id="alto_alianza_tacna"></a>
### 3.4 Alto de la Alianza y Tacna (`alto_alianza_tacna`)

- **Hechos (documentado):** batalla del Alto de la Alianza o de Tacna (26 may 1880), en la meseta de Intiorko, rebautizada «Alto de la Alianza» por orden general del 16 may 1880. La línea aliada medía unos 2,5 km, con cuatro reductos (Wikipedia en español). Tras la batalla, Bolivia se retira de la guerra activa.
- **Núcleo:** centro en (−18,006; −70,272), entre la meseta y la ciudad; r = 4,5 km, k = 3, con anillo estrecho (w = 0,5·r, ρc = 0,5; enmienda de ADR-009, Q-012 y Q-013). Quedan dentro la coordenada del artículo en la meseta (2,4 km) y la ciudad de Tacna (2,4 km). Hacia el norte y el oeste de la meseta queda ~2 km de margen para la línea aliada y el despliegue chileno.
- **Límite:** Arica está a 53 km del centro; la holgura entre los dos discos es de 1,0 km.
- **Pendiente:** la orientación exacta de la línea aliada respecto de la coordenada del artículo (si un extremo quedara a más de ~2 km de ella, podría salirse del núcleo).

<a id="arica"></a>
### 3.5 Arica y su Morro (`arica`)

- **Hechos (documentado):** combate naval del *Huáscar* y el *Manco Cápac* en la bahía (27 feb 1880); asalto y toma del Morro de Arica (7 jun 1880). Las defensas peruanas eran las baterías del Morro (alta y baja), las baterías del norte (San José, Santa Rosa y Dos de Mayo) y los fuertes del este: Ciudadela (cerro Chuño) y Este (cerro Aniani). El Morro mide unos 139 m.
- **Núcleo:** centro en (−18,483; −70,315), r = 3,5 km, k = 3, con anillo estrecho (w = 0,5·r, ρc = 0,5; enmienda de ADR-009, Q-012 y Q-013). Quedan dentro la cumbre del Morro (0,96 km) y la ciudad (0,84 km). El radio de 3,5 km deja ~2,5 km de margen alrededor de la ciudad, pensado para los fuertes del este y las baterías del norte.
- **Pendiente:** no se encontraron coordenadas verificadas de los fuertes Ciudadela y del Este ni de las baterías del norte. Por su descripción están al este y al norte de la ciudad, probablemente a menos de 3–4 km del Morro, pero eso **no está verificado**. Si alguno queda a más de 3,5 km del centro, no hay holgura para subir r (1,0 km con el Alto de la Alianza): habría que mover el centro hacia el este. Fuente para resolverlo: los planos del Decreto N.º 18 de 2016 del Ministerio de Educación de Chile (límites de los monumentos Fuerte Ciudadela, Fuerte del Este y Morro de Arica).

<a id="pisagua"></a>
### 3.6 Pisagua (`pisagua`)

- **Hechos (documentado):** desembarco y combate de Pisagua (2 nov 1879). Fuerzas chilenas desembarcaron con oposición frente al puerto, defendido por tropas peruanas y bolivianas, y lo tomaron. Abre la campaña terrestre de Tarapacá.
- **Coordenada:** (−19,599; −70,215), del artículo de Wikipedia en español.
- **Núcleo:** r = 1,8 km, k = 3, con anillo estrecho (w = 0,5·r, ρc = 0,5; enmienda de ADR-009, Q-012 y Q-013). Es el radio máximo que cabe junto a Dolores (holgura de 0,9 km). Antes de la enmienda, Pisagua quedaba sin lupa.
- **Pendiente:** la extensión de las defensas y de las playas del desembarco no está verificada. Algunas relaciones mencionan la caleta de Junín, al sur, como segundo punto de desembarco (**pendiente** de verificar en Bulnes y Sater); si está a más de 1,8 km del puerto, queda **fuera** del núcleo. Su coordenada también es pendiente.

<a id="dolores"></a>
### 3.7 Dolores, cerro San Francisco (`dolores`)

- **Hechos (documentado):** batalla de Dolores o San Francisco (19 nov 1879). Las posiciones chilenas estaban en los cerros San Francisco, Dolores, San Bartolo y Tres Clavos; las fuerzas aliadas se reunieron en la aguada de El Porvenir.
- **Coordenada:** (−19,6667; −69,95), del artículo de Wikipedia en español, que la sitúa a «unos 30 km al sureste de Pisagua» (el validador da 28,8 km). La ficha de T-009 daba (−19,63; −69,97), precisión B.
- **Núcleo:** r = 2,5 km, k = 3, con anillo estrecho (w = 0,5·r, ρc = 0,5; enmienda de ADR-009, Q-012 y Q-013). La extensión del conjunto de cerros es **pendiente**: el artículo no la da.

<a id="tarapaca"></a>
### 3.8 Quebrada de Tarapacá e Iluga (`tarapaca`)

- **Hechos (documentado):** batalla de Tarapacá (27 nov 1879), victoria peruana. Se combatió en la quebrada de Tarapacá (de noreste a suroeste: Quillahuasa, Tarapacá, cuesta de Visagra, San Lorenzo, Huarasiña) y en las alturas (cerro Tarapacá, cerro Redondo, laderas de Visagra). Las columnas chilenas partieron de Iluga, al suroeste.
- **Núcleo:** centro en (−19,94; −69,53), entre el pueblo y Iluga; r = 5,5 km, k = 3, con anillo estrecho (w = 0,5·r, ρc = 0,5; enmienda de ADR-009, Q-012 y Q-013). Quedan dentro el pueblo (3,05 km) e Iluga (4,93 km). Hacia el noreste quedan ~2,5 km de margen más allá del pueblo para Quillahuasa.
- **Ajuste respecto de Q-012:** con el centro anterior (−19,935; −69,525), r = 5,5 km no dejaba a Iluga dentro (5,7 km) y además se solapaba con Iquique. Se movió el centro ~0,8 km hacia Iluga y se bajó el radio de Iquique de 3 a 2,5 km (§3.9).
- **Límite:** holguras de 1,5 km con Dolores y 2,8 km con Iquique. El artículo de Wikipedia no da coordenadas del campo ni de Quillahuasa o Huarasiña: la cobertura completa de la quebrada es **pendiente**.

<a id="iquique"></a>
### 3.9 Iquique (`iquique`)

- **Hechos (documentado):** principal puerto salitrero del Perú. Combate naval de Iquique (21 may 1879): la *Esmeralda* se hundió frente a la ciudad, tras moverse unos 1000 m al norte de su primera posición, a unos 200 m de la playa. Ocupación chilena el 23 nov 1879.
- **Núcleo:** r = 2,5 km, k = 4, anillo por defecto (w = r, ρc = 0,6). Quedan dentro la coordenada del artículo del combate (0,63 km) y la ciudad (0,80 km), con ~1,7 km de margen sobre la bahía. ADR-009 ponía de ejemplo r ≈ 2 km y k = 5; se usa k = 4 y r = 2,5 km para que quepa Tarapacá con Iluga (en la primera versión era r = 3 km).
- **Punta Gruesa** (varada de la *Independencia*, 17 km al sur) queda en el anillo de compresión: se desplaza a ~23,1 km del centro. Es un combate naval y en el mar rige la escala del mapa (ADR-012).

<a id="calama_topater"></a>
### 3.10 Calama y los vados del Loa (`calama_topater`)

- **Hechos (documentado):** combate de Topáter (23 mar 1879). La defensa boliviana cubría los vados de Yalquincha, Topáter, Carbajal y Huaita sobre el Loa. Según Ladislao Cabrera, citado en el artículo, la línea tenía «tres millas de extensión» (~4,8 km), y entre Yalquincha y Carbajal había «más de 3 millas». Murió allí Eduardo Abaroa.
- **Núcleo:** centro entre la coordenada del combate (−22,4649; −68,9051) y Calama, r = 4 km, k = 4. Las dos cifras de la fuente no coinciden del todo: si la línea mide más de 5 km, cada extremo queda a unos 2,5–3 km del centro, dentro del núcleo. Chiu Chiu (~30 km) queda en el anillo.

<a id="antofagasta"></a>
### 3.11 Antofagasta (`antofagasta`)

- **Hechos (documentado):** puerto boliviano de la Compañía de Salitres y Ferrocarril de Antofagasta. Su ocupación chilena, el 14 feb 1879, inicia la guerra. No hubo combate terrestre en la ciudad.
- **Núcleo:** r = 3 km, k = 4. El Salar del Carmen (coordenada **pendiente** en T-009) no entra. Mejillones (61 km) queda fuera de la lupa.

<a id="valparaiso"></a>
### 3.12 Valparaíso (`valparaiso`)

- **Hechos (documentado):** puerto principal y base naval de Chile; lugar del Pacto de Tregua (4 abr 1884). No fue campo de batalla.
- **Núcleo:** r = 3 km, k = 3. Se amplía como puerto y base, para equilibrar el Callao del lado peruano. El núcleo ampliado (9 km) queda a 50 km del borde sur.

## 4. Sitios muy cercanos: anillo estrecho (Q-012, Q-013 y enmienda de ADR-009)

Con el anillo por defecto (w = r, ρc = 0,6), cada lupa necesita un disco libre de 9,5 a 17 veces su radio. En dos zonas los sitios están más juntos de lo que eso permite:

- **Arica y el Alto de la Alianza:** unos 53 km entre los dos centros.
- **Pisagua y Dolores:** unos 29 km. Tarapacá, a su vez, está a 53 km de Dolores y a 72 km de Iquique.

En la primera versión de esta ficha, que cumplía ADR-009 sin cambios, la ciudad de Tacna quedaba fuera del núcleo, Arica tenía un radio justo de 3 km y Pisagua quedaba sin lupa. Feño eligió en **Q-012** el anillo estrecho para los cinco sitios y Luis aceptó en **Q-013** la enmienda de ADR-009 §1b (17-10-2026). Con w = 0,5·r y ρc = 0,5, R baja a 6,5·r con k = 3, y caben todos con su núcleo completo (§3).

**Costo (licencia):** la deformación se concentra más cerca del núcleo. La anisotropía máxima sube de 4,0 a 5,2 con k = 3 (5,3 → 6,8 con k = 4 y 6,5 → 8,5 con k = 5, según la enmienda) y aparece en d = 1,5·r en lugar de 2·r. El anillo se comprime hasta un 50 %. Es decir, en estos cinco sitios las formas justo fuera del núcleo (por ejemplo, el camino de Tacna a Arica o la pampa entre Pisagua y Dolores) se ven más estiradas en sentido tangencial y más comprimidas en sentido radial. **Hay que revisarlo en el mapa de distorsión de T-011**; si algún sitio queda inaceptable, se sube w o ρc en ese sitio, aunque las holguras de §3 dejan muy poco margen para hacerlo sin bajar r.

## 5. Sitios sin lupa dentro de la caja

| Sitio | Coordenada y fuente | Por qué no tiene lupa | Dónde cae |
|---|---|---|---|
| Punta Gruesa | −20,36; −70,18 (geografia-1879, B) | Combate naval: escala del mapa (ADR-012) | Anillo de Iquique: de 17,2 a ~23,1 km |
| Punta Angamos | −23,02; −70,515 (geografia-1879, A) | Combate naval mar adentro (ADR-012) | Fuera de toda lupa |
| Mejillones | −23,10; −70,45 (geografia-1879, A) | Puerto de guano sin combate terrestre | Fuera de toda lupa |
| Ancón | −11,773; −77,176 (geografia-1879, A) | Lugar del tratado, sin combate | Anillo de Lima: **empujado fuera de la caja** |
| Lurín y Curayaco | −12,28; −76,90 (geografia-1879 §6.3, aprox.) | Desembarco sin combate mayor | Transición de Lima: de 24,6 a ~89 km |
| Pisco | −13,71; −76,204 (geografia-1879, A) | Desembarco de 1880 sin combate mayor | Fuera de toda lupa |
| Valle del Mantaro (Concepción, Huancayo, Marcavalle, Pucará) | ~−12,07; −75,21 (Huancayo, **pendiente**) | Campaña de la Breña: evento o texto (ADR-014) | Fuera de toda lupa |

Pisagua, la ciudad de Tacna e Iluga, que en la primera versión estaban en esta tabla, ahora quedan dentro de un núcleo (§3.4, §3.6 y §3.8).

**Nota sobre la Breña.** Parte de la campaña de la Breña (por ejemplo, el combate de La Concepción, 1882, y los de Marcavalle y Pucará) se libró en el valle del Mantaro, que cae **dentro** de la caja geográfica (~11,9–12,2° S, ~75° W). ADR-014 la deja como evento o texto, así que no tiene lupa. Si más adelante se quisiera jugar, habría que añadir un sitio y comprobar que no choca con la lupa de Lima (están a unos 200 km). Las coordenadas de esos combates son **pendientes**.

## 6. Fuera del mapa (ADR-014)

| Sitio | Coordenada | Hecho | Tratamiento |
|---|---|---|---|
| Huamachuco | −7,812; −78,049 | Batalla del 10 jul 1883 | Evento o texto |
| Punta Arenas | −53,16; −70,91 | Llegada de la corbeta *Unión* en 1879 | Evento o texto |

## 7. Fuentes

**Consultadas en esta tarea** (17 oct 2026; artículos de Wikipedia en español, usados solo para coordenadas y extensión de los campos, con sus cifras contrastadas entre sí cuando fue posible):

- «Batalla de San Juan y Chorrillos»: coordenada 12°10′32″ S, 76°57′23″ O; línea de San Juan de ~15 km del Morro Solar a Pamplona. https://es.wikipedia.org/wiki/Batalla_de_San_Juan_y_Chorrillos
- «Batalla de Miraflores»: ubicación aproximada de los reductos (−12,1074; −77,0070); línea de 12 km de la costa al río Surco. https://es.wikipedia.org/wiki/Batalla_de_Miraflores
- «Batalla de Los Ángeles (1880)»: coordenada 17°09′02″ S, 70°53′54″ O. https://es.wikipedia.org/wiki/Batalla_de_Los_%C3%81ngeles_(1880)
- «Batalla del Alto de la Alianza»: coordenada 18°00′01″ S, 70°17′39″ O; línea aliada de ~2500 m. https://es.wikipedia.org/wiki/Batalla_del_Alto_de_la_Alianza
- «Batalla de Arica»: fuertes y baterías (sin coordenadas). https://es.wikipedia.org/wiki/Batalla_de_Arica
- «Morro de Arica»: coordenada 18°28′49″ S, 70°19′25″ O; altura de ~139 m. https://es.wikipedia.org/wiki/Morro_de_Arica
- «Desembarco y combate de Pisagua»: coordenada 19°35′56″ S, 70°12′54″ O. https://es.wikipedia.org/wiki/Desembarco_y_combate_de_Pisagua
- «Batalla de Dolores»: coordenada 19°40′00″ S, 69°57′00″ O; «unos 30 km al sureste de Pisagua». https://es.wikipedia.org/wiki/Batalla_de_Dolores
- «Batalla de Tarapacá»: sin coordenadas del campo; Iluga (−19,9751; −69,5589) por enlace a OpenStreetMap. https://es.wikipedia.org/wiki/Batalla_de_Tarap%C3%A1ca
- «Combate naval de Iquique»: coordenada 20°12′06″ S, 70°09′21″ O. https://es.wikipedia.org/wiki/Combate_naval_de_Iquique
- «Combate de Topáter»: coordenada 22°27′54″ S, 68°54′18″ O; vados y extensión de la línea según Ladislao Cabrera. https://es.wikipedia.org/wiki/Combate_de_Top%C3%A1ter
- `docs/historia/geografia-1879.md` (T-009): coordenadas de ciudades y puertos con precisión A/B y sus fuentes.
- ADR-009 (con su enmienda del 17-10-2026 a §1b), ADR-014, ADR-015, Q-012 y Q-013 (pizarra del proyecto).

**Para verificar lo pendiente** (no consultadas en esta sesión):

- Bulnes, Gonzalo. *Guerra del Pacífico*. 3 vols. Valparaíso, 1911–1919 (planos de las batallas; visión chilena).
- Basadre, Jorge. *Historia de la República del Perú* (visión peruana).
- Querejazu Calvo, Roberto. *Guano, salitre, sangre*. La Paz, 1979 (visión boliviana).
- Sater, William F. *Andean Tragedy: Fighting the War of the Pacific, 1879–1884*. University of Nebraska Press, 2007.
- Decreto N.º 18 de 2016 (Chile), límites de los monumentos históricos Fuerte Ciudadela, Fuerte del Este y Morro de Arica.
- GeoNames y OpenStreetMap, para contrastar todas las coordenadas antes de T-011.

## 8. Pendientes

- [x] Q-012 y Q-013 respondidas; `sitios.json` ajustado con el anillo estrecho en los cinco sitios de la enmienda de ADR-009 §1b.
- [ ] Coordenadas de los fuertes Ciudadela y del Este y de las baterías del norte de Arica (comprobar que quedan a ≤ 3,5 km del centro).
- [ ] Orientación de la línea aliada del Alto de la Alianza respecto de la coordenada del artículo.
- [ ] Extensión de las defensas de Pisagua y coordenada de la caleta de Junín.
- [ ] Extremo oriental de la línea de San Juan (Pamplona) y Monterrico, en Lima.
- [ ] Distancia real entre el cerro Los Ángeles y Moquegua (6 km según la coordenada, 20 km según el texto del artículo).
- [ ] Extensión de los campos de Dolores y de Tarapacá (Quillahuasa, Huarasiña).
- [ ] Coordenadas de los combates de la Breña en el valle del Mantaro, por si se reconsidera ADR-014.
- [ ] Revisar el mapa de distorsión que genere el pipeline (T-011): sobre todo Lima, y los cinco sitios del anillo estrecho, cuya anisotropía máxima es de ~5,2 (k = 3) en d = 1,5·r; con k = 4 o 5 sería de 6,8 u 8,5.
