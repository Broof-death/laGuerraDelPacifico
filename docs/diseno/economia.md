# Economía v1: recursos y edificios

> Tarea: **T-022** (P-004). Agente: game-designer. Estado: propuesta para revisión, con bloqueos abiertos para Feño (§14).
> Fuentes: `docs/historia/recursos-1879.md` (T-035, sobre todo §10 y §11), `docs/historia/geografia-1879.md` (§6–§8), `docs/diseno/unidades.md` (T-016).
> Decisiones que respeta: **ADR-006** (6 jugadores × ~500 unidades, ~300 edificios en total, tick de 20 Hz), **ADR-007** (ResourceDef, BuildingDef, `drop_off`, `pop_provided`, `trains`), **ADR-009** (geografía a 1:20, edificios en metros reales, velocidades de diseño), **ADR-014** (caja del mapa), **ADR-016** (carbón por mar, sin minas en el mapa), **ADR-017** (oficina de paradas y Shanks, tiempos comprimidos, yacimientos según su estado en 1879), **ADR-018/019** (interfaz de cartografía de 1879, colores de facción).
> Convención de marcas: **[J]** valor de juego propuesto aquí; **[Q-xxx]** depende de una pregunta abierta (§14); **[A]** necesita forma de datos que decide el arquitecto (§12.3).

## 1. Objetivo para el jugador

La economía tiene que contar lo mismo que la guerra de 1879: **el desierto vale por lo que sale por sus puertos**.

- El jugador ocupa **yacimientos fijos** del mapa (salitre, guano, plata, cobre, valles y oasis), pone a trabajar operarios en ellos y lleva la carga al **puerto** en carretas o en tren.
- La carga solo se vuelve **pesos** cuando se embarca en un **muelle propio o aliado**. Por eso un **bloqueo naval**, un muelle bombardeado o una vía cortada se notan de inmediato en el ingreso.
- Los **víveres** salen de valles y oasis, o se importan por mar con pesos. Los **pesos** pagan casi todo. El **carbón** llega por mar (ADR-016) y es el cuello de botella de la escuadra y de las oficinas Shanks.
- Decisiones del jugador: barato y seguro (oficina de paradas, carretas) contra caro y productivo pero dependiente del mar (Shanks, tren, carbón); defender puertos y vías contra atacar los del enemigo.

**Para el prototipo bastan 3 recursos, 4 cargas y 19 edificios** (§2 y §4). Agua, fundiciones, ingenios y captura de edificios quedan para v2 (§13).

## 2. Recursos

### 2.1 Recursos acumulables (ResourceDef con `kind = STOCK`)

Son los únicos que aparecen en la barra superior y los únicos que pagan costos (`EntityDef.cost`). Coinciden con V/P/C de unidades.md §4.

| id | Nombre visible | Abrev. | De dónde sale | En qué se gasta | Inicial (todas las facciones) [J] |
|---|---|---|---|---|---|
| `viveres` | Víveres | V | Haciendas de valle, chacras de oasis, importación por un muelle (§5.4) | Unidades (sobre todo de tierra), poblaciones, centros | 400 |
| `pesos` | Pesos | P | Ingreso base de cada centro (60 P/min) y exportación de cargas por un muelle | Casi todos los edificios, unidades, carbón importado, víveres importados | 600 |
| `carbon` | Carbón | C | Solo por mar, en una carbonera (§6) | Buques (costo) y oficina Shanks (consumo por minuto) | 200 Chile y Perú; 0 Bolivia |

Los recursos iniciales de cada facción los puede retocar T-031 en `FactionDef.start_resources`.

### 2.2 Cargas (no acumulables; ResourceDef con `kind = CARGO`) [A]

Las cargas **no** se guardan en el tesoro del jugador: existen en la **bodega** de un extractor, encima de un porteador (carreta o tren) o en la bodega de un muelle. Al embarcarse se convierten en pesos.

| id | Nombre visible | Valor al embarcarse | Densidad (unidades de carga por unidad de volumen) | Sale de |
|---|---|---|---|---|
| `salitre` | Salitre | 1 P por unidad | 1,0 | Oficina de paradas, oficina Shanks |
| `guano` | Guano | 1 P por unidad | 1,0 | Covadera (embarca sola, §4.4) |
| `plata` | Plata en barra | 1 P por unidad | 4,0 (barras: mucho valor por viaje) | Mina de plata |
| `cobre` | Cobre en barra | 1 P por unidad | 1,5 | Mina de cobre |

- Todas valen 1 P por unidad para que las tasas de producción se lean directamente en pesos por minuto. Lo que diferencia a la plata y al cobre es la **densidad**: una carreta lleva 200 de volumen, es decir 200 de salitre o 800 de plata.
- El agua **no** es un recurso en v1 (unidades.md §6.3). Ver §13.

## 3. Reglas generales

### 3.1 Operarios y puestos de trabajo [Q-020]

- Los extractores tienen **puestos** (`worker_slots`). El jugador envía operarios al edificio; cada operario que entra ocupa un puesto y **deja de ser una entidad visible** (como las tropas embarcadas en un transporte, unidades.md §5.7), pero **sigue contando su pop**.
- La producción es proporcional a los puestos ocupados: `producción/min = puestos_ocupados × tasa_por_operario × rendimiento_del_yacimiento × RITMO`.
- El jugador puede sacar operarios (orden «Desalojar»: salen por la puerta, de a 1 por segundo).
- Si el edificio se destruye, los operarios salen con vida por la puerta, a razón de todos en 1 s.
- `RITMO` es una constante global de la partida (1,0 en «medio»; ver §9.4 y Q-019).

### 3.2 Construir

- Lo construyen operarios. `build_time` es el tiempo con **1 operario**. Con n operarios (máximo 5): `tiempo = build_time / (1 + 0,5 × (n − 1))`. Dos operarios: ×0,67; cinco: ×0,33.
- El costo se paga completo al poner los cimientos. Cancelar devuelve el 100 %. Un edificio destruido no devuelve nada.
- **Reparar:** 1 operario repara 10 de vida por segundo y cobra, proporcionalmente, el 25 % del costo del edificio por la vida que repone.
- **Zona de influencia:** todo edificio se coloca a ≤ 3000 m de un centro propio o a ≤ 1000 m de un almacén o fuerte propio (3 km de juego = ~60 km reales). Así no se construye al otro lado del mapa sin presencia.
- **Tope de 50 edificios por jugador** (cimientos incluidos), consecuencia de ADR-006 (~300 edificios en total con 6 jugadores). Las vías férreas son del mapa y no cuentan.

### 3.3 Yacimientos

- Los yacimientos son **fijos**, en su ubicación histórica (datos del mapa, T-011, con el historiador). No se crean donde no los había.
- Cada yacimiento tiene un número de **sitios** (cuántos extractores admite) y un **rendimiento** (factor sobre la tasa). Son infinitos: no se agotan en una partida.
- Un sitio ocupado por un edificio de otro jugador no se puede usar hasta que ese edificio se destruye (queda una ruina 60 s y después el sitio queda libre).

### 3.4 Acopio de víveres

Las haciendas y chacras **solo producen** si están a ≤ 1500 m de un centro o almacén propio (el acopio). Si se destruye el almacén, la hacienda se detiene y muestra «sin acopio». Los víveres van directo al tesoro, sin porteadores: en v1 el transporte visible queda para las cargas de exportación.

### 3.5 Presupuesto de entidades (ADR-006)

| Entidad | ¿Cuenta pop? | Tope | Motivo |
|---|---|---|---|
| Operario dentro de un edificio | Sí (1) | Dentro de los 500 de pop | No es entidad visible: ahorra entidades |
| Carreta, tren | Sí (1 y 2) | Dentro de los 500 de pop | Garantiza que un jugador nunca pase de 500 entidades móviles |
| Vapor carbonero | No | 1 en tránsito por carbonera, 2 carboneras por jugador → ≤ 2 | Lo genera el contrato, no el jugador |
| Recua de la remesa del altiplano (solo si se acepta en Q-023) | No | 1 en tránsito | Igual |
| Lanchas del muelle | — | — | **Solo cosméticas en el cliente**, no son entidades de la simulación |
| Edificios | — | 50 por jugador | ADR-006: ~300 en total |

Peor caso: 6 × (500 + 3) + 300 = **3318 entidades**, por debajo del margen medido de 4500 de ADR-006.

## 4. Edificios

### 4.1 Tabla de edificios v1

Medidas de huella en celdas de **16 m** (TERRAIN_CELL de ADR-009; a confirmar por el arquitecto, Q-025). Vida y armadura usan las reglas de combate de unidades.md §5 (daño = max(0, daño − armadura)); todos los edificios son objetivo LAND.

| id | Nombre visible | Colocación | Costo (V / P) | build_time (s) | max_hp | armor | Huella (celdas) | Puestos | Hace | Tope por jugador |
|---|---|---|---|---|---|---|---|---|---|---|
| `centro` | Intendencia (Chile), Prefectura (Perú y Bolivia) | LAND | 200 / 600 | 180 | 4000 | 5 | 6 × 6 | — | Entrena operarios; +50 pop; ingreso base 60 P/min; acopio de víveres; zona de influencia 3000 m | 3 |
| `poblacion` | Población | LAND | 50 / 100 | 40 | 600 | 2 | 4 × 4 | — | +50 pop | 9 |
| `almacen` | Almacén de intendencia | LAND | 0 / 120 | 30 | 800 | 3 | 3 × 3 | — | Acopio de víveres; zona de influencia 1000 m | — |
| `cuartel` | Cuartel | LAND | 0 / 200 | 60 | 1500 | 4 | 6 × 4 | — | Entrena las 6 unidades de tierra de unidades.md (salvo el operario) | — |
| `astillero` | Arsenal | COAST | 0 / 500 | 120 | 2500 | 5 | 8 × 4 | — | Entrena los buques de la facción | 2 |
| `agencia_fletes_bolivia` | Agencia de fletes | COAST | 0 / 250 | 60 | 1200 | 3 | 4 × 3 | — | Solo Bolivia: fleta transportes (Q-011) | 2 |
| `fuerte` | Fuerte (batería de costa) | LAND | 50 / 400 | 120 | 2500 | 6 | 5 × 5 | — | Arma `canon_costa` (§4.3); zona de influencia 1000 m | — |
| `muelle` | Muelle de embarque | COAST | 0 / 250 | 60 | 1500 | 4 | 2 × 8 | — | Recibe cargas y las exporta (500 P/min); importa víveres (§5.4) | — |
| `carbonera` | Carbonera | COAST | 0 / 250 | 60 | 1000 | 3 | 4 × 3 | — | Recibe el carbón por mar (§6) | 2 |
| `estacion` | Estación de ferrocarril | sobre vía histórica | 0 / 200 | 45 | 800 | 3 | 4 × 2 | — | Entrena trenes; recibe cargas (§5.3) | — |
| `hacienda` | Hacienda | sitio de valle | 0 / 100 | 45 | 800 | 2 | 8 × 8 | 5 | 20 V/min por operario | — |
| `chacra_oasis` | Chacra | sitio de oasis | 0 / 60 | 30 | 400 | 1 | 4 × 4 | 3 | 15 V/min por operario | — |
| `oficina_paradas` | Oficina de paradas | sitio de salitre | 0 / 200 | 60 | 1000 | 2 | 6 × 5 | 6 | 15 salitre/min por operario; sin carbón | — |
| `oficina_shanks` | Oficina Shanks | sitio de salitre | 0 / 600 | 150 | 2000 | 4 | 10 × 7 | 8 | 30 salitre/min por operario; consume 10 C/min | — |
| `covadera` | Covadera de guano | sitio de guano (costa) | 0 / 150 | 60 | 900 | 2 | 4 × 3 | 5 | 18 guano/min por operario; embarca sola (§4.4) | — |
| `mina_plata` | Mina de plata | sitio de plata | 0 / 300 | 90 | 1000 | 3 | 4 × 4 | 6 | 30 plata/min por operario | — |
| `mina_cobre` | Mina de cobre | sitio de cobre | 0 / 250 | 75 | 1000 | 3 | 4 × 4 | 6 | 15 cobre/min por operario (incluye la fundición en v1) | — |

Notas:

- **Centro inicial:** cada jugador empieza con 1 centro, 6 operarios y los recursos de §2.1. Con un centro tiene 50 de pop; los 500 se alcanzan con 3 centros y 7 poblaciones, o 1 centro y 9 poblaciones.
- **Cuartel único en v1:** entrena guardia nacional, infantería de línea, Colorados (Bolivia), caballería y artillería de campaña. Separarlo (caballeriza, maestranza) es una opción de v2 si hace falta ritmo de progresión.
- **Astillero por facción:** Chile entrena transporte, torpedera, corbeta y blindado de batería; Perú, transporte, torpedera, corbeta y monitor de torre (FactionDef y `trains`). Bolivia no tiene astillero sino la agencia de fletes (solo transporte).
- **Bolivia sin puerto propio:** puede embarcar sus cargas y comprar carbón en muelles y carboneras **aliados** (§5.2 y §6.4).

### 4.2 Mejora de la oficina de paradas a Shanks [Q-022]

Propuesta recomendada (pendiente de Feño): la oficina de paradas se puede **mejorar** a Shanks por **450 P y 120 s**. Durante la mejora sigue produciendo como oficina de paradas; al terminar pasa a 8 puestos y empieza a consumir carbón. Si se responde que no, la Shanks solo se construye nueva en un sitio libre.

### 4.3 Fuerte: artillería de costa

La artillería de costa es un edificio (unidades.md §3.1). Arma propuesta:

| id del arma | damage | range (m) | min_range (m) | cooldown (s) | DPS | target_domains | splash_radius (m) |
|---|---|---|---|---|---|---|---|
| `canon_costa` | 140 | 220 | 30 | 12,0 | 11,7 | LAND, SEA | 4 |

Visión del fuerte: 230 m. Alcance 220 m: supera por 20 m a los cañones pesados de los buques (200 m), así que un fuerte domina su bahía, como en Arica y el Callao.

| Enfrentamiento (sin reparar) | Resultado | Cálculo |
|---|---|---|
| Fuerte contra 1 blindado de batería (duelo a 200 m) | **Gana el fuerte** en t = 240 s y queda con 106 de vida | Fuerte: 140 − 22 = 118 por disparo, 21 disparos (t = 0…240) contra 2400. Blindado: 120 − 6 = 114 cada 12 s, 21 disparos hasta t = 240 = 2394 contra 2500 (le faltaba 1 disparo). Si el blindado se queda a más de 220 m, ninguno dispara |
| Fuerte contra 1 monitor | **Gana el fuerte** en t = 168 s y queda con 628 | 140 − 20 = 120, 15 disparos (t = 0…168). Monitor: 150 − 6 = 144 cada 14 s → 13 disparos hasta t = 168 = 1872 |
| Fuerte contra blindado + monitor | **Ganan los buques** en ~130 s; el fuerte, que dispara al monitor, lo deja con ~500 | Buques: 9,5 + 10,3 = 19,8 DPS → 2500 / 19,8 ≈ 126 s, más el redondeo de los disparos |
| Fuerte contra corbetas | Las corbetas no lo alcanzan desde fuera de los 220 m (sus cañones llegan a 150 m); si se acercan le hacen 20 − 6 = 14 por disparo | El fuerte le hace 137 por disparo a una corbeta: la hunde en 8 disparos (84 s) |
| 15 infanterías de línea dispersas lo asaltan | **Gana la infantería** en ~6 min, perdiendo ~5 en la aproximación | De 220 a 30 m: 190 m a 3,5 m/s = 54 s bajo fuego (5 disparos, 1 baja por disparo si van dispersas). Dentro de los 30 m el fuerte no dispara. 10 infantes: 10 × (8 − 6) / 3 = 6,7 DPS → 2500 / 6,7 ≈ 375 s |
| 30 infanterías de línea dispersas | **Gana la infantería** en ~3 min | Llegan 25: 16,7 DPS → 150 s |

Lectura: el fuerte es la defensa costera barata (450 de costo frente a 1050 de un blindado), gana a un buque solo y pierde ante una escuadra o un asalto de infantería numeroso y disperso, como el Morro de Arica en junio de 1880. La artillería de campaña lo daña poco (24 cada 8 s) y tiene que ponerse dentro de su alcance para hacerlo.

### 4.4 Covadera

La covadera está en la costa y **embarca su propio guano** (sin porteadores ni muelle), con un tope de 100 P/min. Le afectan el bloqueo y el bombardeo igual que a un muelle (§7). Por eso un buque enemigo frente a Huanillos o Pabellón de Pica la apaga, como el 17 de abril de 1879.

## 5. Cadena logística: yacimiento → porteador → puerto

### 5.1 Bodega del extractor

- Cada extractor de carga (oficinas, minas) guarda lo que produce en su **bodega** (600 de volumen). Con la bodega llena deja de producir y muestra «bodega llena».
- Los porteadores asignados a un extractor van y vienen solos entre la bodega y el **destino más cercano alcanzable**: una estación propia (si la oficina está a ≤ 400 m de ella) o un muelle propio o aliado.

### 5.2 Porteadores (UnitDef nuevos) [J]

| id | Nombre | Se entrena en | Costo (V / P) | build_time (s) | pop | max_hp | armor | speed táctica / marcha (m/s) | Capacidad (volumen) | Carga/descarga |
|---|---|---|---|---|---|---|---|---|---|---|
| `carreta` | Carreta de mulas | Centro, oficinas, minas | 40 / 40 | 20 | 1 | 60 | 0 | 3 / 8 | 200 | 10 s + 10 s |
| `tren` | Tren salitrero | Estación | 0 / 250 | 40 | 2 | 400 | 2 | — / 20 (solo por la vía) | 1000 | 15 s + 15 s |

- Ninguno lleva armas. La carreta pasa a velocidad táctica con enemigos a ≤ 150 m (la misma regla de marcha de unidades.md §2.1). El tren no frena.
- La carreta se dibuja como carreta en la pampa y como **recua de mulas** en terreno de cuesta o altiplano (solo cambio visual).
- El tren solo circula por **vías históricas** del mapa (Iquique–La Noria, Pisagua–Zapiga/Dolores, Antofagasta–Salar del Carmen; trazados de T-011 con el historiador). En v1 no se construyen vías nuevas.
- Una oficina a ≤ 400 m de una estación **le entrega sin porteadores** (el desvío particular de la oficina). La estación del puerto debe estar a ≤ 300 m de un muelle propio y le pasa la carga sin porteadores.

**Rendimiento por porteador** (ciclo = ida y vuelta + carga y descarga; terreno llano):

| Distancia a destino (m de juego) | Equivale a (km reales) | Carreta: ciclo (s) | Carreta: P/min (salitre) | Carreta: P/min (plata) | Tren: ciclo (s) | Tren: P/min |
|---|---|---|---|---|---|---|
| 500 | 10 | 145 | 82,8 | 331 | 80 | 750 |
| 1000 | 20 | 270 | 44,4 | 178 | 130 | 462 |
| 1500 | 30 | 395 | 30,4 | 122 | 180 | 333 |
| 2000 | 40 | 520 | 23,1 | 92 | 230 | 261 |
| 3000 | 60 | 770 | 15,6 | 62 | 330 | 182 |
| 10 000 (Caracoles–Antofagasta) | 200 | 2520 | 4,8 | 19 | — | — |

Cálculo: carreta, `ciclo = 2·d / 8 + 20`; tren, `ciclo = 2·d / 20 + 30`; `P/min = capacidad × densidad × 60 / ciclo`. Los multiplicadores de terreno de unidades.md §12 alargan el ciclo de la carreta (camino ×1,2 lo acorta).

### 5.3 Muelle

- Recibe cargas de porteadores, estaciones de puerto y de cualquier jugador aliado. La carga entra en su **bodega** (3000) y sale en lanchas a razón de **500 P/min** por muelle: los pesos se acreditan al **dueño de la carga**.
- Con la bodega llena, los porteadores esperan en el muelle.
- Un puerto que exporta más de 500 P/min necesita un segundo muelle (por ejemplo, Iquique con 2 Shanks y 2 paradas: 660 P/min). Eso hace de los muelles un blanco que vale la pena defender.
- Las lanchas que van y vuelven entre el muelle y los mercantes fondeados son un efecto del cliente.

### 5.4 Importar víveres

Un muelle propio puede **importar víveres** (interruptor en su panel): hasta **120 V/min** a **1,5 P por V** (180 P/min). Es la forma de alimentar a un ejército en un puerto del desierto sin valles cerca (Antofagasta, Iquique), como se hacía en 1879. El bloqueo la detiene.

### 5.5 Ejemplos de rutas

| Ruta | Distancia de juego aprox. | Con carretas | Con tren |
|---|---|---|---|
| Cantón La Noria → Iquique | ~1500 m | 1 oficina de paradas (90 P/min): 3 carretas | 1 Shanks (240 P/min): 1 tren basta (333 P/min) |
| Cantón de Zapiga → Pisagua | ~2000 m [P, trazado] | 1 paradas: 4 carretas | 1 Shanks: 1 tren (261 P/min) |
| Salar del Carmen → Antofagasta | ~750 m | 1 paradas: 2 carretas (~60 P/min c/u) | No compensa la estación |
| Caracoles → Antofagasta (plata, ×0,5) | ~10 000 m | 1 mina (90 P/min): 5 carretas | Sin vía |
| Corocoro → Arica (cobre) | ~22 000 m | 1 mina (90 P/min): harían falta ~28 carretas (ciclo de 92 min, 300 de cobre por viaje = 3,3 P/min cada una) | Sin vía |

La última fila muestra el problema de Bolivia (§10).

## 6. Carbón (ADR-016)

### 6.1 Carbonera y contrato

- Cada carbonera tiene un **contrato** automático: cada **180 s** sale un **vapor carbonero** con **150 C** hacia ella. Rinde **50 C/min por carbonera**. Máximo 2 carboneras por jugador → 100 C/min.
- **Precio por facción** (se paga al salir el vapor):

| Facción | Origen | Precio | Costo por viaje | Entrada |
|---|---|---|---|---|
| Chile | Lota y Coronel, por el borde sur (ADR-016) | 0,5 P por C | 75 P | 4000 m al **sur** de la carbonera, por el mar |
| Perú | Importado (fuera del mapa) | 2 P por C | 300 P | 4000 m al **oeste** de la carbonera, mar adentro |
| Bolivia | Importado, en carboneras aliadas | 2 P por C | 300 P | Igual que Perú |

- **Licencia (compresión, cubierta por L2 de ADR-017):** el vapor no recorre los ~1000 km de Lota a Antofagasta; aparece a 4000 m de juego (~80 km reales) de la carbonera, en la dirección de su origen, y llega en 160 s a marcha. Así Chile conserva su ventaja histórica (precio) sin esperar 40 minutos por viaje.
- Si no hay pesos para el viaje, el contrato espera (aviso «sin fondos para el carbón»).

### 6.2 Vapor carbonero [Q-021]

| id | max_hp | armor | speed táctica / marcha | radius | vision_range | Armas | pop |
|---|---|---|---|---|---|---|---|
| `vapor_carbonero` | 400 | 1 | 10 / 25 | 10 | 120 | ninguna | 0 (no lo controla el jugador) |

Propuesta recomendada (pendiente de Feño, Q-021): el vapor es una entidad visible y **se puede hundir**. Si se hunde se pierden el carbón y el pago, y el siguiente sale 180 s después. Un buque enemigo armado a ≤ 400 m de la entrada o de la carbonera detiene la salida (§7). Así la guerra de corso tiene un blanco, como la captura del *Rímac* por el *Huáscar* en julio de 1879.

### 6.3 Quién consume carbón [Q-024]

- **Buques:** el costo C de unidades.md §4.2 (transporte 50, torpedera 55, corbeta 100, blindado 250, monitor 220). Los buques no consumen carbón al navegar en v1.
- **Oficina Shanks:** 10 C/min mientras trabaja (ADR-017). **Sin carbón se detiene** (aviso «sin carbón»); vuelve a trabajar en cuanto hay.
- Propuesta recomendada (pendiente, Q-024): **nada más en v1**. El tren y las condensadoras quedan sin consumo.
- Corresponde corregir en unidades.md §4 la frase «C = carbón (solo buques)» por «entre las unidades, solo los buques cuestan carbón; la oficina Shanks también lo consume» (comentado en T-016; este documento no edita unidades.md).

### 6.4 Lectura de balance del carbón

| Gasto | C | Tiempo con 1 carbonera (50 C/min) | Con 2 (100 C/min) |
|---|---|---|---|
| 1 corbeta | 100 | 2 min | 1 min |
| 1 blindado | 250 | 5 min | 2,5 min |
| Escuadra chilena de ejemplo: 1 blindado, 4 corbetas, 6 torpederas, 3 transportes | 1130 | 22,6 min | 11,3 min |
| 2 oficinas Shanks durante 10 min | 200 | 4 min | 2 min |

- Un astillero que construye corbetas sin parar gasta 100 C cada 70 s = **86 C/min**; con blindados, **107 C/min**. Con 2 carboneras (el máximo) se sostiene **un** astillero naval en producción continua. El carbón es el ritmo de la escuadra, como en 1879.
- Chile paga 565 P por la escuadra de ejemplo; Perú, 2260 P (unos 2,5 min de ingreso de mitad de partida). Es la ventaja chilena de ADR-016.

## 7. Bloqueo naval y ataque costero

### 7.1 Bloqueo

Se evalúa a 1 Hz para cada muelle, covadera y carbonera, en un radio de **400 m** (la bahía ampliada ×5 mide ~750 m, unidades.md §2.2):

| Situación en el radio | Estado | Exportación, importación de víveres, contrato de carbón |
|---|---|---|
| Ningún buque enemigo armado | Libre | 100 % |
| Buque enemigo armado y algún buque armado propio o aliado | Disputado | 50 % |
| Buque enemigo armado y ningún buque armado propio o aliado | **Bloqueado** | 0 %: la carga se acumula en la bodega del muelle; el vapor carbonero espera en la entrada |

- «Buque armado» = unidad SEA con al menos un arma (el transporte y el vapor carbonero no cuentan).
- Un fuerte no rompe el bloqueo por sí solo: tiene que hundir o ahuyentar al buque. Su alcance de 220 m cubre la mitad interior del radio de 400 m, así que un bloqueador puede mantenerse a 220–400 m, fuera de su alcance, como hizo la escuadra frente a Iquique (5 de abril de 1879).
- El bloqueo se levanta en el tick siguiente a que deje de cumplirse la condición.

### 7.2 Ataque costero

- Muelles, covaderas, carboneras y astilleros son objetivo LAND al alcance de los cañones navales. Ejemplos: un blindado destruye un muelle (1500, armadura 4) en 13 disparos (116 cada 12 s), en t = **144 s**; una corbeta, con cañones ligeros (16 cada 3 s), en ≈ **280 s**.
- Destruir el muelle pierde lo que hubiera en su bodega.

## 8. Interacción con el combate

| Acción | Cómo se hace | Efecto |
|---|---|---|
| Atacar porteadores | Cualquier unidad armada | La carreta (60 de vida) cae con 8 tiros de fusil; se pierde su carga |
| **Cortar la vía** | Orden nueva `CUT_RAIL` [A]: una unidad de tierra queda 10 s sobre una celda de vía | Corta un tramo de 64 m: los trenes se detienen ante él. Un operario lo repara en 15 s (orden `REPAIR`). Se dibuja como rieles levantados |
| Destruir el almacén | Combate normal | Las haciendas que dependían de él se detienen («sin acopio») |
| Bloquear un puerto | §7.1 | Ingreso por exportación a 0 o a la mitad |
| Bombardear muelles y covaderas | §7.2 | Igual que en Huanillos y Pabellón de Pica |
| Interceptar el carbón | §6.2 [Q-021] | Sin carbón no hay escuadra ni Shanks |
| Ocupar yacimientos | Destruir el extractor enemigo y construir encima tras la ruina (60 s) | El salitre cambia de manos, como Tarapacá en noviembre de 1879 |

Los operarios dentro de un edificio no combaten ni pueden ser atacados; salen vivos si el edificio cae (§3.1).

## 9. Balance

Supuestos comunes: `RITMO = 1,0` («medio»); operario 50 V; víveres y pesos valen lo mismo para comparar; carbón según el precio de cada facción.

### 9.1 Ingreso por edificio lleno

| Edificio | Puestos | Producción bruta / min | Consumo / min | Neto (Perú) | Neto (Chile) | Por operario |
|---|---|---|---|---|---|---|
| Hacienda | 5 | 100 V | — | 100 V | 100 V | 20 V |
| Chacra de oasis | 3 | 45 V | — | 45 V | 45 V | 15 V |
| Oficina de paradas | 6 | 90 P | — | 90 P | 90 P | 15 P |
| Oficina Shanks | 8 | 240 P | 10 C | 220 P | 235 P | 27,5–29,4 P |
| Covadera (rendimiento 1,0) | 5 | 90 P | — | 90 P | 90 P | 18 P |
| Covadera en Chincha (0,1) | 5 | 9 P | — | 9 P | 9 P | 1,8 P |
| Mina de plata en Caracoles (0,5) | 6 | 90 P | — | 90 P | 90 P | 15 P |
| Mina de cobre | 6 | 90 P | — | 90 P | 90 P | 15 P |
| Centro (ingreso base) | — | 60 P | — | 60 P | 60 P | — |

### 9.2 Amortización

Tiempo para recuperar la inversión desde que el edificio está lleno (inversión ÷ neto por minuto). Las carretas y trenes son los de una distancia de 1500 m.

| Edificio | Inversión | Neto / min | Amortización |
|---|---|---|---|
| Hacienda: edificio + 5 operarios | 100 P + 250 V = 350 | 100 | **3,5 min** |
| Chacra: edificio + 3 operarios | 60 + 150 = 210 | 45 | 4,7 min |
| Paradas: edificio + 6 operarios | 200 + 300 = 500 | 90 | 5,6 min |
| Paradas + 3 carretas (240) | 740 | 90 | **8,2 min** |
| Shanks (Perú): edificio + 8 operarios | 600 + 400 = 1000 | 220 | 4,5 min |
| Shanks (Perú) + 8 carretas (640) | 1640 | 220 | 7,5 min |
| Shanks (Perú) + 2 estaciones y 1 tren (650) | 1650 | 220 | **7,5 min** |
| Shanks (Chile) + estaciones y tren | 1650 | 235 | 7,0 min |
| Segunda Shanks en la misma vía (+1 tren, 250) | 1250 | 220 | 5,7 min |
| Mejora paradas → Shanks (si se acepta Q-022): 450 P + 2 operarios | 550 | +130 (Perú) | 4,2 min |
| Covadera + 5 operarios | 150 + 250 = 400 | 90 | 4,4 min |
| Covadera en Chincha | 400 | 9 | 44 min (no compensa: ADR-017) |
| Mina de plata en Caracoles + 6 operarios + 5 carretas (10 km) | 300 + 300 + 400 = 1000 | 90 | 11,1 min (en declive: ADR-017) |

### 9.3 Paradas contra Shanks

| | Oficina de paradas | Oficina Shanks |
|---|---|---|
| Costo y tiempo | 200 P, 60 s | 600 P, 150 s |
| Producción llena | 90 P/min | 240 P/min (−10 C/min) |
| P/min por pop, con carretas a 1500 m | 90 / (6 + 3) = **10,0** | 220 / (8 + 8) = 13,8 (Perú) |
| P/min por pop, con tren a 1500 m | — (no compensa la estación) | 220 / (8 + 2) = **22,0** (Perú); 23,5 (Chile) |
| Depende del mar | No | Sí: carbón (bloqueo de la carbonera la apaga) |
| Cuándo conviene | Al principio, en cantones lejos de la vía, cuando el mar está en disputa | Mitad de partida, junto a una vía y con el carbón asegurado |

La Shanks rinde **2,2 veces** más por pop que la paradas si tiene tren. Con un tope de 500 de pop eso es lo que decide, no el costo en pesos. Bloquear la carbonera de un rival con Shanks le quita el 100 % de esa producción en ~1 minuto (cuando se acaba su reserva de carbón).

### 9.4 Ritmo de la partida (simulación) [Q-019]

Script reproducible: `docs/diseno/balance/sim_economia.mjs` (`node sim_economia.mjs RITMO PRECIO_CARBON`). Un jugador sin pérdidas desarrolla su economía en este orden: hacienda, paradas, muelle, hacienda, cuartel, hacienda, paradas, carbonera, Shanks con tren, hacienda, segundo centro, covadera, ... hasta 110 operarios y 10 de pop en porteadores, y gasta el resto en infantería de línea. Poblaciones cuando le faltan ≤ 8 de pop. Es una partida de «desarrollo» sin ataques: el peor caso para tener ejército pronto.

| RITMO | Plan económico completo (min) | 30 militares | 100 | 200 | 300 | 380 (pop 500) | Ingreso a los 40 min (V + P acumulados) |
|---|---|---|---|---|---|---|---|
| 0,75 (lento) | 25,3 | 26,4 | 33,5 | 41,0 | 49,1 | **55,5** | 17 058 V + 16 396 P |
| **1,0 (medio, propuesta)** | 21,7 | 22,3 | 27,7 | 33,2 | 39,3 | **44,1** | 24 674 V + 22 760 P |
| 1,4 (rápido) | 17,1 | 18,6 | 22,9 | 28,1 | 32,8 | **36,4** | 38 137 V + 32 736 P |

Con el carbón a 0,5 P (Chile) la curva es casi igual (pop 500 en 44,1 min): la ventaja chilena del carbón está en la escuadra, no en el salitre.

**Ingreso de un jugador con la economía completa** (medio, Perú, minuto ~25): **1000 V/min y ~920 P/min netos** con 110 operarios (22 % del pop). Comparación con unidades.md §4:

| Gasto | Costo | Tiempo de ingreso completo |
|---|---|---|
| 1 infantería de línea | 60 V / 30 P | 3,6 s de víveres |
| 100 infanterías de línea (100 pop) | 6000 V / 3000 P | 6 min (limitan los víveres) |
| 1 blindado | 100 V / 700 P / 250 C | 46 s de pesos; 2,5–5 min de carbón |
| Un cuartel sin parar (infantería) | 164 V/min + 82 P/min | 6 cuarteles saturan 1000 V/min |
| 9 poblaciones (de 50 a 500 de pop) | 450 V / 900 P | ~1 min |

Lectura: en «medio», un ejército de 100 a los ~28 min y el tope de pop a los ~44 min en desarrollo puro. Un jugador que ataque antes (1 cuartel desde el minuto 4) puede tener ~15–20 soldados hacia el minuto 10 (estimación: 1 cuartel produce 1 cada 22 s si tiene ~160 V/min). Encaja con los tiempos de desplazamiento de unidades.md §2.1 (5–20 min en marcha dentro de una región): la primera ofensiva llega hacia el minuto 15–20 y las partidas duran **60–90 min**. Feño decide el ritmo en Q-019.

### 9.5 Tope de población

- Se mantiene **500 de pop por jugador** (unidades.md §5.8 y ADR-006). Los operarios y porteadores ocupan ~120 (24 %); quedan ~380 para el ejército y la escuadra.
- La población la dan los centros (50 cada uno, máximo 3) y las poblaciones (50 cada una, máximo 9): con 1 centro y 9 poblaciones se llega exactamente a 500.

## 10. Bolivia [Q-023]

**El problema (recursos-1879 §10.4):** si Bolivia pierde el litoral (Antofagasta, Mejillones, Tocopilla, Cobija, Caracoles), dentro de la caja del mapa solo le quedan Corocoro (cobre) y los oasis del altiplano y de Atacama. Su plata (Huanchaca, Potosí) y sus valles (Cochabamba, Chuquisaca) están fuera del mapa (ADR-014). Y Corocoro queda a ~22 km de juego de Arica: una carreta tarda 92 min en ir y volver (§5.5), así que su cobre casi no rinde.

Si la partida empieza antes del 14 de febrero de 1879 (posiciones iniciales aún sin decidir), Bolivia sí tiene el litoral al comienzo y el problema aparece cuando lo pierde. Propuesta recomendada en Q-023 (opción A), con estas cifras:

- **Remesa del altiplano:** cada 120 s entra por el borde este del mapa (camino de La Paz a Tacna, por el paso de Tacora o Charaña) una **recua** (entidad sin armas, 300 de vida, 6 m/s, pop 0, máximo 1 en tránsito) con **300 P y 200 V** hacia el centro o almacén boliviano más cercano: **150 P/min y 100 V/min**, equivalente a 1,5 oficinas de paradas y una hacienda llenas, sin operarios. Se puede atacar (se pierde lo que lleva) y llega más tarde cuanto más lejos esté el centro boliviano del borde este.
- Bolivia embarca en muelles aliados (§5.3) y compra carbón en carboneras aliadas (§6.1).

## 11. Cómo se ve en pantalla

Interfaz de cartografía de 1879 (ADR-018): papel crema, tinta sepia, tipografía y símbolos de las leyendas de época.

- **Barra superior:** Víveres, Pesos y Carbón con su cantidad y su **saldo por minuto** (+/−, en verde oliva o rojo óxido), y `Pop 123/500`. Al pasar el ratón, el desglose: «Exportación 660 · Base 60 · Importación de víveres −180 · Carbón −100».
- **Avisos** (cartela con sonido, una vez por causa y cada 30 s como mucho): «Iquique bloqueado», «Muelle de Pisagua destruido», «Vía cortada en La Noria», «Oficina Shanks sin carbón», «Vapor carbonero hundido», «Bodega llena», «Sin acopio».
- **Panel de un extractor:** puestos ocupados como figuras (●●●○○), producción por minuto actual y máxima, rendimiento del yacimiento («Caracoles: en declive, ×0,5»), barra de la bodega, porteadores asignados y botones **Agregar operario**, **Desalojar**, **Entrenar carreta** y, en paradas, **Mejorar a Shanks** (si se acepta Q-022).
- **Panel del muelle:** bodega, exportación por minuto, interruptor **Importar víveres**, estado (Libre / Disputado / Bloqueado) con un icono de ancla, tachada si está bloqueado.
- **Mapa y minimapa:** yacimientos con símbolos de época (rombo de salitre, punto de guano, cruz de mina, espiga de valle); vías férreas como línea de tren de los mapas de 1879, con una marca roja donde están cortadas; rutas de los porteadores como línea punteada de tinta al seleccionar un extractor; círculo del radio de bloqueo (400 m) y de la zona de influencia al colocar un edificio.
- **En el mundo 3D** (provisional según ADR-005, final según recursos-1879 §11): humo bajo en la paradas, chimenea con humo negro en la Shanks (sin humo si está parada), carretas y trenes moviéndose, lanchas cosméticas entre muelle y mercantes fondeados, pila de carbón que crece en la carbonera. Las figuras de operarios trabajando son animación del edificio, no entidades.

### 11.1 Representación provisional (ADR-005, ADR-007)

| id | placeholder_shape | placeholder_size (m, x·y·z) | placeholder_label |
|---|---|---|---|
| centro | BOX | 96 · 12 · 96 | CENTRO |
| poblacion | BOX | 64 · 6 · 64 | POB. |
| almacen | BOX | 48 · 6 · 48 | ALM. |
| cuartel | BOX | 96 · 8 · 64 | CUARTEL |
| astillero, agencia_fletes_bolivia | BOX | 128 · 12 · 64 / 64 · 8 · 48 | ARSENAL / FLETES |
| fuerte | CYLINDER | 80 · 8 · 80 | FUERTE |
| muelle | BOX | 32 · 2 · 128 | MUELLE |
| carbonera | BOX | 64 · 6 · 48 | CARBÓN |
| estacion | BOX | 64 · 6 · 32 | EST. |
| hacienda | BOX | 128 · 4 · 128 | HACIENDA |
| chacra_oasis | BOX | 64 · 3 · 64 | CHACRA |
| oficina_paradas | BOX | 96 · 5 · 80 | PARADAS |
| oficina_shanks | BOX (+ CYLINDER de 40 m de chimenea) | 160 · 10 · 112 | SHANKS |
| covadera | BOX | 64 · 6 · 48 | GUANO |
| mina_plata / mina_cobre | BOX | 64 · 10 · 64 | PLATA / COBRE |
| carreta | BOX | 2 · 2 · 5 | CAR. |
| tren | BOX | 3 · 4 · 40 | TREN |
| vapor_carbonero | HULL | 9 · 6 · 55 | CARBON. |

Las huellas son el **núcleo** del edificio en metros reales (ADR-009); el campamento y las canchas de una oficina son decoración que puede salirse de la huella sin bloquear el paso.

## 12. Datos para Godot

### 12.1 ResourceDef (`data/resources/`)

| id | display_name | kind [A] | density [A] | export_value [A] | ui_color [J] |
|---|---|---|---|---|---|
| viveres | Víveres | STOCK | — | — | #6B7A3A (verde oliva) |
| pesos | Pesos | STOCK | — | — | #B8892E (ocre dorado) |
| carbon | Carbón | STOCK | — | — | #2E2A26 (negro carbón) |
| salitre | Salitre | CARGO | 1,0 | 1 P | #E8E2D0 (blanco salitre) |
| guano | Guano | CARGO | 1,0 | 1 P | #8C7A5B (pardo) |
| plata | Plata en barra | CARGO | 4,0 | 1 P | #A8A8A8 (gris plata) |
| cobre | Cobre en barra | CARGO | 1,5 | 1 P | #B05A2C (cobre) |

### 12.2 BuildingDef (`data/buildings/comun/` salvo los de facción)

Campos existentes de ADR-007: `cost`, `build_time`, `max_hp`, `armor`, `vision_range`, `weapons`, `footprint`, `placement`, `trains`, `pop_provided`, `drop_off`.

| id | cost | build_time | max_hp | armor | vision_range | footprint | placement | trains | pop_provided | drop_off |
|---|---|---|---|---|---|---|---|---|---|---|
| centro | V 200, P 600 | 180 | 4000 | 5 | 120 | (6, 6) | LAND | operario, carreta | 50 | viveres |
| poblacion | V 50, P 100 | 40 | 600 | 2 | 40 | (4, 4) | LAND | — | 50 | — |
| almacen | P 120 | 30 | 800 | 3 | 60 | (3, 3) | LAND | — | 0 | viveres |
| cuartel | P 200 | 60 | 1500 | 4 | 60 | (6, 4) | LAND | guardia_nacional, infanteria_linea, caballeria, artilleria_campana (+ colorados_bolivia en Bolivia) | 0 | — |
| astillero_chile | P 500 | 120 | 2500 | 5 | 150 | (8, 4) | COAST | transporte, torpedera, corbeta, blindado_bateria_chile | 0 | — |
| astillero_peru | P 500 | 120 | 2500 | 5 | 150 | (8, 4) | COAST | transporte, torpedera, corbeta, monitor_torre_peru | 0 | — |
| agencia_fletes_bolivia | P 250 | 60 | 1200 | 3 | 100 | (4, 3) | COAST | transporte | 0 | — |
| fuerte | V 50, P 400 | 120 | 2500 | 6 | 230 | (5, 5) | LAND | — | 0 | — |
| muelle | P 250 | 60 | 1500 | 4 | 100 | (2, 8) | COAST | — | 0 | salitre, guano, plata, cobre |
| carbonera | P 250 | 60 | 1000 | 3 | 80 | (4, 3) | COAST | — | 0 | carbon |
| estacion | P 200 | 45 | 800 | 3 | 60 | (4, 2) | LAND (vía) | tren | 0 | salitre, plata, cobre |
| hacienda | P 100 | 45 | 800 | 2 | 50 | (8, 8) | LAND (valle) | — | 0 | — |
| chacra_oasis | P 60 | 30 | 400 | 1 | 50 | (4, 4) | LAND (oasis) | — | 0 | — |
| oficina_paradas | P 200 | 60 | 1000 | 2 | 60 | (6, 5) | LAND (salitre) | carreta | 0 | — |
| oficina_shanks | P 600 | 150 | 2000 | 4 | 60 | (10, 7) | LAND (salitre) | carreta | 0 | — |
| covadera | P 150 | 60 | 900 | 2 | 60 | (4, 3) | COAST (guano) | — | 0 | guano (propio) |
| mina_plata | P 300 | 90 | 1000 | 3 | 60 | (4, 4) | LAND (plata) | carreta | 0 | — |
| mina_cobre | P 250 | 75 | 1000 | 3 | 60 | (4, 4) | LAND (cobre) | carreta | 0 | — |

Todos los tiempos son múltiplos de 0,05 s (ADR-006). El astillero se divide en dos `.tres` por facción porque `trains` cambia; también podría ser uno común si FactionDef filtra `trains` por `FactionDef.units` (lo decide el arquitecto).

### 12.3 Campos nuevos que hacen falta (forma: arquitecto, Q-025)

| Campo propuesto | Dónde | Tipo | Valores de este documento |
|---|---|---|---|
| `kind` | ResourceDef | enum {STOCK, CARGO} | §12.1 |
| `density`, `export_value` | ResourceDef | float, int | §12.1 |
| `site_type` | BuildingDef | StringName ("", valle, oasis, salitre, guano, plata, cobre, via) | §12.2 |
| `worker_slots` | BuildingDef | int | §4.1 |
| `produces`, `rate_per_worker` | BuildingDef | ResourceDef, float (por min) | §4.1 |
| `upkeep` | BuildingDef | Dictionary[ResourceDef, float] (por min) | Shanks: carbón 10 |
| `cargo_buffer` | BuildingDef | int (volumen) | Extractores 600; muelle 3000 |
| `export_rate` | BuildingDef | float (P/min) | Muelle 500; covadera 100 |
| `influence_radius` | BuildingDef | float (m) | Centro 3000; almacén y fuerte 1000 |
| `max_per_player` | BuildingDef | int (0 = sin tope) | §4.1 |
| `upgrades_to`, `upgrade_cost`, `upgrade_time` | BuildingDef | BuildingDef, Dictionary, float | Paradas → Shanks (si Q-022) |
| `base_income` | BuildingDef | Dictionary[ResourceDef, float] (por min) | Centro: pesos 60 |
| `carry_capacity`, `rail_only` | UnitDef | int, bool | Carreta 200 / false; tren 1000 / true |
| `coal_price`, `coal_entry_dir` | FactionDef | float, enum {SUR, OESTE} | §6.1 |
| `start_resources` | FactionDef (ya existe) | — | §2.1 |
| Yacimientos | Datos del mapa (T-011) | lista: tipo, posición, sitios, rendimiento | §12.4 |
| Constantes | Simulación | — | `RITMO` 1,0; tope de edificios 50; radio de bloqueo 400 m; contrato de carbón 150 C / 180 s; entrada a 4000 m; corte de vía 10 s / reparación 15 s |

### 12.4 Yacimientos (datos del mapa, a completar con el historiador en T-011) [J]

| Tipo | Yacimiento | Sitios | Rendimiento | Nota |
|---|---|---|---|---|
| salitre | Cantón de Zapiga (Pisagua) | 2 | 1,0 | |
| salitre | Cantón de Negreiros | 2 | 1,0 | |
| salitre | Cantón de La Noria (Iquique) | 3 | 1,0 | Vía Iquique–La Noria |
| salitre | Cantón de Pozo Almonte | 2 | 1,0 | |
| salitre | Cantón de Lagunas | 2 | 1,0 | |
| salitre | Salar del Carmen (Antofagasta) | 2 | 1,0 | Vía de la CSFA |
| salitre | El Toco (Tocopilla) | 2 | 1,0 | Coordenada [P] |
| guano | Pabellón de Pica | 1 | 1,0 | |
| guano | Huanillos | 1 | 1,0 | |
| guano | Punta de Lobos | 1 | 1,0 | Coordenada [P] |
| guano | Mejillones | 1 | 1,0 | Zona compartida en 1879 |
| guano | Islas de Chincha | 1 | **0,1** | Casi agotadas (ADR-017) |
| plata | Caracoles | 2 | **0,5** | En declive (ADR-017) |
| plata | Huantajaya | — | — | Actividad en 1879 [P]: no se incluye hasta que el historiador la verifique |
| cobre | Tocopilla | 1 | 1,0 | |
| cobre | Chañaral | 1 | 1,0 | |
| cobre | Norte Chico (Carrizal, Tamaya) | 2 | 1,0 | Coordenadas [P] |
| cobre | Corocoro | 2 | 1,0 | Lejos de la costa (§10) |
| valle | Rímac y Lima | 6 | 1,0 | |
| valle | Cañete | 4 | 1,0 | |
| valle | Ica | 4 | 1,0 | |
| valle | Moquegua | 3 | 1,0 | |
| valle | Tacna | 4 | 1,0 | |
| valle | Azapa (Arica) | 2 | 1,0 | |
| valle | Aconcagua | 6 | 1,0 | |
| oasis | Pica | 2 | 1,0 | |
| oasis | Quebrada de Tarapacá | 1 | 1,0 | |
| oasis | Calama | 2 | 1,0 | |
| oasis | Chiu Chiu | 1 | 1,0 | |
| oasis | San Pedro de Atacama | 2 | 1,0 | |
| oasis | Quillagua | 1 | 1,0 | |

## 13. Casos borde

- **Bodega llena en el muelle y en el extractor:** el extractor se detiene; nada se pierde.
- **Muelle destruido con carretas en camino:** las carretas buscan el siguiente muelle propio o aliado alcanzable; si no hay, vuelven al extractor y esperan. La carga de la bodega del muelle se pierde.
- **Aliado que deja de serlo** (si el modo de juego lo permite): la carga ya entregada en su muelle se paga a su dueño; las carretas en camino se redirigen.
- **Sin pesos para el carbón:** el contrato espera; no hay deuda.
- **Shanks sin carbón:** se detiene; sus operarios siguen dentro (el jugador puede desalojarlos). Avisa una vez.
- **Bloqueo sin bodega libre:** las carretas esperan en el muelle (pueden ser blanco de los cañones del buque).
- **Varios jugadores en el mismo yacimiento:** cada sitio admite un edificio; el primero que pone los cimientos lo ocupa.
- **Corte de vía con un tren encima:** el tren se detiene antes del tramo cortado; si el tramo se corta bajo el tren, sigue hasta el final de su vagón y se detiene.
- **Tope de 50 edificios:** el botón de construir se desactiva con el aviso «Tope de edificios»; los cimientos cuentan.
- **Tope de pop con porteadores:** entrenar una carreta o un tren requiere pop libre igual que una unidad militar; la cola espera sin cobrar (unidades.md §9).
- **Operarios dentro de un edificio que cambia de dueño:** en v1 no hay captura; si se destruye, salen por la puerta.
- **Covadera bloqueada:** su guano se acumula en la bodega (600) y luego se detiene.
- **Precisión:** la producción se acumula en float cada tick (por ejemplo, 20 V/min = 0,0167 V por tick) y se acredita en enteros; la parte fraccionaria se guarda.

## 14. Preguntas abiertas para Feño (bloqueos)

| Id | Pregunta | Recomendación | Bloquea T-022 |
|---|---|---|---|
| Q-019 | Ritmo general de la economía | Medio (RITMO = 1,0): pop 500 en ~44 min; partidas de 60–90 min | Sí |
| Q-020 | Cómo trabajan los operarios | Asignados dentro del edificio (no visibles, cuentan pop) | Sí |
| Q-021 | ¿Se pueden interceptar los vapores carboneros? | Sí, son visibles y se pueden hundir | No |
| Q-022 | ¿La oficina de paradas se puede mejorar a Shanks? | Sí, por 450 P y 120 s, sin dejar de producir | No |
| Q-023 | Cómo compensar a Bolivia | Remesa del altiplano por el borde este, interceptable | No (puede ir a T-031) |
| Q-024 | ¿El carbón se usa fuera de los buques y la Shanks? | No en v1 | No |
| Q-025 (Luis) | Forma de las cargas y campos nuevos en ADR-007 | Ampliar ResourceDef con `kind` y BuildingDef con los campos de §12.3 | No |

Mientras no se respondan, los valores recomendados son los que usa este documento. Si la respuesta es otra, se ajustan las secciones marcadas con el Id de la pregunta.

## 15. Licencias y apartamientos de la historia

| Licencia | Por qué | Registro |
|---|---|---|
| Tiempos comprimidos de extracción, transporte y embarque | Jugabilidad | ADR-017 (L2) |
| El vapor carbonero aparece a 4 km de la carbonera en vez de venir desde Lota o desde Europa | Que el carbón no tarde 40 min por viaje | Cubierta por L2 (ADR-017) y ADR-016 |
| La mina de cobre incluye la fundición | Simplificar v1 | Diseño (este documento) |
| Una carga vale 1 P por unidad para todos los minerales | Legibilidad; la plata vale más por viaje (densidad) | Diseño |
| Yacimientos infinitos | Partidas de 60–90 min; la producción de 1879 no se agotaba en meses | Diseño |
| Remesa del altiplano (si se acepta Q-023) | Bolivia sin recursos dentro del mapa | Diseño; el historiador debe revisar la ruta |

## 16. Para v2

- **Agua:** aguadas y condensadoras como radio de abasto; fuera de él, desgaste de vida de las tropas (ficha de ejércitos §5). Las condensadoras consumirían carbón.
- Fundiciones de cobre separadas, ingenios azucareros, construcción de vías nuevas, consumo de carbón al navegar.
- **Captura de edificios** (Chile explotando las oficinas peruanas tras ocupar Tarapacá).
- Derechos de exportación como mecánica de facción (Chile cobra 40 centavos por quintal en 1879; recursos-1879 §2.6) en T-031.
- Víveres importados más baratos para Chile (trigo del valle central), si T-031 lo pide.

## 17. Decisiones registradas (propuestas, área diseño)

- **ADR-020:** tres recursos acumulables y cuatro cargas que se convierten en pesos al embarcarse (§2, §5).
- **ADR-021:** presupuesto de entidades de la economía: porteadores con pop, lanchas cosméticas, tope de 50 edificios (§3.5).
- **ADR-022:** suministro de carbón por mar con carbonera y contrato (§6; concreta ADR-016).
- **ADR-023:** cifras de las dos oficinas salitreras y rendimiento de los yacimientos (§4, §9, §12.4; concreta ADR-017).
- **ADR-024:** bloqueo naval, ataque costero, corte de vías y fuerte de costa (§4.3, §7, §8).

## 18. Pendiente

- Respuestas de Q-019 a Q-025 y ajuste de las secciones afectadas.
- Yacimientos, vías históricas y distancias reales en los datos del mapa (T-011, con el historiador); las distancias de §5.5 son aproximadas.
- Corrección del texto «C = carbón (solo buques)» y del tope de pop en unidades.md (comentado en T-016).
- Bonificaciones económicas de facción (T-031).
- Primera prueba jugable: ajustar tasas y costos con `sim_economia.mjs` y con partidas reales.
