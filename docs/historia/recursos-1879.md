# Ficha histórica: extracción de recursos (1879–1884) y cómo representarla

> Tarea: **T-035** (P-004). Alimenta el diseño de economía (**T-022**, `docs/diseno/economia.md`) y los costos provisionales de `docs/diseno/unidades.md` §4 (T-016).
> Fichas relacionadas: [geografia-1879.md](geografia-1879.md) (§6 agua, §7 recursos, §8 ferrocarriles), [ejercitos-1879.md](ejercitos-1879.md) (§5 logística), [armadas-1879.md](armadas-1879.md).
> Decisiones en las que se apoya: **ADR-007** (ResourceDef, BuildingDef), **ADR-009** (escala 1:20, edificios a tamaño real), **ADR-014** (caja del mapa 11,5–33,5° S, 78–67° W; lo de fuera no tiene lupa) y **ADR-015** (fronteras).
> Bloqueos abiertos para Feño: **Q-014** (carbón fuera del mapa) y **Q-015** (licencias de representación). Las licencias de §10 **no están decididas**.

## Cómo leer esta ficha

Igual que las otras fichas de historia:

- **[D] Documentado:** las fuentes consultadas coinciden.
- **[C] Discutido:** las fuentes dan cifras o fechas distintas. Se da el rango y de dónde sale cada valor.
- **[P] Pendiente:** no se pudo verificar en esta tarea, o viene de un resumen secundario sin la fuente original. **No usarlo como dato histórico sin revisarlo.**
- **[I] Inferido:** deducción del historiador a partir de datos documentados (no es un dato de fuente).
- **[J] Propuesta de juego:** sugerencia para T-022. No es historia ni está decidida: la decide el game-designer, y las licencias creativas, Feño.

Coordenadas en grados decimales WGS84 (sur y oeste negativos). La precisión A/B es la de la ficha de geografía.

---

## 1. Resumen

| Recurso | Dónde (dentro de la caja salvo aviso) | Quién lo controlaba en feb. 1879 | Papel en la guerra |
|---|---|---|---|
| **Salitre** | Pampa del Tamarugal (Tarapacá, Perú); Salar del Carmen y El Toco (litoral boliviano) | Perú (Estado, tras la expropiación de 1875); en Antofagasta, la CSFA (capitales chilenos y británicos) | Detonante (impuesto de los 10 centavos) y gran premio territorial; Chile lo grava desde 1879 y financia la guerra [D] |
| **Guano** | Covaderas de Tarapacá (Pabellón de Pica, Huanillos, Punta de Lobos), Mejillones; islas de Chincha casi agotadas | Perú; Mejillones, zona compartida Chile–Bolivia (tratado de 1874) | Base del crédito peruano en crisis; la escuadra chilena destruye los embarcaderos en abril de 1879 [D]/[C] |
| **Plata** | Caracoles (litoral boliviano). **Fuera del mapa:** Huanchaca–Pulacayo y Potosí (Bolivia) | Empresarios chilenos en Caracoles; Compañía Huanchaca (Arce, con socios chilenos) | Caracoles se ocupa en feb–mar 1879; el interés minero boliviano es parte del debate sobre la paz [C] |
| **Cobre** | Norte Chico chileno (Atacama, Coquimbo), Tocopilla, Chañaral; Corocoro (Bolivia, altiplano) | Chile en su territorio; Bolivia en Tocopilla/Corocoro | Chile era el primer productor mundial hasta ~1880 [D]; peso económico, poco papel militar directo [I] |
| **Carbón** | **Fuera del mapa:** Lota y Coronel (~37° S, Chile) | Compañía de Lota (Cousiño) | Combustible de la escuadra y de las calderas salitreras [D]; ver Q-014 |
| **Agua** | Ríos y quebradas, aguadas, condensadoras de agua de mar en los puertos | Quien ocupara el pozo o el puerto | Recurso limitante de toda operación en el desierto [D] |
| **Agricultura** | Valles de Lima, Cañete, Ica, Moquegua, Tacna, Azapa; oasis (Pica, Calama, San Pedro); valle de Aconcagua (Chile) | Haciendas privadas | Víveres y forraje para los ejércitos; la expedición Lynch (1880) castiga haciendas del norte peruano, fuera del mapa [D] |

---

## 2. Salitre

### 2.1 Qué era y para qué servía

- Nitrato de sodio extraído del **caliche**, un manto mineral bajo la costra de la pampa. Se exportaba a Europa como **fertilizante** y como materia prima de **explosivos**. [D]
- Producción total (toneladas métricas): **323 058 en 1878** y **589 720 en 1883** (Memoria Chilena, «Explotación del salitre»; la misma cifra aparece en «Sistema Shanks», Wikipedia en español). [D] La cifra de 1878 suma Tarapacá y Antofagasta. Falta separarla por región. [P]

### 2.2 Cómo se extraía (cadena de trabajo)

Según Memoria Chilena («Explotación del salitre») [D] en lo general:

1. **Cateo:** se reconocía el manto, se hacían tiros de prueba con explosivo y se registraba la propiedad.
2. **Extracción:** los trabajadores rompían la costra y el caliche con barretas y tiros. El caliche se cargaba en **carretas** (después, carros) hasta la planta.
3. **Chancado:** el caliche se trituraba.
4. **Lixiviación en caliente:** en los **cachuchos** (grandes recipientes) se disolvía con agua calentada a vapor.
5. **Cristalización:** el caldo pasaba a **bateas** donde el salitre cristalizaba al enfriarse.
6. **Secado:** en las **canchas** al sol. Luego se **ensacaba**.
7. **Transporte al puerto y embarque** (ver §2.4).

### 2.3 Tres sistemas que convivían en 1879

| Sistema | Desde | Cómo funcionaba | Fuente | Confianza |
|---|---|---|---|---|
| **Paradas** | primera mitad del s. XIX (un pie de foto lo sitúa hacia 1830) | Dos fondos o calderas a **fuego directo**, en fogones improvisados. Exigía caliche muy rico (se cita >60 %), mucha leña y mano de obra. Campamentos **itinerantes** que se movían por la pampa. Deforestó el tamarugal (La Tirana, Canchones) | Memoria Chilena; «Paradas method», Wikipedia en inglés | [D] el método; [P] el umbral de 60 % |
| **Vapor (Gamboni)** | ~1853 | Reemplaza el fuego por vapor de agua | Memoria Chilena; «Paradas method» | [D] |
| **Shanks** | 1876 (Memoria Chilena: J. T. Humberstone, oficina San Antonio) **o** 1878 (Wikipedia en inglés, «James Thomas Humberstone») | Lixiviación en caliente adaptada del método inglés de James Shanks. Planta **fija**, más rápida, aprovecha residuos. Combustible: **carbón mineral**. Da origen a la **oficina salitrera** como pueblo estable (campamento, pulpería, administración) | Memoria Chilena; «Sistema Shanks», Wikipedia en español | [C] la fecha y la oficina; [D] el resto |

- Memoria Chilena indica que Shanks fue **mayoritario entre 1880 y 1920**. Por tanto, en 1879 aún había muchas oficinas de paradas o de vapor simple. [I] La proporción exacta en 1879 es **[P]**.

### 2.4 Del cantón al puerto

- **Ferrocarriles salitreros** (detalle en geografia-1879 §8): Iquique–La Noria (inaugurado en **julio de 1871** según la cronología del Álbum del Desierto; Donoso sitúa la inauguración de The Nitrate Railways en **1868**) [C]; entre 1870 y 1875 se extendió una red desde Iquique a numerosas oficinas [D]; Pisagua–interior (Zapiga, Dolores) [D] la existencia, [P] el trazado; Antofagasta–Salar del Carmen (CSFA) [D] el inicio.
- **Carretas de mulas:** siguieron en uso hasta la década de 1890 dentro de los cantones, y el tren cubría el tramo largo a la costa (González Miranda, citado en el resultado de búsqueda del Álbum del Desierto/Revista Academia). [D] en lo general.
- **Embarque:** los puertos (Iquique, Pisagua, Antofagasta, Tocopilla) eran caletas al pie del acantilado (geografia §6.1). Los sacos se llevaban a los buques fondeados en **lanchas**. [P] (de conocimiento general; no se encontró una fuente concreta en esta tarea).

### 2.5 Quién lo controlaba

- **Tarapacá (Perú):** *estanco del salitre* en **1873** (el gobierno compraba toda la producción a precio fijo; fracasó y se derogó) y **expropiación de las oficinas en 1875**, pagada con certificados de deuda. En 1876 Antony Gibbs & Sons fue consignataria del salitre peruano, y Perú compró las licencias de **El Toco** que Bolivia remató el 13 de enero de 1876. («War of the Pacific», Wikipedia en inglés.) [D]
- **Antofagasta (Bolivia):** la **CSFA** (antes Melbourne Clark y Cía., 1868; CSFA desde 1872). Accionistas: Agustín Edwards (42,16 %), Gibbs & Cía. (~29 %), Puelma y otros; capital nominal de $2 500 000. Contrato con Bolivia del **27 de noviembre de 1873**: salitre libre de derechos por 15 años desde Antofagasta hasta Salinas, incluido el Salar del Carmen. («Compañía de Salitres y Ferrocarril de Antofagasta», Wikipedia en español.) [D]
- **Impuesto de los 10 centavos** por quintal: ley boliviana del 14 de febrero de 1878, suspendida en abril y reactivada en diciembre de 1878; embargo el 11 de febrero de 1879, remate fijado para el 14 de febrero, día en que Chile ocupó Antofagasta. [D] Su interpretación jurídica es **[C]** (ver geografia §3).

### 2.6 Papel en la guerra

- La ocupación de Tarapacá (noviembre de 1879, tras Pisagua y Tarapacá) puso el salitre peruano en manos chilenas. [D]
- Chile cobró un derecho de exportación de **40 centavos por quintal métrico en 1879**, que subió a **$1,60 en 1880** («War of the Pacific», Wikipedia en inglés, nota 121). [D] según esa fuente; conviene confirmarlo en Sater 2007. [P]
- Chile devolvió las oficinas a los tenedores de los certificados de deuda peruanos. [D]
- Valor de lo perdido por Perú: Farcau habla de «£28 millones anuales de ingreso bruto» por el salitre (citado en la misma página). Es **una sola fuente** y la cifra parece alta frente a la producción de 1878. [C]

---

## 3. Guano

- Excremento de aves marinas, acumulado en islas y en **covaderas** (depósitos en la costa). Fertilizante. [D]
- **Islas de Chincha** (13,64° S, 76,40° W, dentro de la caja): exportación desde **1840**, **casi agotadas hacia 1874** («Chincha Islands», Wikipedia en inglés). Las exportaciones peruanas de guano bajaron de **575 000 t en 1869 a menos de 350 000 t en 1873** (Greenhill y Miller 1973, citados en «Guano Era» y «War of the Pacific», Wikipedia en inglés). [D]
- Los otros yacimientos peruanos grandes de la década de 1870 (Guañape, Macabí, Lobos) están **al norte de 11,5° S, fuera del mapa** [I] por sus latitudes conocidas; sus fechas de explotación son **[P]**.
- **Tarapacá:** Pabellón de Pica (−20,87, −70,14, B), Huanillos (−21,27, −70,10, B) y Punta de Lobos. En Huanillos el gobierno peruano aprobó la extracción en **1874**; trabajaban peruanos, chilenos y **culíes chinos**; población registrada de 825 personas («Huanillos», Wikipedia en inglés, con citas débiles). [P] las cifras.
- **Mejillones:** en la zona de beneficios compartidos (tratados de 1866 y 1874, art. III). [D]
- **Trabajo:** el guano se extraía a mano, en gran parte con culíes chinos en condiciones durísimas: en Chincha, de unos 4 000 llegados desde el inicio del comercio, en 1860 «no sobrevivía ninguno» («Chincha Islands», Wikipedia en inglés). [C] la cifra exacta; [D] la dureza.
- **Guerra:** el **17 de abril de 1879** la escuadra chilena destruyó los muelles y elementos de embarque de Huanillos y Pabellón de Pica (Efemérides de la Guerra del Pacífico, andesacd.org). [C] La fecha viene de una cronología; falta confirmarla en una historia naval. El bloqueo de Iquique empezó el **5 de abril** de 1879 (otra fuente da el 3). [C]
- El guano fue la garantía de la deuda externa peruana (contrato Dreyfus de 1869 y suspensión de pagos de 1876). [D] el hecho general; [P] los detalles del contrato.

---

## 4. Plata

- **Caracoles** (23,03° S, 69,03° W, B; ~3 100 m de altura): descubierto el **24 de marzo de 1870** por cateadores de la expedición de **José Díaz Gana**; primera mina, *La Deseada* (25 de marzo de 1870). En unos ocho años de bonanza produjo **855 202 kg de plata**. Más que una veta, era un campo de plata concentrado alrededor de los primeros hallazgos, de corta vida. Un diccionario de 1899 lo sitúa a unos 200 km al NE de Antofagasta, su salida al mar («Mineral de Caracoles», Wikipedia en español). [D]
  - Su ubicación respecto del paralelo 23 motivó el art. II del tratado de 1874 (geografia §3). [D]
  - En 1879 estaba **en declive** [I] (por la descripción de «corta vida» tras unos ocho años desde 1870).
  - Agua de Caracoles: se traía o se condensaba en la costa; no hay fuente concreta. [P]
- **Huanchaca–Pulacayo** (Bolivia, cerca de Uyuni, ~20,4° S, ~66,7° W, **fuera de la caja**, que termina en 67° W; coordenada [P]): la Compañía Huanchaca, dominada por **Aniceto Arce** desde la década de 1850 y refundada con capitales chilenos (1872, 1873 o 1877 según la fuente: [C]), produjo **más del 50 % de la plata boliviana entre 1872 y 1895**; tenía 1 567 trabajadores en 1877 (artículo de una revista chilena de ingeniería en revistas.uchile.cl, visto solo como resultado de búsqueda). [C]
  - Que los intereses mineros de Arce explicaran la postura «pacifista» de una parte de la élite boliviana es una **interpretación** (CEDIB, *Breve historia de la minería en Bolivia II*), no un hecho establecido. [C]
- **Potosí** (~65,75° W): fuera de la caja. [I]
- **Chañarcillo** (Norte Chico chileno, descubierto en la década de 1830) dio origen a la corrida de la plata que llevó chilenos al desierto. [D] el hecho; [P] la coordenada y su producción en 1879.
- **Huantajaya** (Tarapacá, plata colonial): actividad en 1879 **[P]**.

---

## 5. Cobre

- Chile fue el **primer productor mundial de cobre** hasta que Estados Unidos lo superó hacia **1880**. [D] Su participación se cita como **más del 50 % de la producción mundial en 1877–1880** (documento de UNIDO hallado en búsqueda) [C]; otros textos solo dicen «primer productor». Producción de ~34 000 t hacia 1860 (fuente chilena hallada en búsqueda). [P]
- Exportaciones de barras y lingotes: de $1,2 millones en 1844 a **$13 millones en 1878** (Cambridge, *The Americas*, estudio de la fundición Urmeneta y Errázuriz, 1860–1880). [D] según ese resumen.
- Se fundía con **carbón**: fundiciones costeras y, desde 1867, una **fundición de cobre en Lota** que procesaba mineral del norte (Memoria Chilena, «Lota y Coronel»). [D]
- Centros: Norte Chico (Atacama y Coquimbo: Tamaya, Carrizal, Chañaral) [P] la lista y las coordenadas; **Tocopilla** (litoral boliviano en 1879, −22,09, −70,20, A) y **Chañaral** (−26,35, −70,62, A) como puertos del cobre (geografia §7). **Corocoro** (altiplano boliviano, ~17,2° S, ~68,5° W, dentro de la caja; coordenada [P]).
- Papel militar directo: poco [I]. Su peso es económico (la crisis chilena de la década de 1870 con el cobre, la plata y el trigo es uno de los motivos que algunos historiadores dan a la guerra: **[C]**, «War of the Pacific», Wikipedia en inglés).

---

## 6. Carbón

- **Lota y Coronel** (golfo de Arauco, Lota ~37,09° S, 73,16° W): explotación desde **1852** por **Matías Cousiño** (Compañía Carbonífera de Lota). Primero abastecía a los vapores que cruzaban el estrecho de Magallanes; luego ferrocarriles e industria; fundición de cobre desde 1867 (Memoria Chilena, «Lota y Coronel (1854-1995)»; «Lota, Chile», Wikipedia en inglés). [D]
- Producción: **más de 100 000 t en 1870** y **200 000 t en 1882** (resumen de un artículo de historia minera hallado en búsqueda; no se leyó la fuente original). [P]
- **Guerra:** en 1879 el primer vapor de la compañía, el *Matías Cousiño*, llevó carbón a Antofagasta para la escuadra (misma fuente). [P] Los buques chilenos se reaprovisionaban de carbón en la zona de operaciones: p. ej., en marzo de 1880 la *Chacabuco* y el *Loa* llevaron carga de Iquique al bloqueo de Mollendo y allí se reaprovisionó de carbón (Revista de Marina, artículos sobre logística naval, resultado de búsqueda). [P] la fuente exacta.
- **Está fuera de la caja del mapa** (ADR-014 corta en 33,5° S). Cómo representarlo es **Q-014**.
- **Perú y el carbón:** no se encontró fuente sobre su abastecimiento (importado, presumiblemente británico) ni sobre escasez en 1879. Una ficha del *Huáscar* (naval-encyclopedia.com) dice que daba entre 9 y 12,3 nudos según la calidad del carbón, la presión del vapor y el estado de las calderas y del casco: la calidad del carbón importaba. [P] todo lo demás. **No usar «carbón de Cardiff» como dato** hasta verificarlo.

---

## 7. Agua

- El agua era el recurso limitante (ejercitos §5, geografia §6.2). [D]
- **Antofagasta:** planta **condensadora de agua de mar desde 1869**; tras Caracoles (1870) el abasto no alcanzó y se trajo agua de Coquimbo y Caldera y se instalaron más plantas («Aguas Antofagasta», copia de Wikipedia en español en es-academic). [C] (fuente débil; la fecha se cita también como 1870).
- **Pisagua:** un documento de la campaña de Tarapacá (Memoria Chilena, MC0007407, reproducido por la Academia de Historia Militar) cuenta que el presidente Pinto creía que Pisagua destilaba su agua «como se hacía en Antofagasta i en los puertos chilenos de Coquimbo al norte», pero que en realidad la recibía de **Arica en vapores-cisterna** y por **ferrocarril desde Dolores**; tras la ocupación ambos cortaron y hubo escasez. [D] según el fragmento; no se pudo leer el PDF completo (es un escaneo).
- **Iquique bajo bloqueo (1879):** la falta de agua minó la moral y llevó a construir condensadores (artículo académico hallado en búsqueda). [P] fechas y detalles.
- Las condensadoras queman **carbón** [I] (son calderas): el agua de los puertos depende del carbón.

---

## 8. Agricultura y víveres

- **Perú:** valles costeros con haciendas de **caña de azúcar y algodón** (Rímac, Cañete, Pativilca, Supe; Cañete ~13,1° S, dentro de la caja), con mano de obra de culíes chinos (más de 100 000 llegados entre 1849 y 1874) (Discover Nikkei; Brown University, *Modern Latin America*). [D] en lo general. Valles del sur (Ica, Moquegua, Tacna, Azapa) con vino, aguardiente y forraje. [P] el detalle.
- **Expedición Lynch** (4 sept.–nov. 1880): unos 2 600 hombres, Chimbote, Paita, Eten, Chiclayo; cupos a hacendados y destrucción de bienes de quien no pagaba (≈ US$ 4,7 millones según el artículo) («Lynch Expedition», Wikipedia en inglés). [D] el hecho; [C] las cifras. **Fuera de la caja** (al norte de 11,5° S): según ADR-014 va como evento o texto.
- **Chile:** el trigo del valle central se exportaba a Inglaterra desde mediados de la década de 1860; el ciclo triguero declinaba a fines de la de 1870 (Memoria Chilena, «Exportación de trigo»). [D] Los molinos de Concepción y del Maule quedan **fuera de la caja**; dentro está el valle de Aconcagua–Valparaíso. [I]
- **Oasis del desierto:** Pica, Calama, Chiu Chiu, San Pedro de Atacama y Quillagua daban agua, forraje y algo de víveres a las rutas de recuas (geografia §8). [P] la producción.
- **Bolivia:** sus valles agrícolas (Cochabamba, Chuquisaca) están **fuera de la caja**. [I]

---

## 9. Transporte de los recursos

| Medio | Uso | Confianza |
|---|---|---|
| Carreta de mulas | Caliche dentro del cantón; salitre al puerto donde no había tren | [D] |
| Recua de mulas o llamas | Altiplano–costa; minerales de alta montaña (Caracoles, Corocoro) | [D] en lo general |
| Ferrocarril salitrero | Cantón–puerto (Iquique, Pisagua, Antofagasta); también traía agua (Dolores–Pisagua) | [D]/[P] (geografia §8) |
| Lancha | Del muelle o la playa al buque fondeado | [P] |
| Vapor y velero | Exportación a Europa; cabotaje de carbón, agua y víveres | [D] |

---

## 10. Propuesta de representación en el juego [J]

Todo este apartado es **propuesta** para T-022. Respeta ADR-007 (los recursos son `ResourceDef`; los edificios, `BuildingDef`) y los recursos provisionales de unidades.md §4 (**V** víveres, **P** pesos, **C** carbón).

### 10.1 Recursos del jugador (sugerencia)

| ResourceDef sugerido | Viene de | Histórico |
|---|---|---|
| `viveres` | Haciendas de valle y oasis | Víveres y forraje de los ejércitos |
| `pesos` | Exportar salitre, guano, plata y cobre **por un puerto propio** | Los minerales valían por su exportación; el fisco vivía de ella |
| `carbon` | Según Q-014 | Combustible de buques y calderas |
| (agua) | Mejor como **mecánica de logística** (radio de aguadas y condensadoras), no como recurso acumulable | Coherente con unidades.md §6.3 («sin agua, munición ni desgaste en v1») |

El salitre, el guano, la plata y el cobre **no** serían recursos acumulables, sino **cargas** que se convierten en pesos al embarcarse. [J] Así el mapa muestra las rutas y la guerra económica (bloqueo, corte del ferrocarril) tiene efecto, como en 1879.

### 10.2 Cadena general: yacimiento → extractor → ruta → puerto

1. **Yacimiento** fijo en el mapa, en su ubicación histórica (datos del mapa, T-011). No se crean yacimientos donde no los había.
2. **Edificio extractor** sobre el yacimiento, con una animación de trabajo en bucle.
3. **Transporte visible**: carretas de mulas (lentas, baratas) o tren (rápido, solo sobre vía construida o histórica), que llevan la carga al puerto. Se pueden atacar o cortar.
4. **Puerto** con muelle: las **lanchas** van del muelle al buque y la carga se convierte en pesos. Un **bloqueo naval** (buque enemigo cerca) frena o detiene la conversión: Iquique, abril de 1879.
5. **Ataque costero**: un buque puede destruir el muelle (Huanillos y Pabellón de Pica, 17 de abril de 1879).

### 10.3 Por recurso

| Recurso | Edificio extractor | Animación | Ruta al puerto | Sitios del mapa |
|---|---|---|---|---|
| Salitre | **Oficina salitrera** (planta con chimenea, cachuchos, canchas, campamento) | Humo de la chimenea; operarios con barreta en el manto; montones blancos en las canchas | Carreta al tren o al puerto; tren salitrero | Cantones de Zapiga, Negreiros, La Noria, Pozo Almonte, Lagunas; Salar del Carmen; El Toco |
| Guano | **Covadera** (rampa o manga de carga, sacos, barracas) | Operarios con pala y carretilla; sacos que bajan al muelle | Directo al muelle (la covadera está en la costa) | Pabellón de Pica, Huanillos, Punta de Lobos, Mejillones; Chincha según Q-015 |
| Plata | **Mina de plata** (pique con cabria o malacate, desmonte, cancha) | Malacate girando; recua que sale | Recua de mulas a la costa (Antofagasta) | Caracoles (según Q-015); Corocoro y Tocopilla para el cobre |
| Cobre | **Mina de cobre** + **fundición** (horno y chimenea) | Humo de la fundición | Recua o carreta a Tocopilla, Chañaral, Caldera | Norte Chico, Tocopilla |
| Carbón | Según **Q-014** (sin edificio extractor en la opción A) | Vapor carbonero que llega por el borde del mapa | Por mar a la **carbonera** del puerto | Valparaíso y puertos propios |
| Víveres | **Hacienda** (casas, cultivos, acequias) o **chacra de oasis** | Cultivo que cambia de color; carretas | Carreta al almacén o al puerto | Valles de Lima, Cañete, Ica, Moquegua, Tacna, Azapa, Aconcagua; oasis |
| Agua | **Condensadora** en el puerto y **aguada/pozo** en el desierto | Caldera con humo; estanques | El agua no viaja como recurso: da un radio de abasto | Antofagasta, Iquique, Pisagua; aguadas de la ficha de geografía |

### 10.4 Lo que cambia por bando (datos para T-022 y T-031) [I]

- **Bolivia** perdió su litoral y Caracoles entre febrero y marzo de 1879, y sus fuentes de plata (Huanchaca, Potosí) y sus valles agrícolas están **fuera de la caja**. Dentro del mapa le queda poco que extraer (Corocoro, oasis del altiplano y de Atacama). T-022/T-031 tendrán que compensarlo de algún modo (p. ej. un ingreso fuera del mapa). Esto es una **decisión de diseño**, no de historia.
- **Chile** controla el carbón (Lota, fuera del mapa) y, tras Pisagua, el salitre de Tarapacá.
- **Perú** empieza con el salitre de Tarapacá, el guano y los valles agrícolas más ricos, pero depende del mar para el carbón y la exportación.

### 10.5 Licencias creativas propuestas (no decididas)

| Id | Licencia | Estado |
|---|---|---|
| L1 | Una sola oficina salitrera tipo Shanks para todas, aunque en 1879 convivían paradas, vapor y Shanks (§2.3) | **Q-015** |
| L2 | Tiempos de extracción, transporte y embarque comprimidos (días o semanas → segundos o minutos) | **Q-015** |
| L3 | Yacimientos según su estado en 1879: Chincha casi agotada y Caracoles en declive | **Q-015** |
| L4 | Representación del carbón de Lota y Coronel, fuera del mapa | **Q-014** |
| — | Las lupas (ADR-009, T-040) amplían ciudades y puertos; los edificios industriales van a tamaño real (ADR-009) | Ya decidido; no es nueva |

---

## 11. Modelos de edificios industriales para arte

Prioridad sugerida: **1** = imprescindible para T-022 v1; **2** = deseable; **3** = después. Hasta que existan, se usa la representación provisional de ADR-005/ADR-007 (`placeholder_shape`, `placeholder_label`). En `assets/models/kenney/fantasy_town_kit` ya hay piezas útiles como provisionales (`cart.glb`, `chimney*.glb`, `planks*.glb`, `poles*.glb`).

| # | Modelo | Partes que lo hacen reconocible | Prioridad | Referencia histórica |
|---|---|---|---|---|
| 1 | Oficina salitrera | Chimenea de ladrillo o fierro, cachuchos (estanques rectangulares de fierro), canchas blancas de secado, montones de caliche, casas del campamento | 1 | Fotografías de oficinas de Tarapacá en Memoria Chilena (las más cercanas son de ~1880–1889; Oficina Ramírez hacia 1880) |
| 2 | Carreta salitrera de mulas | Carreta de dos ruedas grandes con tiro de varias mulas | 1 | Memoria Chilena |
| 3 | Muelle de embarque con lanchas | Muelle de madera sobre pilotes, pescante, lanchas a remo con sacos | 1 | «Embarque de salitre en Pisagua» (1891), Memoria Chilena |
| 4 | Covadera de guano | Rampa o manga de carga, sacos, barracas | 1 | Huanillos, Pabellón de Pica [P] fotos de época |
| 5 | Mina de plata | Pique con cabria o malacate a sangre (mulas), desmonte, casucha | 1 | Caracoles [P] fotos |
| 6 | Hacienda / chacra | Casa de adobe, cultivo, acequia | 1 | Valles del sur del Perú y oasis |
| 7 | Condensadora de agua | Caldera, chimenea, estanques; junto al mar | 1 | Antofagasta [P] imágenes |
| 8 | Vía férrea, locomotora y vagones salitreros | Locomotora pequeña de la década de 1870, vagones abiertos con sacos | 2 | Iquique–La Noria, Antofagasta |
| 9 | Estación ferroviaria | Andén, bodega de madera, estanque de agua | 2 | |
| 10 | Carbonera de puerto | Pila de carbón, bodega, grúa de mano | 2 | |
| 11 | Fundición de cobre | Horno de reverbero y chimenea alta | 3 | Norte Chico, Lota |
| 12 | Aguada / pozo | Pozo con brocal, bebederos | 2 | Aguadas de la pampa |
| 13 | Ingenio azucarero | Trapiche, chimenea, cañaveral | 3 | Valles de Lima y Cañete |
| 14 | Recua de mulas / llamas (unidad o efecto) | Animales con carga | 2 | Rutas del altiplano |

**Pendiente para arte:** reunir fotos de época (Memoria Chilena, Biblioteca Nacional del Perú) de cada edificio antes del modelado.

---

## 12. Lo que no se sabe o queda pendiente

- [ ] Producción de salitre de 1878 separada por Tarapacá y Antofagasta, y número de oficinas por sistema (paradas/vapor/Shanks) en 1879.
- [ ] Fecha y oficina de la introducción del sistema Shanks (1876 San Antonio o 1878).
- [ ] Derecho de exportación chileno de 1879–1880 (confirmar en Sater 2007 o en Bulnes).
- [ ] Producción de Lota en 1879 y suministro de carbón a la escuadra (fuente original).
- [ ] Abastecimiento de carbón de la marina peruana (origen, escasez).
- [ ] Destrucción de los muelles guaneros del 17 de abril de 1879 (confirmar en una historia naval).
- [ ] Condensadoras de agua: número, capacidad y ubicación en Antofagasta, Iquique y Pisagua.
- [ ] Embarque en lanchas: fuente concreta.
- [ ] Coordenadas de Pulacayo, Corocoro, Chañarcillo, Tamaya, Carrizal, Punta de Lobos y El Toco.
- [ ] Situación de Caracoles y Huantajaya en 1879.
- [ ] Fotos de época para cada modelo de §11.

---

## Fuentes

**Consultadas en esta tarea** (en línea, octubre de 2026)

- Memoria Chilena, Biblioteca Nacional de Chile, «Explotación del salitre»: https://www.memoriachilena.gob.cl/602/w3-article-93821.html
- Memoria Chilena, «Lota y Coronel (1854-1995)»: https://www.memoriachilena.gob.cl/602/w3-article-734.html
- Memoria Chilena, «Exportación de trigo»: https://www.memoriachilena.gob.cl/602/w3-article-94448.html (visto como resultado de búsqueda)
- Memoria Chilena, documento MC0007407 sobre la campaña de Tarapacá, reproducido por la Academia de Historia Militar: https://www.academiahistoriamilitar.cl/academia/wp-content/uploads/2021/11/BATALLA-DE-SAN-FRANCISCO-O-DE-DOLORES.-19-DE-NOVIEMBRE-DE-1879.pdf (solo el fragmento citado en la búsqueda; el PDF es un escaneo)
- «Sistema Shanks», Wikipedia en español: https://es.wikipedia.org/wiki/Sistema_Shanks
- «Paradas method», Wikipedia en inglés: https://en.wikipedia.org/wiki/Paradas_method
- «James Thomas Humberstone», Wikipedia en inglés: https://en.wikipedia.org/wiki/James_Thomas_Humberstone
- «Compañía de Salitres y Ferrocarril de Antofagasta», Wikipedia en español: https://es.wikipedia.org/wiki/Compa%C3%B1%C3%ADa_de_Salitres_y_Ferrocarril_de_Antofagasta
- «War of the Pacific», Wikipedia en inglés (estanco, expropiación, 10 centavos, derecho de exportación, Farcau): https://en.wikipedia.org/wiki/War_of_the_Pacific
- «Guano Era», Wikipedia en inglés: https://en.wikipedia.org/wiki/Guano_Era
- «Chincha Islands», Wikipedia en inglés: https://en.wikipedia.org/wiki/Chincha_Islands
- «Huanillos», Wikipedia en inglés: https://en.wikipedia.org/wiki/Huanillos
- «Mineral de Caracoles», Wikipedia en español: https://es.wikipedia.org/wiki/Mineral_de_Caracoles
- «Compañía Minera Huanchaca», Wikipedia en inglés: https://en.wikipedia.org/wiki/Compa%C3%B1%C3%ADa_Minera_Huanchaca (resultado de búsqueda)
- CEDIB, *Breve historia de la minería en Bolivia II*: https://cedib.org/wp-content/uploads/2012/03/Breve-historia-de-la-mineria-en-Bolivia-II.pdf (resultado de búsqueda)
- «Lota, Chile», Wikipedia en inglés: https://en.wikipedia.org/wiki/Lota,_Chile
- «Lynch Expedition», Wikipedia en inglés: https://en.wikipedia.org/wiki/Lynch_Expedition
- Efemérides de la Guerra del Pacífico (andesacd.org): https://www.andesacd.org/wp-content/uploads/2020/03/Efem%C3%A9rides-de-la-Guerra-del-Pac%C3%ADfico.pdf (resultado de búsqueda)
- Revista de Marina, artículos sobre logística naval en la guerra (p. ej. https://revistamarina.cl/revistas/1982/5/vlarenasq.pdf y https://revistamarina.cl/revistas/1981/2/jgonzalezo.pdf; resultados de búsqueda, sin identificar cuál contiene el pasaje de Mollendo)
- «Huáscar (1865)», naval-encyclopedia.com: https://www.naval-encyclopedia.com/industrial-era/chile/huascar-1865.php (resultado de búsqueda)
- Álbum del Desierto, cronología: https://albumdesierto.cl/eco/pdfs/artic19.pdf ; Revista Academia (Donoso, ferrocarriles salitreros): https://revistas.academia.cl/index.php/academia/article/view/1766/1997 (resultados de búsqueda)
- «Aguas Antofagasta» (copia de Wikipedia en español): https://es-academic.com/dic.nsf/eswiki/48886 (resultado de búsqueda)
- *The Copper Smelting Company «Urmeneta y Errázuriz» of Chile: An Economic Profile, 1860–1880*, *The Americas* (Cambridge): https://www.cambridge.org/core/journals/americas/article/copper-smelting-company-urmeneta-y-errazuriz-of-chile-an-economic-profile-18601880/E5F927871BC5ABB3F232CA4715B8BD0C (resumen)
- Discover Nikkei, «Emigrantes chinos y japoneses»: https://discovernikkei.org/en/journal/2007/9/11/emigrantes-chinos-y-japoneses/ ; Brown University, «Chinese in Peru in the 19th century»: https://library.brown.edu/create/modernlatinamerica/?p=700 (resultados de búsqueda)

**Obras de referencia para verificar lo pendiente** (no consultadas en esta sesión)

- Sater, William F. *Andean Tragedy: Fighting the War of the Pacific, 1879–1884*. University of Nebraska Press, 2007.
- Bulnes, Gonzalo. *Guerra del Pacífico*. 3 vols. Valparaíso, 1911–1919. Visión chilena.
- Basadre, Jorge. *Historia de la República del Perú*. Visión peruana.
- Querejazu Calvo, Roberto. *Guano, salitre, sangre*. La Paz, 1979. Visión boliviana.
- Greenhill, R. y Miller, R. «The Peruvian Government and the Nitrate Trade, 1873–1879». *Journal of Latin American Studies*, 1973.
- Bermúdez, Óscar. *Historia del salitre desde sus orígenes hasta la Guerra del Pacífico*. Santiago, 1963.
- González Miranda, Sergio. Estudios sobre la pampa salitrera de Tarapacá.
- Zolezzi, Mario. *Historia de los puertos guaneros del litoral de Tarapacá (hasta 1879)*. CREAR, 1993.
- Mitre, Antonio. *Los patriarcas de la plata*. Lima, 1981. Minería boliviana.
- Pederson, Leland R. *The Mining Industry of the Norte Chico, Chile*. 1966.
