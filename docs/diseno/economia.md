# Economía v1: recursos y edificios

> Tarea: **T-022** (P-004). Agente: game-designer. Estado: en revisión (2.ª ronda, con las correcciones de QA). Feño respondió Q-019 a Q-024 (§14) y decidió las observaciones 4 (qué buques bloquean) y 8 (Bolivia y el litoral) de QA; queda abierta Q-025 para Luis (forma de los datos).
> Fuentes: `docs/historia/recursos-1879.md` (T-035, sobre todo §10 y §11), `docs/historia/geografia-1879.md` (§6–§8), `docs/diseno/unidades.md` (T-016).
> Decisiones que respeta: **ADR-006** (6 jugadores × ~500 unidades, ~300 edificios en total, tick de 20 Hz), **ADR-007** (ResourceDef, BuildingDef, `drop_off`, `pop_provided`, `trains`), **ADR-009** (geografía a 1:20, edificios en metros reales, velocidades de diseño), **ADR-014** (caja del mapa), **ADR-016** (carbón por mar, sin minas en el mapa), **ADR-017** (oficina de paradas y Shanks, tiempos comprimidos, yacimientos según su estado en 1879), **ADR-018/019** (interfaz de cartografía de 1879, colores de facción).
> Convención de marcas: **[J]** valor de juego propuesto aquí; **[Q-xxx]** decidido por Feño en esa pregunta (§14); **[A]** necesita forma de datos que decide el arquitecto (§12.3).

## 1. Objetivo para el jugador

La economía tiene que contar lo mismo que la guerra de 1879: **el desierto vale por lo que sale por sus puertos**.

- El jugador ocupa **yacimientos fijos** del mapa (salitre, guano, plata, cobre, valles y oasis), pone a trabajar operarios en ellos y lleva la carga al **puerto** en carretas o en tren.
- La carga solo se vuelve **pesos** cuando se embarca en un **muelle propio o aliado**. Por eso un **bloqueo naval**, un muelle bombardeado o una vía cortada se notan de inmediato en el ingreso.
- Los **víveres** salen de valles y oasis, o se importan por mar con pesos. Los **pesos** pagan casi todo. El **carbón** llega por mar (ADR-016) y es el cuello de botella de la escuadra y de las oficinas Shanks.
- Decisiones del jugador: barato y seguro (oficina de paradas, carretas) contra caro y productivo pero dependiente del mar (Shanks, tren, carbón); defender puertos y vías contra atacar los del enemigo.

**Para el prototipo bastan 3 recursos, 4 cargas, 17 edificios y 2 porteadores** (§2 y §4). Agua, fundiciones, ingenios y captura de edificios quedan para v2 (§16).

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
- El agua **no** es un recurso en v1 (unidades.md §6.3). Ver §16.

## 3. Reglas generales

### 3.1 Operarios y puestos de trabajo (Q-020, respondida)

- Los extractores tienen **puestos** (`worker_slots`). El jugador envía operarios al edificio; cada operario que entra ocupa un puesto y **deja de ser una entidad visible** (como las tropas embarcadas en un transporte, unidades.md §5.7), pero **sigue contando su pop**.
- La producción es proporcional a los puestos ocupados: `producción/min = puestos_ocupados × tasa_por_operario × rendimiento_del_yacimiento × RITMO`.
- El jugador puede sacar operarios (orden «Desalojar»: salen por la puerta, de a 1 por segundo).
- Si el edificio se destruye, los operarios salen con vida por la puerta, a razón de todos en 1 s.
- `RITMO` es una constante global de la partida (1,0, ritmo «medio», elegido por Feño en Q-019; ver §9.4).

### 3.2 Construir

- Lo construyen operarios. `build_time` es el tiempo con **1 operario**. Con n operarios (máximo 5): `tiempo = build_time / (1 + 0,5 × (n − 1))`. Dos operarios: ×0,67; cinco: ×0,33.
- El costo se paga completo al poner los cimientos. Un edificio destruido no devuelve nada.
- **Cimientos:** nacen con el 10 % de `max_hp` y ganan vida en proporción al avance de la obra. **Cancelar devuelve el 80 %.** Unos cimientos que pasan **60 s sin ningún operario trabajando** se cancelan solos (con el mismo 80 %). Así, ocupar un sitio de yacimiento con cimientos cuesta el 20 % del edificio cada vez y no dura más de 60 s sin gente; y unos cimientos de oficina Shanks (200 de vida) caen con 25 tiros de fusil.
- **Reparar:** 1 operario repara **3 de vida por segundo**; como máximo **3 reparadores** por edificio (9 de vida por segundo). **No se puede reparar un edificio que recibió daño en los últimos 15 s** (más que el cooldown del arma más lenta que dispara contra tierra, la `torre_10` del monitor, 14 s). Cobra, proporcionalmente, el 25 % del costo del edificio por la vida que repone.
  - Consecuencia: mientras un buque o una tropa sigue disparando, no hay reparación, y los cálculos de §4.3 y §7.2 valen tal cual. La reparación sirve **entre** ataques: un fuerte a media vida (1250) vuelve a estar entero en 139 s con 3 operarios y cuesta 0,25 × 450 × 0,5 ≈ 56 de recursos.
  - Si el atacante dispara de forma intermitente para dejar reparar al defensor, pierde: para que haya reparación tiene que dejar de disparar más de 15 s, y en ese tiempo 3 reparadores solo recuperan (t − 15) × 9 de vida.
- **Zona de influencia:** todo edificio se coloca a ≤ 3000 m de un centro propio o a ≤ 1000 m de un almacén o fuerte propio (3 km de juego = ~60 km reales). Así no se construye al otro lado del mapa sin presencia.
- **Tope de 50 edificios por jugador** (cimientos incluidos), consecuencia de ADR-006 (~300 edificios en total con 6 jugadores). Las vías férreas son del mapa y no cuentan.
- **Distancia a un edificio:** toda distancia entre una unidad y un edificio (alcance de armas en ambos sentidos, visión, radio de bloqueo, zona de influencia, acopio, entregas) se mide **desde el centro de la unidad hasta el punto más cercano del borde de la huella** del edificio (un rectángulo). Un edificio que dispara lo hace desde ese borde. Así el alcance mínimo de 30 m del fuerte es una franja de 30 m alrededor de sus muros, no un círculo dentro de su propia huella de 80 × 80 m.
- **Asalto a un edificio con alcance mínimo:** con una orden de atacar (ATTACK o ATTACK_MOVE hacia él) a un edificio cuya arma tiene `min_range`, las unidades de tierra no se detienen a su alcance normal (40 m la infantería, unidades.md §5.2–5.3), sino a **min_range − 5 m** del borde (25 m en el fuerte), dentro del ángulo muerto, y desde ahí disparan. Si solo lo atacan por adquisición automática, se detienen a su alcance normal, dentro de la franja de tiro del fuerte.

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
| Recua de la remesa del altiplano (solo Bolivia, Q-023) | No | ≤ 3 en tránsito (sale 1 cada 120 s y tarda 300 s, §10) | Igual |
| Lanchas del muelle | — | — | **Solo cosméticas en el cliente**, no son entidades de la simulación |
| Edificios | — | 50 por jugador | ADR-006: ~300 en total |

Entidades sin pop por jugador: hasta 2 en Chile y Perú (vapores) y hasta 5 en Bolivia (2 vapores y 3 recuas). Peor caso con 6 jugadores, como máximo 2 por facción (Q-002): 4 × (500 + 2) + 2 × (500 + 5) + 300 = **3318 entidades**, por debajo del margen medido de 4500 de ADR-006.

## 4. Edificios

### 4.1 Tabla de edificios v1

Medidas de huella en celdas de **16 m** (TERRAIN_CELL de ADR-009; a confirmar por el arquitecto en Q-025, abierta). Vida y armadura usan las reglas de combate de unidades.md §5 (daño = max(0, daño − armadura)); todos los edificios son objetivo LAND.

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
- **Bolivia y el litoral** (decisión de Feño sobre la obs. 8 de QA): mientras conserve costa propia, Bolivia construye **muelle y carbonera como las demás facciones**. Si la pierde, embarca sus cargas en muelles **aliados** (§5.3) y compra carbón en carboneras **aliadas** (§6.1). La remesa del altiplano (§10) existe desde el inicio de la partida, tenga o no litoral.

### 4.2 Mejora de la oficina de paradas a Shanks (Q-022, respondida)

Decidido por Feño en Q-022: la oficina de paradas se puede **mejorar** a Shanks por **450 P y 120 s**. Durante la mejora sigue produciendo como oficina de paradas; al terminar pasa a 8 puestos y empieza a consumir carbón. La Shanks también se puede construir nueva en un sitio libre.

### 4.3 Fuerte: artillería de costa

La artillería de costa es un edificio (unidades.md §3.1). Arma propuesta:

| id del arma | damage | range (m) | min_range (m) | cooldown (s) | DPS | target_domains | splash_radius (m) |
|---|---|---|---|---|---|---|---|
| `canon_costa` | 140 | 220 | 30 | 12,0 | 11,7 | LAND, SEA | 4 |

Visión del fuerte: 230 m. Alcance 220 m: supera por 20 m a los cañones pesados de los buques (200 m), así que un fuerte domina su bahía, como en Arica y el Callao.

Distancias medidas desde el borde de la huella del fuerte (§3.2). La reparación no actúa en ninguna fila: el fuerte recibe daño al menos cada 14 s y la regla de §3.2 exige 15 s sin daño.

| Enfrentamiento | Resultado | Cálculo |
|---|---|---|
| Fuerte contra 1 blindado de batería (duelo a 200 m) | **Gana el fuerte** en t = 240 s y queda con 106 de vida | Fuerte: 140 − 22 = 118 por disparo, 21 disparos (t = 0…240) contra 2400. Blindado: 120 − 6 = 114 cada 12 s, 21 disparos hasta t = 240 = 2394 contra 2500 (le faltaba 1 disparo). Si el blindado se queda a más de 220 m, ninguno dispara |
| Fuerte contra 1 monitor | **Gana el fuerte** en t = 168 s y queda con 628 | 140 − 20 = 120, 15 disparos (t = 0…168). Monitor: 150 − 6 = 144 cada 14 s → 13 disparos hasta t = 168 = 1872 |
| Fuerte contra blindado + monitor | **Ganan los buques** en ~130 s; el fuerte, que dispara al monitor, lo deja con ~500 | Buques: 9,5 + 10,3 = 19,8 DPS → 2500 / 19,8 ≈ 126 s, más el redondeo de los disparos |
| Fuerte contra corbetas | Las corbetas no lo alcanzan desde fuera de los 220 m (sus cañones llegan a 150 m); si se acercan le hacen 20 − 6 = 14 por disparo | El fuerte le hace 137 por disparo a una corbeta: la hunde en 8 disparos (84 s) |
| 15 infanterías de línea **dispersas** (más de 4 m entre figuras), con orden de atacar el fuerte | **Gana la infantería** en t ≈ 428 s (~7 min), perdiendo 5 | Regla de asalto (§3.2): se detienen a 25 m del muro. De 220 a 25 m: 195 m a 3,5 m/s = 55,7 s; el fuerte dispara en t = 0, 12, 24, 36 y 48 (5 disparos, 1 baja cada uno: 140 > 60 de vida). Llegan 10: descargas de 10 × (8 − 6) = 20 cada 3 s → 125 descargas → t = 55,7 + 124 × 3 = 427,7 s |
| 30 infanterías de línea dispersas | **Gana la infantería** en t ≈ 203 s (~3,4 min), perdiendo 5 | Llegan 25: 50 por descarga → 50 descargas → t = 55,7 + 49 × 3 = 202,7 s |
| 15 infanterías **agrupadas** | **Gana el fuerte**: mueren las 15 antes de llegar | Cada disparo: 140 + hasta 4 × 70 (área de 4 m) → hasta 5 bajas; 5 disparos = 25 bajas posibles |
| 15 infanterías sin la orden de asalto (adquisición automática) | **Gana el fuerte** con ~2060 de vida | Se detienen a 40 m, dentro de la franja de tiro (30–220 m). En la aproximación (180 m, 51 s) caen 5; llegan 10. El fuerte mata 1 cada 12 s, mientras ellos hacen 4 descargas de n × 2 por intervalo: 8 × (10 + 9 + … + 1) = 440 de daño en 120 s |
| 10 caballerías dispersas (20 pop, 1000 V / 600 P) | **Gana la caballería** en t ≈ 138 s (~2,3 min), perdiendo 3 | El sable (2,5 m) está dentro del ángulo muerto. De 220 a 2,5 m: 217,5 m a 7 m/s = 31,1 s → disparos en t = 0, 12 y 24 (3 bajas: 140 > 80). Llegan 7: 7 × (11 − 6) = 35 cada 1,5 s → 72 golpes → t = 31,1 + 71 × 1,5 = 137,6 s |

Lectura: el fuerte es la defensa costera barata (450 de costo frente a 1050 de un blindado). Gana a un buque solo y pierde ante dos buques de línea o ante un asalto numeroso y disperso, como el Morro de Arica en junio de 1880.

- **Contra tierra, la caballería asalta mejor que la infantería:** 10 caballerías (20 pop, 1600 de recursos) lo toman en ~2,3 min; 30 infantes (30 pop, 2700 de recursos) tardan ~3,4 min. Es razonable: la caballería cruza la franja de tiro en la mitad de tiempo y su sable trabaja en el ángulo muerto. Si en la prueba jugable resulta dominante, la palanca es la armadura del fuerte contra el sable (por ejemplo, armadura 8: el sable haría 3 y la infantería 0) o un daño contra edificios por arma; no se cambia ahora.
- La artillería de campaña lo daña poco (30 − 6 = 24 cada 8 s) y tiene que ponerse dentro de su franja de tiro (alcance 120 m < 220 m) para hacerlo.

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
| Bolivia | Importado: en su carbonera mientras tenga costa; si no, en carboneras aliadas | 2 P por C | 300 P | Igual que Perú |

- **Contratos en carboneras aliadas:** cada carbonera admite **2 contratos**, el de su dueño y el de 1 aliado. Cada contrato tiene su propio vapor (150 C cada 180 s, pagado por quien lo firma, a su precio de facción), así que el aliado no le quita carbón al dueño. Un jugador puede tener como máximo **2 contratos** en total (propios o en carboneras aliadas): sigue habiendo ≤ 2 vapores por jugador (§3.5). El carbón llega al tesoro de quien firmó. Si la carbonera aliada se destruye o deja de ser aliada, el contrato se cancela (el vapor en camino se pierde, sin reembolso, como si lo hundieran).
- **Bolivia empieza con 0 C** (§2.1). Para fletar su primer transporte (50 C) necesita antes una carbonera propia (mientras tenga costa) o un contrato en una aliada; la agencia de fletes y la carbonera son edificios de costa, así que mientras Bolivia pueda tener una agencia también puede tener una carbonera. Sin costa propia ni aliado con carbonera, **Bolivia no puede fletar transportes**: es explícito y coherente con la historia (después de 1879 dependió de los buques peruanos). Su primer transporte cuesta, en la práctica, 50 V / 150 P / 50 C más 250 P de la carbonera y 300 P del primer viaje de carbón (que trae 150 C, suficientes para 3 transportes).
- **Licencia (compresión, cubierta por L2 de ADR-017):** el vapor no recorre los ~1000 km de Lota a Antofagasta; aparece a 4000 m de juego (~80 km reales) de la carbonera, en la dirección de su origen, y llega en 160 s a marcha. Así Chile conserva su ventaja histórica (precio) sin esperar 40 minutos por viaje.
- Si no hay pesos para el viaje, el contrato espera (aviso «sin fondos para el carbón»).

### 6.2 Vapor carbonero (Q-021, respondida)

| id | max_hp | armor | speed táctica / marcha | radius | vision_range | Armas | pop |
|---|---|---|---|---|---|---|---|
| `vapor_carbonero` | 400 | 1 | 10 / 25 | 10 | 120 | ninguna | 0 (no lo controla el jugador) |

Decidido por Feño en Q-021: el vapor es una entidad visible, sin armas, y **se puede hundir**. Si se hunde se pierden el carbón y el pago, y el siguiente sale 180 s después. Si la carbonera está bloqueada (§7.1: buque enemigo con armas contra tierra a ≤ 400 m), el vapor espera en la entrada. Así la guerra de corso tiene un blanco, como la captura del *Rímac* por el *Huáscar* en julio de 1879.

### 6.3 Quién consume carbón (Q-024, respondida)

- **Buques:** el costo C de unidades.md §4.2 (transporte 50, torpedera 55, corbeta 100, blindado 250, monitor 220). Los buques no consumen carbón al navegar en v1.
- **Oficina Shanks:** 10 C/min mientras trabaja (ADR-017). **Sin carbón se detiene** (aviso «sin carbón»); vuelve a trabajar en cuanto hay.
- Decidido por Feño en Q-024: **nada más en v1**. El tren y las condensadoras no consumen carbón; las condensadoras llegan con el agua en v2 (§16).
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
| Ningún buque enemigo bloqueador | Libre | 100 % |
| Buque enemigo bloqueador y algún buque bloqueador propio o aliado | Disputado | 50 % |
| Buque enemigo bloqueador y ningún buque bloqueador propio o aliado | **Bloqueado** | 0 %: la carga se acumula en la bodega del muelle; el vapor carbonero espera en la entrada |

- **«Buque bloqueador»** (decisión de Feño sobre la obs. 4 de QA) = unidad SEA con al menos un arma cuyo `target_domains` incluye LAND: en v1, **corbeta, blindado de batería y monitor de torre**. La torpedera (su torpedo solo apunta a SEA), el transporte y el vapor carbonero **no bloquean ni disputan**. Así no hay bloqueo barato con torpederas, y para disputar un bloqueo hace falta al menos una corbeta.
- Se calcula con la misma regla en ambos sentidos: un buque propio solo «disputa» si también es bloqueador.
- Un fuerte no rompe el bloqueo por sí solo: tiene que hundir o ahuyentar al buque. Su alcance de 220 m cubre la mitad interior del radio de 400 m, así que un bloqueador puede mantenerse a 220–400 m, fuera de su alcance, como hizo la escuadra frente a Iquique (5 de abril de 1879).
- El bloqueo se levanta en el tick siguiente a que deje de cumplirse la condición.

### 7.2 Ataque costero

- Muelles, covaderas, carboneras y astilleros son objetivo LAND al alcance de los cañones navales. Ejemplos: un blindado destruye un muelle (1500, armadura 4) en 13 disparos (116 cada 12 s), en t = **144 s**; una corbeta, con cañones ligeros (16 cada 3 s), en ≈ **280 s**. La reparación no lo impide: el muelle recibe daño cada 12 s o menos y no se puede reparar sin 15 s seguidos sin daño (§3.2).
- Destruir el muelle pierde lo que hubiera en su bodega.

## 8. Interacción con el combate

| Acción | Cómo se hace | Efecto |
|---|---|---|
| Atacar porteadores | Cualquier unidad armada | La carreta (60 de vida) cae con 8 tiros de fusil; se pierde su carga |
| **Cortar la vía** | Orden nueva `CUT_RAIL` [A]: una unidad de tierra queda 10 s sobre una celda de vía | Corta un tramo de 64 m: los trenes se detienen ante él. Un operario lo repara en 15 s (orden `REPAIR`). Se dibuja como rieles levantados |
| Destruir el almacén | Combate normal | Las haciendas que dependían de él se detienen («sin acopio») |
| Bloquear un puerto | §7.1 | Ingreso por exportación a 0 o a la mitad |
| Bombardear muelles y covaderas | §7.2 | Igual que en Huanillos y Pabellón de Pica |
| Interceptar el carbón | §6.2 (Q-021) | Sin carbón no hay escuadra ni Shanks |
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
| Mejora paradas → Shanks (Q-022) con carretas: 450 P + 2 operarios (100) + 5 carretas más (400; las 3 de la paradas llevan 91 P/min y la Shanks produce 240: hacen falta 8) | 950 | +130 (Perú) | **7,3 min** |
| Mejora paradas → Shanks (Q-022) con tren: 450 P + 2 operarios (100) + 2 estaciones y 1 tren (650); las 3 carretas quedan libres para otro extractor | 1200 | +130 (Perú) | 9,2 min (pero la oficina pasa de 9 a 10 de pop: 22 P/min por pop) |
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

La Shanks rinde **2,2 veces** más por pop que la paradas si tiene tren. Con un tope de 500 de pop eso es lo que decide, no el costo en pesos. Bloquear la carbonera de un rival corta su suministro, pero sus Shanks siguen trabajando con el **carbón almacenado** en su tesoro hasta agotarlo: a 10 C/min, los 200 C iniciales duran 20 min con una Shanks y 10 min con dos (menos si a la vez construye buques). El bloqueo apaga la Shanks a mediano plazo, no al instante; por eso conviene bloquear temprano y mantenerlo.

### 9.4 Ritmo de la partida (simulación; Q-019, respondida)

Script reproducible: `docs/diseno/balance/sim_economia.mjs` (`node sim_economia.mjs RITMO PRECIO_CARBON`). Un jugador sin pérdidas desarrolla su economía en este orden: hacienda, paradas, muelle, hacienda, cuartel, hacienda, paradas, carbonera, Shanks con tren, hacienda, segundo centro, covadera, hacienda, cuartel, segunda Shanks, **segundo muelle**, ... hasta 110 operarios y 10 de pop en porteadores, y gasta el resto en infantería de línea. Poblaciones cuando le faltan ≤ 8 de pop. Es una partida de «desarrollo» sin ataques: el peor caso para tener ejército pronto. El salitre sale por muelles con el tope de 500 P/min de §5.3 (lo que no cabe espera en las bodegas de 600 de cada oficina); el segundo muelle hace falta cuando entra la segunda Shanks (720 P/min de salitre). En las tres corridas no se pierde salitre por bodegas llenas.

| RITMO | Plan económico completo (min) | 30 militares | 100 | 200 | 300 | 380 (pop 500) | Ingreso a los 40 min (V + P acumulados) |
|---|---|---|---|---|---|---|---|
| 0,75 (lento) | 25,6 | 26,8 | 33,5 | 41,2 | 49,3 | **55,8** | 16 884 V + 16 362 P |
| **1,0 (medio, elegido en Q-019)** | 22,1 | 22,6 | 27,9 | 33,3 | 39,4 | **44,3** | 24 544 V + 22 744 P |
| 1,4 (rápido) | 17,6 | 19,1 | 23,3 | 28,4 | 33,1 | **36,7** | 37 455 V + 33 539 P |

(Corrida del 17-10-2026 con el tope de muelle; sin él, las cifras eran 0,2–0,4 min más bajas. Las respuestas de Q-019 citan las cifras anteriores, 44 y 36 min, que siguen valiendo redondeadas.)

Con el carbón a 0,5 P (Chile) la curva es casi igual (pop 500 en 44,2 min): la ventaja chilena del carbón está en la escuadra, no en el salitre.

**Ingreso de un jugador con la economía completa** (medio, Perú, minuto ~25): **1000 V/min y ~920 P/min netos** con 110 operarios (22 % del pop). Comparación con unidades.md §4:

| Gasto | Costo | Tiempo de ingreso completo |
|---|---|---|
| 1 infantería de línea | 60 V / 30 P | 3,6 s de víveres |
| 100 infanterías de línea (100 pop) | 6000 V / 3000 P | 6 min (limitan los víveres) |
| 1 blindado | 100 V / 700 P / 250 C | 46 s de pesos; 2,5–5 min de carbón |
| Un cuartel sin parar (infantería) | 164 V/min + 82 P/min | 6 cuarteles saturan 1000 V/min |
| 9 poblaciones (de 50 a 500 de pop) | 450 V / 900 P | ~1 min |

Lectura: en «medio», un ejército de 100 a los ~28 min y el tope de pop a los ~44 min en desarrollo puro. Un jugador que ataque antes (1 cuartel desde el minuto 4) puede tener ~15–20 soldados hacia el minuto 10 (estimación: 1 cuartel produce 1 cada 22 s si tiene ~160 V/min). Encaja con los tiempos de desplazamiento de unidades.md §2.1 (5–20 min en marcha dentro de una región): la primera ofensiva llega hacia el minuto 15–20 y las partidas duran **60–90 min**. Feño eligió el ritmo medio (RITMO = 1,0) en Q-019.

### 9.5 Tope de población

- Se mantiene **500 de pop por jugador** (unidades.md §5.8 y ADR-006). Los operarios y porteadores ocupan ~120 (24 %); quedan ~380 para el ejército y la escuadra.
- La población la dan los centros (50 cada uno, máximo 3) y las poblaciones (50 cada una, máximo 9): con 1 centro y 9 poblaciones se llega exactamente a 500.

## 10. Bolivia (Q-023, respondida)

**El problema (recursos-1879 §10.4):** si Bolivia pierde el litoral (Antofagasta, Mejillones, Tocopilla, Cobija, Caracoles), dentro de la caja del mapa solo le quedan Corocoro (cobre) y los oasis del altiplano y de Atacama. Su plata (Huanchaca, Potosí) y sus valles (Cochabamba, Chuquisaca) están fuera del mapa (ADR-014). Y Corocoro queda a ~22 km de juego de Arica: una carreta tarda 92 min en ir y volver (§5.5), así que su cobre casi no rinde.

Si la partida empieza antes del 14 de febrero de 1879 (posiciones iniciales aún sin decidir), Bolivia sí tiene el litoral al comienzo y el problema aparece cuando lo pierde. Feño eligió en Q-023 la remesa del altiplano (150 P/min y 100 V/min) y, sobre la obs. 8 de QA, que exista **desde el inicio de la partida**, tenga o no litoral.

### 10.1 Remesa del altiplano: mecanismo

Representa la plata de Huanchaca y Potosí y los víveres de los valles del interior, que están **al este de 67° W, fuera de la caja** (ADR-014). La Paz y Oruro quedan dentro de la caja, así que la remesa no «viene de La Paz»: viene de fuera del mapa por el este.

- **Destino:** el centro o almacén boliviano situado más al este (mayor x). Si no hay ninguno, la remesa se suspende (no se acumula).
- **Entrada:** la recua aparece a **2400 m** de juego del destino (~48 km reales), en dirección al borde este (o en el borde mismo si el destino está a menos de 2400 m de él). Es la misma compresión que la del vapor carbonero (L2 de ADR-017).
- **Ritmo:** sale **1 recua cada 120 s**, con **300 P y 200 V**, sin importar cuántas haya en camino. Recua: sin armas, 300 de vida, armadura 0, 3 / 8 m/s (táctica / marcha, como la carreta), pop 0.
- **Tránsito:** 2400 m / 8 m/s = **300 s**. Con una salida cada 120 s hay como máximo ⌈300 / 120⌉ = **3 recuas en camino** (2,5 de media). La primera llega en t = 300 s; desde entonces llega 1 cada 120 s.
- **Ingreso resultante:** 300 P / 120 s = **150 P/min** y 200 V / 120 s = **100 V/min**, la cifra de Q-023. Equivale a 1,7 oficinas de paradas y una hacienda llenas, sin operarios.
- **Ataque:** si una recua muere, se pierde su carga; las siguientes salen igual cada 120 s. Una recua que entra en combate pasa a velocidad táctica (3 m/s) y tarda más. Si el destino se destruye, las recuas en camino van al siguiente destino; si no hay, desaparecen con su carga.
- **Coste en entidades:** hasta 3 por jugador boliviano (§3.5).

| Comprobación | Valor |
|---|---|
| Tiempo de tránsito | 2400 / 8 = 300 s |
| Recuas en camino | ⌈300 / 120⌉ = 3 como máximo |
| Ingreso a régimen | 150 P/min y 100 V/min |
| Ingreso acumulado a los 10 min | Llegadas en t = 300, 420 y 540 s: ⌊(600 − 300) / 120⌋ + 1 = 3 entregas = 900 P y 600 V |
| Ingreso acumulado a los 40 min | ⌊(2400 − 300) / 120⌋ + 1 = 18 entregas = 5400 P y 3600 V |

### 10.2 Litoral y carbón

- Mientras tenga costa, Bolivia construye muelle y carbonera como las demás facciones; sin costa, usa los de sus aliados (§4.1, §5.3, §6.1).
- Bolivia empieza con 0 C. Para fletar transportes necesita una carbonera propia o un contrato en una aliada (§6.1). Sin ninguna de las dos no puede fletar transportes.
- El historiador debe revisar qué ruta histórica representa la entrada (por ejemplo, Potosí–Uyuni–Oruro hacia Tacna por Tacora o Charaña) y cómo se explica en la enciclopedia.

## 11. Cómo se ve en pantalla

Interfaz de cartografía de 1879 (ADR-018): papel crema, tinta sepia, tipografía y símbolos de las leyendas de época.

- **Barra superior:** Víveres, Pesos y Carbón con su cantidad y su **saldo por minuto** (+/−, en verde oliva o rojo óxido), y `Pop 123/500`. Al pasar el ratón, el desglose: «Exportación 660 · Base 60 · Importación de víveres −180 · Carbón −100».
- **Avisos** (cartela con sonido, una vez por causa y cada 30 s como mucho): «Iquique bloqueado», «Muelle de Pisagua destruido», «Vía cortada en La Noria», «Oficina Shanks sin carbón», «Vapor carbonero hundido», «Bodega llena», «Sin acopio».
- **Panel de un extractor:** puestos ocupados como figuras (●●●○○), producción por minuto actual y máxima, rendimiento del yacimiento («Caracoles: en declive, ×0,5»), barra de la bodega, porteadores asignados y botones **Agregar operario**, **Desalojar**, **Entrenar carreta** y, en paradas, **Mejorar a Shanks** (Q-022).
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

| id | cost | build_time | max_hp | armor | vision_range | footprint | placement | trains | pop_provided | drop_off | weapons |
|---|---|---|---|---|---|---|---|---|---|---|---|
| centro | V 200, P 600 | 180 | 4000 | 5 | 120 | (6, 6) | LAND | operario, carreta | 50 | viveres | — |
| poblacion | V 50, P 100 | 40 | 600 | 2 | 40 | (4, 4) | LAND | — | 50 | — | — |
| almacen | P 120 | 30 | 800 | 3 | 60 | (3, 3) | LAND | — | 0 | viveres | — |
| cuartel | P 200 | 60 | 1500 | 4 | 60 | (6, 4) | LAND | guardia_nacional, infanteria_linea, caballeria, artilleria_campana (+ colorados_bolivia en Bolivia) | 0 | — | — |
| astillero_chile | P 500 | 120 | 2500 | 5 | 150 | (8, 4) | COAST | transporte, torpedera, corbeta, blindado_bateria_chile | 0 | — | — |
| astillero_peru | P 500 | 120 | 2500 | 5 | 150 | (8, 4) | COAST | transporte, torpedera, corbeta, monitor_torre_peru | 0 | — | — |
| agencia_fletes_bolivia | P 250 | 60 | 1200 | 3 | 100 | (4, 3) | COAST | transporte | 0 | — | — |
| fuerte | V 50, P 400 | 120 | 2500 | 6 | 230 | (5, 5) | LAND | — | 0 | — | canon_costa |
| muelle | P 250 | 60 | 1500 | 4 | 100 | (2, 8) | COAST | — | 0 | salitre, guano, plata, cobre | — |
| carbonera | P 250 | 60 | 1000 | 3 | 80 | (4, 3) | COAST | — | 0 | carbon | — |
| estacion | P 200 | 45 | 800 | 3 | 60 | (4, 2) | LAND (vía) | tren | 0 | salitre, plata, cobre | — |
| hacienda | P 100 | 45 | 800 | 2 | 50 | (8, 8) | LAND (valle) | — | 0 | — | — |
| chacra_oasis | P 60 | 30 | 400 | 1 | 50 | (4, 4) | LAND (oasis) | — | 0 | — | — |
| oficina_paradas | P 200 | 60 | 1000 | 2 | 60 | (6, 5) | LAND (salitre) | carreta | 0 | — | — |
| oficina_shanks | P 600 | 150 | 2000 | 4 | 60 | (10, 7) | LAND (salitre) | carreta | 0 | — | — |
| covadera | P 150 | 60 | 900 | 2 | 60 | (4, 3) | COAST (guano) | — | 0 | guano (propio) | — |
| mina_plata | P 300 | 90 | 1000 | 3 | 60 | (4, 4) | LAND (plata) | carreta | 0 | — | — |
| mina_cobre | P 250 | 75 | 1000 | 3 | 60 | (4, 4) | LAND (cobre) | carreta | 0 | — | — |

Todos los tiempos son múltiplos de 0,05 s (ADR-006). El astillero se divide en dos `.tres` por facción porque `trains` cambia; también podría ser uno común si FactionDef filtra `trains` por `FactionDef.units` (lo decide el arquitecto).

### 12.3 Campos nuevos que hacen falta (forma: arquitecto, Q-025, abierta)

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
| `upgrades_to`, `upgrade_cost`, `upgrade_time` | BuildingDef | BuildingDef, Dictionary, float | Paradas → Shanks: 450 P, 120 s (Q-022) |
| `base_income` | BuildingDef | Dictionary[ResourceDef, float] (por min) | Centro: pesos 60 |
| `carry_capacity`, `rail_only` | UnitDef | int, bool | Carreta 200 / false; tren 1000 / true |
| `coal_price`, `coal_entry_dir` | FactionDef | float, enum {SUR, OESTE} | §6.1 |
| `start_resources` | FactionDef (ya existe) | — | §2.1 |
| Yacimientos | Datos del mapa (T-011) | lista: tipo, posición, sitios, rendimiento | §12.4 |
| Constantes | Simulación | — | `RITMO` 1,0; tope de edificios 50; radio de bloqueo 400 m; contrato de carbón 150 C / 180 s; entrada a 4000 m; corte de vía 10 s / reparación 15 s; reparar 3 de vida/s por operario, máximo 3, sin daño en 15 s; cimientos con 10 % de vida, reembolso 80 %, autocancelación a 60 s sin obra; asalto a min_range − 5 m; remesa boliviana 300 P + 200 V cada 120 s, entrada a 2400 m, recua a 8 m/s; 2 contratos de carbón por carbonera y por jugador |

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
- **Varios jugadores en el mismo yacimiento:** cada sitio admite un edificio; el primero que pone los cimientos lo ocupa. Bloquearlo con cimientos no es gratis: cancelar devuelve el 80 %, los cimientos se cancelan solos a los 60 s sin obra y nacen con el 10 % de la vida del edificio, así que se pueden destruir (§3.2).
- **Corte de vía con un tren encima:** el tren se detiene antes del tramo cortado; si el tramo se corta bajo el tren, sigue hasta el final de su vagón y se detiene.
- **Tope de 50 edificios:** el botón de construir se desactiva con el aviso «Tope de edificios»; los cimientos cuentan.
- **Tope de pop con porteadores:** entrenar una carreta o un tren requiere pop libre igual que una unidad militar; la cola espera sin cobrar (unidades.md §9).
- **Operarios dentro de un edificio que cambia de dueño:** en v1 no hay captura; si se destruye, salen por la puerta.
- **Covadera bloqueada:** su guano se acumula en la bodega (600) y luego se detiene.
- **Precisión:** la producción se acumula en float cada tick (por ejemplo, 20 V/min = 0,0167 V por tick) y se acredita en enteros; la parte fraccionaria se guarda.

## 14. Preguntas de diseño y sus respuestas

| Id | Pregunta | Respuesta | Estado |
|---|---|---|---|
| Q-019 | Ritmo general de la economía | Medio (RITMO = 1,0): pop 500 en ~44 min; partidas de 60–90 min | Respondida por Feño |
| Q-020 | Cómo trabajan los operarios | Asignados dentro del edificio (no visibles, cuentan pop) | Respondida por Feño |
| Q-021 | ¿Se pueden interceptar los vapores carboneros? | Sí: visibles, sin armas y se pueden hundir | Respondida por Feño |
| Q-022 | ¿La oficina de paradas se puede mejorar a Shanks? | Sí, por 450 P y 120 s, sin dejar de producir | Respondida por Feño |
| Q-023 | Cómo compensar a Bolivia | Remesa del altiplano por el borde este cada 120 s (300 P y 200 V), atacable | Respondida por Feño |
| Q-024 | ¿El carbón se usa fuera de los buques y la Shanks? | No: en v1 solo buques y Shanks | Respondida por Feño |
| Q-025 (Luis) | Forma de las cargas y campos nuevos en ADR-007 | Recomendación: ampliar ResourceDef con `kind` y BuildingDef con los campos de §12.3 | **Abierta** (no bloquea el diseño; sí la implementación de los datos) |

Todas las respuestas de Feño coinciden con las opciones que ya usaba este documento, así que no cambió ninguna cifra. Q-025 solo afecta a la forma de los campos de §12, no a los valores.

## 15. Licencias y apartamientos de la historia

| Licencia | Por qué | Registro |
|---|---|---|
| Tiempos comprimidos de extracción, transporte y embarque | Jugabilidad | ADR-017 (L2) |
| El vapor carbonero aparece a 4 km de la carbonera en vez de venir desde Lota o desde Europa | Que el carbón no tarde 40 min por viaje | Cubierta por L2 (ADR-017) y ADR-016 |
| La mina de cobre incluye la fundición | Simplificar v1 | Diseño (este documento) |
| Una carga vale 1 P por unidad para todos los minerales | Legibilidad; la plata vale más por viaje (densidad) | Diseño |
| Yacimientos infinitos | Partidas de 60–90 min; la producción de 1879 no se agotaba en meses | Diseño |
| Remesa del altiplano (Q-023): la plata y los víveres de fuera de la caja (al este de 67° W) entran como recuas que aparecen a 2400 m del destino boliviano | Bolivia sin recursos dentro del mapa | Diseño (Q-023); el historiador debe revisar la ruta que representa (La Paz y Oruro están dentro de la caja) |

## 16. Para v2

- **Agua:** aguadas y condensadoras como radio de abasto; fuera de él, desgaste de vida de las tropas (ficha de ejércitos §5). Las condensadoras consumirían carbón.
- Fundiciones de cobre separadas, ingenios azucareros, construcción de vías nuevas, consumo de carbón al navegar.
- **Captura de edificios** (Chile explotando las oficinas peruanas tras ocupar Tarapacá).
- Derechos de exportación como mecánica de facción (según una sola fuente, Chile cobró 40 centavos por quintal en 1879: dato [P] en recursos-1879 §2.6, a confirmar) en T-031.
- Víveres importados más baratos para Chile (trigo del valle central), si T-031 lo pide.

## 17. Decisiones registradas (propuestas, área diseño)

- **ADR-020:** tres recursos acumulables y cuatro cargas que se convierten en pesos al embarcarse (§2, §5).
- **ADR-021:** presupuesto de entidades de la economía: porteadores con pop, lanchas cosméticas, tope de 50 edificios (§3.5).
- **ADR-022:** suministro de carbón por mar con carbonera y contrato (§6; concreta ADR-016).
- **ADR-023:** cifras de las dos oficinas salitreras y rendimiento de los yacimientos (§4, §9, §12.4; concreta ADR-017).
- **ADR-024:** bloqueo naval, ataque costero, corte de vías y fuerte de costa (§4.3, §7, §8).

## 18. Pendiente

- Respuesta de Luis a Q-025 (forma de las cargas y de los campos nuevos en ADR-007) antes de cargar los .tres.
- Yacimientos, vías históricas y distancias reales en los datos del mapa (T-011, con el historiador); las distancias de §5.5 son aproximadas.
- Corrección del texto «C = carbón (solo buques)» y del tope de pop en unidades.md (comentado en T-016).
- Bonificaciones económicas de facción (T-031).
- Primera prueba jugable: ajustar tasas y costos con `sim_economia.mjs` y con partidas reales.
