# Guía de estilo visual: la estética de 1879

> Tarea **T-034** (P-002). Autor: historiador. **Estado: tono y colores de facción decididos.** Feño eligió la opción A en **Q-017** (tono visual) y en **Q-018** (colores de facción), registradas como **ADR-018** y **ADR-019** (área arte, aceptadas). El resto de lo marcado **[J]** sigue siendo una propuesta que el área de arte puede ajustar.
>
> Fichas de historia en las que se apoya: [mapas-1879.md](../historia/mapas-1879.md) (mapas con su licencia), [ejercitos-1879.md](../historia/ejercitos-1879.md) §6 (uniformes), [armadas-1879.md](../historia/armadas-1879.md) §2 y §4 (buques y modelos provisionales), [geografia-1879.md](../historia/geografia-1879.md) §6 (relieve), `recursos-1879.md` §11 (modelos industriales, rama `feature/T-035-recursos-epoca`) y `sitios-clave-escala.md` (lupas, rama `feature/T-040-sitios-clave`).
>
> Decisiones: **ADR-004** (3D con cámara RTS), **ADR-005** (jugable sin arte final), **ADR-007** (separación lógica/vista), **ADR-010** (presupuesto de render), **ADR-014** a **ADR-017** (licencias creativas de historia).
>
> Las imágenes de referencia están en `docs/referencias/mapas/` y `docs/referencias/estetica/`, con su licencia en el README de cada carpeta. Están fuera del juego (`docs/` tiene `.gdignore`).

## Cómo leer esta guía

- **[D] Documentado:** sale de una fuente (ficha de catálogo, texto impreso en el mapa o ficha de historia).
- **[O] Observado:** el historiador lo ve en una imagen de época. Las fotos de 1879 son en blanco y negro: **no dan colores**.
- **[M] Medido:** color tomado con un programa sobre el escaneo (mediana de una zona). El papel amarillea y los escaneos cambian el color: el valor dice cómo se ve hoy el documento, no cómo era en 1879.
- **[I] Inferido:** deducción del historiador.
- **[P] Pendiente:** sin verificar.
- **[J] Propuesta de juego:** no es historia; la decide diseño o Feño.

---

## 1. Idea general (decidida: ADR-018)

**«La guerra vista a través de sus mapas.»** Lo más reconocible y mejor conservado de 1879 son los mapas impresos: papel crema, tinta sepia, relieve dibujado con normales (rayitas de pendiente), nombres en mayúsculas espaciadas y, en los mejores, coloreado a mano. Feño eligió la opción A de **Q-017**, registrada como **ADR-018**:

1. **Interfaz de época.** El minimapa, el mapa estratégico, los menús y las cartelas imitan esa cartografía (§2, §3 y §4).
2. **Mundo 3D naturalista y sobrio.** El terreno, los buques, las tropas y los edificios se ven con luz natural y una paleta desaturada de desierto, mar frío y adobe (§5 a §8). Nada de filtros de grabado sobre el 3D: cuesta mucho y choca con el presupuesto de ADR-010.
3. **Tono respetuoso.** Los tres bandos reciben el mismo cuidado visual. Sin caricaturas, sin «buenos» ni «malos» por color o por música. Las pinturas conmemorativas de después de la guerra (§9) sirven para la composición, no como modelo de tono.

Alternativas descartadas en ADR-018: todo el juego como grabado (costo en shaders y riesgo para ADR-010) y una interfaz moderna sin referencias de época.

---

## 2. Paleta

### 2.1 Papel y tinta (de los mapas de 1879)

| Uso propuesto | Color | Muestra tomada de | Marca |
|---|---|---|---|
| Papel crema (fondo del minimapa y de los menús) | `#D4C9A9` | Bertrand, *Teatro de la guerra* (1879), zona más extensa del papel | [M] |
| Papel crema más claro | `#DDD2B2` | Ídem | [M] |
| Papel tostado | `#D9C8AB` | Prieto, *Combate naval de Iquique* (1879) | [M] |
| Papel envejecido (borde) | `#D6C59B` | Turner (1879), margen inferior | [M] |
| Papel claro, casi blanco | `#E8E5D9` | Paz Soldán (1865), escaneo de Rumsey | [M] |
| Tinta sepia media (relieve, caminos) | `#84765B` | Bertrand (1879), trazos de relieve | [M] |
| Tinta sepia oscura | `#6B674C` | Turner (1879), trazos oscuros | [M] |
| Tinta para textos (legibilidad) | `#3B3328` | **Propuesta**: los escaneos no dan un negro de tinta fiable | [J] |
| Relieve sepia claro | `#C5B09B` | Prieto, *Prise d'Arica* (1880), el Morro | [M] |
| Rojo lacre (ciudades, fuertes, alertas) | `#9F5D53` | Prieto, *Prise d'Arica* (1880), la ciudad de Arica | [M] |

### 2.2 Coloreado a mano (Turner, 1879)

El mapa británico de Turner es el único del conjunto que colorea los tres países (`mapas-1879.md` §2.1). Medido sobre el escaneo de Princeton:

| Zona del mapa | Color medido | Marca |
|---|---|---|
| Perú (al norte del Loa) | `#D5B274` ocre | [M] |
| Bolivia (Loa a 23° S) | `#A2AE7A` verde | [M] |
| Bolivia (23° a 24° S, zona de derechos compartidos) | `#C2BF90` verde claro | [M] |
| Chile (al sur de 24° S) | `#D3B387`, un rosado que hoy se ve salmón | [M] |
| Océano | `#C9C49E` (el azul se perdió con el envejecimiento) | [M] |

En el mapa de Bolivia de 1859 (Ondarza, Mujía y Camacho) los departamentos están coloreados en **verdes, rosados, amarillos y azules pálidos** [O]: la acuarela de los mapas de la época era clara y transparente [I].

**Uso en el mapa estratégico [J]:** colorear el territorio con los colores de facción de ADR-019 (§2.4), aplicados como tinta plana y transparente sobre el papel, igual que en estos mapas, con un borde más intenso en la frontera (Turner y Ondarza refuerzan así los límites [O]). Los colores de Turner quedan solo como referencia histórica.

### 2.3 Paisaje 3D [J]

No hay fotos en color de 1879; estas son pautas, no datos. Se ajustan con fotografías actuales de los lugares (con licencia libre) y con `geografia-1879.md` §6.

- **Pampa y desierto:** beige grisáceo y pardo claro, casi sin vegetación, salvo los bosquetes de tamarugo de la Pampa del Tamarugal (geografia-1879 §6.1); las salitreras y salares, manchas blanquecinas (caliche, costras de sal).
- **Cordillera de la Costa:** acantilado pardo oscuro que cae directo al mar, típico entre Arica y Antofagasta [D, geografia-1879 §6.1].
- **Valles y oasis** (Azapa, Lluta, Tarapacá, Pica, Moquegua, Lurín): franjas de verde intenso que contrastan con el desierto. Son las zonas de agua que deciden el movimiento (geografia-1879 §6.2).
- **Mar:** Pacífico frío, azul grisáceo y verdoso; la **camanchaca** (niebla costera) es un buen recurso de ambiente.
- **Andes y altiplano:** pardos, ocres y nieve en las cumbres; la puna es amarillenta (ichu).
- **Luz:** sol alto y duro, sombras cortas y cielo muy despejado en el desierto.

### 2.4 Colores de facción (decididos: ADR-019)

Feño eligió la opción A de **Q-018**, registrada como **ADR-019**: **un color dominante de cada bandera, sin repetir**. Las tres banderas comparten el rojo, así que a cada país se le asigna un color de su bandera que no use ningún otro bando.

| Facción | Color | Valor inicial [J] | De dónde sale |
|---|---|---|---|
| Chile | Azul | `#2B4C8C` | Cantón azul de la bandera |
| Perú | Rojo carmín | `#9B1B30` | Franjas rojas de la bandera |
| Bolivia | Verde | `#2F8F5B` | Franja verde de la bandera |
| Bolivia (acento) | Amarillo | `#E3B23C` | Franja amarilla de la bandera |

**Los valores hex son una propuesta del historiador [J]; el ajuste fino es de arte.** Se eligieron así:

- **Sobre el papel** (`#D4C9A9`, §2.1), contraste WCAG: Chile 5,1:1, Perú 4,9:1, Bolivia 2,5:1. Los tres son legibles como tinta del mapa estratégico; el verde, menos.
- **Sobre el desierto** (pardo claro de referencia `#B9A98A` [J]): Chile 3,6:1, Perú 3,5:1, Bolivia 1,75:1. Por eso las unidades y edificios en el 3D llevan siempre un **contorno o halo oscuro** y el acento amarillo en Bolivia [J].
- **Entre sí:** los tres tienen una luminancia parecida y se distinguen por el tono. Con una simulación de deuteranopía (Machado et al., 2009), una primera versión (carmín `#A51F34`, verde `#1B6B42`) dejaba a Perú y Bolivia casi iguales. Por eso el carmín se oscureció y el verde se aclaró y se volvió algo azulado: la distancia entre ambos se multiplicó por cuatro. Aun así, **Bolivia lleva siempre el acento amarillo como segunda señal** (banda, estandarte o borde), y se recomienda añadir un patrón o una forma para el modo daltónico [J].
- **Frente al paisaje:** el verde de Bolivia es más azulado que el verde oliva de los oasis y valles (§2.3), para no confundirse con la vegetación; el azul de Chile es más oscuro y saturado que el mar del Pacífico.

**Dónde se usa:** `FactionDef.color` de cada facción y `TeamColors.from_factions` (T-017), las tintas del territorio en el mapa estratégico (§2.2) y los símbolos de unidad del mapa táctico (§4).

**Alternativas descartadas en ADR-019:** la convención de Turner (Perú ocre, Bolivia verde, Chile rosado), que se pierde en el desierto; un esquema mixto; y colores neutros no nacionales.

---|---|---|---|---|
| A, recomendada | azul `#2F4A7A` | rojo carmín `#A3282F` | verde `#3F7A3A` (acento amarillo `#D4A93A`) | Un color dominante de cada bandera, sin repetir |
| B | rosado (`#D3B387` medido; vivo, `#D9968C` [J]) | ocre `#D5B274` | verde `#A2AE7A` | Convención de Turner (1879); el ocre se pierde en el desierto |
| C | como A en unidades; como B en el mapa de papel | | | Mixto |
| D | colores neutros elegidos por legibilidad y daltonismo | | | La bandera queda solo en estandartes y buques |

Los valores de A y del rosado vivo de B son **propuestas** [J]. Hoy `FactionDef.color` es provisional y la partida de T-017 usa una paleta por jugador (`TeamColors.from_factions` está listo para leer el color de la facción).

---

## 3. Tipografía y cartelas

**Lo que muestran los mapas [O]** (Bertrand 1879, Prieto 1879–1880, Turner 1879, Gopčević 1887):

- **Títulos:** mayúsculas con serifas y mucho contraste («CARTA DE LOS DESIERTOS DE TARAPACÁ I DE ATACAMA»), o mayúsculas condensadas y gruesas («MAPA DETALLADO DEL TEATRO DE LA GUERRA», «COMBATE NAVAL DE IQUIQUE»). Se mezclan tamaños y estilos en una misma cartela.
- **Subtítulos y toponimia del mar:** cursiva («en 21 de Mayo de 1879», «Bahía», «Caleta»).
- **Regiones:** mayúsculas muy espaciadas que cruzan el mapa («P A M P A  D E L  T A M A R U G A L», «B O L I V I A»).
- **Ciudades:** jerarquía por tamaño y por símbolo (círculos concéntricos para prefecturas y subprefecturas).
- **Ortografía de época [D]:** los mapas chilenos usan la ortografía de Bello: «i» por «y» («Tarapacá i Atacama»), «jeneral». Los peruanos y bolivianos usan la ortografía académica. Es un buen detalle para cartelas y documentos del juego, aplicado según la procedencia del documento [J].
- **Ornamentos:** filetes, pequeñas viñetas y marcos de grecas; el mapa de Bolivia de 1859 tiene un marco con viñetas de paisajes y tipos humanos.

**Fuentes tipográficas libres sugeridas [J]** (licencia SIL Open Font License según Google Fonts; [P] confirmar el `OFL.txt` al descargarlas):

- **Old Standard TT**: serifa «moderna» (de estilo clasicista) inspirada en ediciones de finales del siglo XIX. Para textos, toponimia y cursivas.
- **Playfair Display**: serifa de alto contraste. Para títulos.
- Una **grotesca o egipcia condensada** para títulos al estilo de los carteles de la época: pendiente de elegir [P].

---

## 4. Simbología del minimapa y del mapa táctico [J]

Basada en las leyendas de Bertrand (1879), *Prise d'Arica* (Prieto, 1880), *Combate naval de Iquique* (Prieto, 1879) y Gopčević (1887). Todas las formas están **observadas** en esos mapas [O]; su asignación a elementos del juego es una propuesta [J].

| Elemento del juego | Símbolo de época | Mapa de referencia |
|---|---|---|
| Ferrocarril | Línea continua gruesa | Bertrand, leyenda |
| Camino carretero | Línea con puntos | Bertrand, leyenda |
| Sendero o huella | Línea cortada | Bertrand, leyenda |
| Salitrera | Zona punteada | Bertrand, leyenda |
| Salar | Zona rayada | Bertrand, leyenda |
| Aguada u oficina | Punto negro | Bertrand, leyenda |
| Ciudad importante | Círculos concéntricos; en planos de detalle, mancha roja | Bertrand; Prieto (Arica) |
| Pueblo o estancia | Círculo pequeño | Bertrand, leyenda |
| Desembarco | Estrella | Bertrand («puntos de desembarco») |
| Regimiento o batallón | Rectángulo bicolor con su nombre | Prieto (Arica) |
| Artillería | Cruces en fila | Gopčević |
| Fuerte o batería | Cuadro relleno | Prieto (Arica) |
| Atrincheramiento | Línea de puntos o de cuadritos | Prieto (Arica) |
| Movimiento | Flecha con línea | Gopčević |
| Buque | Silueta mínima (casco) con estela; una línea distinta por buque; hora junto a cada posición | Prieto (Iquique, Arica) |
| Relieve | Normales (rayitas de pendiente) o sombreado; cotas en metros | Bertrand, Paz Soldán |
| Escala | Barra en kilómetros o metros; rosa de los vientos | Todos |

---

## 5. Uniformes

**Estado:** la ficha `ejercitos-1879.md` §6 deja los uniformes como **[P]**. Esta tarea añade fotografías de época (en blanco y negro) y referencias, pero **no permite fijar colores**. Antes de modelar las tropas finales (T-021) hay que consultar:

- Esposito, Gabriele. *Armies of the War of the Pacific 1879–83: Chile, Peru & Bolivia*. Osprey, Men-at-Arms 504, 2016. Tiene láminas en color de los tres ejércitos [P: no consultado].
- Museo Histórico Militar de Chile (Santiago), Museo del Ejército «Real Felipe» (Callao) y Museo del Litoral Boliviano (La Paz).

| Bando | Lo que se sabe | Marca | Imágenes en `docs/referencias/estetica/` |
|---|---|---|---|
| Chile | La infantería de línea suele aparecer con quepís, guerrera azul oscuro y pantalón rojo o garance; en campaña, cubrenucas y prendas de lino claro (brin) por el calor | [P], de `ejercitos-1879.md` §6 | Fotos de Courret en Lima (1881–1884): un capitán del cívico movilizado «Talca» y dos soldados de caballería. Un grabado danés de una cantinera (1884) |
| Perú | Uniformes variados según el batallón; en las fotos predominan el azul y el blanco; en la sierra, ropa civil o mixta | [P], de `ejercitos-1879.md` §6 | Foto de un soldado de infantería peruano en Lima, 1879, en uniforme de parada. Grabado «Tipo del soldado peruano» (Iquique, 1879) [O]: quepí, guerrera y pantalón de tela clara, polainas, fusil con bayoneta |
| Bolivia | Los **Colorados** deben su nombre a su casaca roja | [D], de `ejercitos-1879.md` §6 | Foto de un soldado de los Colorados (publicada en un álbum chileno de 1909). Foto moderna (CC BY-SA) del Museo del Litoral Boliviano [O]: cuatro uniformes de colores muy distintos (guerrera verde con vivos rojos; guerrera y quepí amarillos; casaca azul con pantalón rojo; casaca roja con pantalón blanco y cubrenuca). Coincide con la idea de batallones conocidos por su color (`ejercitos-1879.md` §6), pero sin rótulos no se sabe a qué batallón corresponde cada uno ni si son originales [P] |

**Lectura [I]:** las fuentes reunidas sugieren que en 1879 los tres ejércitos usaban prendas de tela clara (brin, lino) en campaña y uniformes de color en parada, y que el ejército boliviano distinguía batallones por el color de la guerrera. Falta confirmarlo con Osprey y los museos.

**Pauta para el arte [J]:** que cada bando se distinga por la **silueta** (tocado, largo de la guerrera, poncho o capote, correaje) además del color, porque a la distancia de la cámara RTS el color se pierde. Las siluetas concretas se fijan cuando se consulte Osprey y los museos.

---

## 6. Buques

Las fichas técnicas y el contraste con los modelos provisionales están en `armadas-1879.md` §2 y §4. Los **esquemas de pintura de 1879 siguen pendientes** [P] (`armadas-1879.md` §5).

Referencias reunidas en `docs/referencias/estetica/`:

- **Fotografías de 1879 [D]:** el *Huáscar* entrando en Valparaíso tras Angamos (Museo Naval del Perú); la bahía de Pisagua el 2 de noviembre de 1879 con la *Covadonga*, el *Cochrane* y transportes (Museo Marítimo Nacional de Chile); la cubierta de la corbeta *Abtao* tras el combate de Antofagasta del 28 de agosto de 1879.
- **Grabados de 1879 [D]:** *La Ilustración Española y Americana* (Madrid, 22 sep. 1879): «El *Atahualpa*, nuevo monitor de la marina peruana» y la captura del transporte chileno *Rímac* por el *Huáscar* y la *Unión* (23 de julio de 1879). Es una revista de un país neutral, dibujada a partir de croquis enviados desde la zona; el *Atahualpa* aparece con dos palos y velas, lo que habría que contrastar con las fotos del monitor [P].
- **Litografía [D]:** el monitor *Manco Cápac* (ex USS *Oneota*), de Cooper & Sheridan, Nueva York, anterior a 1880 (Archivo Histórico de Marina del Perú).
- **Pintura posterior [D]:** Thomas Somerscales, *Combate naval de Angamos* (1890). Somerscales vivió en Chile y pintó la guerra después de 1879; sirve para el mar, la luz y el humo, no como prueba del color de los cascos [I].

**Lo que se ve [O]:** en la foto de 1879 en Valparaíso, el casco del *Huáscar* se ve de un tono claro, no negro; en la pintura de Somerscales (1890) el *Huáscar* es gris claro y el blindado chileno tiene el casco oscuro. Una foto en blanco y negro y una pintura posterior no bastan para fijar colores, pero ponen en duda el casco negro del modelo provisional (`armadas-1879.md` §4 lo marcaba [P]).

**Pautas [J]:** chimeneas altas y humo de carbón negro y abundante, aparejo (palos y vergas) visible en todos los buques de 1879, banderas grandes en el pico, botes en pescantes. Los colores de casco y superestructura se fijan buque por buque con las fotos y la iconografía de los museos navales [P].

---

## 7. Arquitectura y ciudades

Los modelos industriales (salitreras, muelles, covaderas, condensadoras, ferrocarriles) están en `recursos-1879.md` §11, con su prioridad. Aquí se añaden las ciudades.

| Zona | Rasgos | Marca | Referencias en `docs/referencias/estetica/` |
|---|---|---|---|
| Puertos del desierto (Antofagasta, Iquique, Pisagua, Tocopilla, Mejillones, Cobija) | Una franja de casas bajas de techo plano junto al mar, al pie de cerros pelados; galpones largos con varias chimeneas; muelle de madera sobre pilotes con botes; el ferrocarril subiendo por la ladera; ninguna vegetación [O, grabado de Antofagasta]. En Iquique, una torre de madera de vigía con campana junto a la Aduana y carretas de dos ruedas [O]. Materiales (madera importada, calamina) [I] | [O] grabados de 1879; [P] fecha de cada edificio | Grabados de Antofagasta e Iquique en *La Ilustración Española y Americana* (1879) |
| Arica y Tacna | Arica al pie del Morro, con fuertes y baterías en el morro y en la playa; Tacna, ciudad de valle con casonas | [D] fuertes (ver `sitios-clave-escala.md` §3.5); [P] edificios concretos | Grabado de Arica (1879); plano *Prise d'Arica* (1880) |
| Lima | Ciudad densa de techos planos (azoteas) junto al río Rímac, con el puente de Piedra y el cerro San Cristóbal detrás [O]. Casonas con **balcones de cajón** de madera, iglesias barrocas, adobe y quincha (caña y barro) [I], arquitectura limeña conocida; [P] verificar con fotos de 1879–1881 | [O] grabado; [I]/[P] el resto | Grabado de Lima (1879) |
| Callao | Fortaleza del Real Felipe, baterías costeras y muelle-dársena | [D] Real Felipe; [P] las baterías de 1879–1880 | Grabado de las baterías del Callao (1879) |
| Chorrillos, Barranco y Miraflores | Balnearios de ranchos (casas de veraneo) que quedaron en ruinas tras enero de 1881 | [D] destrucción; [P] aspecto | Por reunir (el grabado de *The Graphic* en Commons tiene procedencia dudosa) |
| Pueblos de valle y de la sierra | Adobe, techos de barro o de paja (ichu), iglesia encalada, plaza | [I] | Por reunir |
| Valparaíso | Puerto principal de Chile; los ascensores empezaron en 1883 (Concepción), así que en 1879 no los había | [P] fecha | Por reunir; fuera de los combates (sitio con lupa en T-040) |

---

## 8. Fotografía y grabados de época como referencia de ambiente

- **Fotografía [D]:** en 1879–1881 trabajaron en campaña fotógrafos como **Díaz y Spencer** (con el ejército chileno) y estudios de Lima como el de **Eugenio Courret**. Las fotos son en blanco y negro (albúmina) y sirven para formas, texturas, siluetas y paisajes, no para colores.
- **Prensa ilustrada [D]:** *La Ilustración Española y Americana* (Madrid), *The Graphic* (Londres), *Le Monde illustré* (París) publicaron grabados de la guerra en 1879–1881. Son de países neutrales, aunque a menudo dibujados a partir de fotos o croquis de uno de los bandos.
- **Uso propuesto [J]:** pantallas de carga, fondos de menú y cartas de evento con grabados o fotos de época (todas las de la carpeta son de dominio público o de licencia libre), en sepia, siempre con un pie que diga qué son y de dónde vienen.

---

## 9. Pinturas conmemorativas

Las pinturas de la guerra se hicieron casi todas **después** (1880–1910) y con intención conmemorativa o patriótica. Por equilibrio se guarda una de cada lado:

- Thomas Somerscales, *Combate naval de Angamos* (1890), Chile.
- Juan Lepiani, *La respuesta* (1894), Perú: Bolognesi en Arica, 5 de junio de 1880.

**Pauta [J]:** útiles para composición, luz y paleta; no copiar su tono heroico. Si el juego usa escenas parecidas, que sea con el mismo respeto para los tres bandos.

---

## 10. Licencias estéticas

- **ADR-018** (Q-017, aceptada por Feño): la interfaz imita la cartografía impresa de 1879 y el mundo 3D es naturalista. Es una licencia estética: el juego se inspira en la cartografía de la época, no reproduce un mapa concreto.
- **ADR-019** (Q-018, aceptada por Feño): un color de cada bandera, sin repetir.
- Queda pendiente, aparte, el uso de los mapas de Paz Soldán (1865), cuyo escaneo es de la colección David Rumsey (ver `mapas-1879.md` §4.1).

## 11. Pendientes

- [ ] Láminas de uniformes en color (Osprey MAA 504, museos) para Chile, Perú y Bolivia.
- [ ] Esquemas de pintura de los buques en 1879 (Museo Naval de Valparaíso, Museo Naval del Perú).
- [ ] Fotos de 1879–1884 de Iquique, Antofagasta, Tacna, Lima y de las oficinas salitreras (Memoria Chilena, Biblioteca Nacional del Perú, Courret).
- [ ] Referencias bolivianas de uniformes y ciudades (Cobija, Calama, La Paz) de fuentes bolivianas.
- [ ] Elegir la fuente condensada de títulos y comprobar las licencias OFL.
- [ ] Probar la paleta de §2 en pantalla (contraste de textos sobre papel, modo daltónico) y que arte ajuste los valores de ADR-019 sobre el terreno real (T-011).

## Fuentes

- Mapas: ver [mapas-1879.md](../historia/mapas-1879.md), con la licencia y el enlace de cada uno. Los colores [M] se midieron sobre esas copias.
- Imágenes de ambiente: ver `docs/referencias/estetica/README.md`, con la ficha de Commons de cada una.
- Fichas de historia del proyecto: `ejercitos-1879.md`, `armadas-1879.md`, `geografia-1879.md`, `recursos-1879.md` (T-035) y `sitios-clave-escala.md` (T-040).
- Google Fonts, fichas de Old Standard TT y Playfair Display (licencia OFL) [P: no consultadas en esta tarea; dato de conocimiento general].
