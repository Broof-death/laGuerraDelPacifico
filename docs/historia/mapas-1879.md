# Mapas históricos de referencia (1879–1884)

Ficha histórica de la tarea **T-034** (propuesta P-002). Reúne mapas de época con licencia libre para dos usos:

1. **Referencia geográfica** del mapa continuo (T-011): toponimia, ferrocarriles, caminos, aguadas y salitreras tal como se conocían en 1879.
2. **Referencia de estilo** para el minimapa, el mapa estratégico y los menús, que la guía [`docs/diseno/estilo-visual.md`](../diseno/estilo-visual.md) propone tratar como cartografía impresa de la época.

**Fichas y decisiones relacionadas**

- [geografia-1879.md](geografia-1879.md) §1: el mapa de Turner (1879) con sus puntos de control para georreferenciarlo. Esta ficha no repite ese análisis.
- [sitios-clave-escala.md](sitios-clave-escala.md) (T-040, rama `feature/T-040-sitios-clave`): las lupas. Los planos de batalla de la sección 3 sirven para dibujarlas.
- [recursos-1879.md](recursos-1879.md) §11 (T-035, rama `feature/T-035-recursos-epoca`): modelos industriales. Las salitreras y los ferrocarriles de los mapas de Bertrand sirven para ubicarlos.
- **ADR-009** (escala 1:20, caja de 131 km), **ADR-014** (caja Callao–Valparaíso), **ADR-015** (fronteras neutrales con aviso) y **ADR-017** (salitreras).

Los archivos descargados están en [`docs/referencias/mapas/`](../referencias/mapas/README.md). `docs/` tiene `.gdignore`, así que Godot no los importa y no forman parte del juego.

---

## Cómo leer esta ficha

- **[D] Documentado:** el dato viene de la ficha del catálogo de la institución o del propio mapa (título, fecha, autor impresos).
- **[O] Observado:** lo describe el historiador mirando la imagen descargada. Es fiable para el contenido visible, no para la exactitud geográfica.
- **[C] Discutido:** fuentes o catálogos que no coinciden.
- **[I] Inferido:** deducción del historiador a partir de lo documentado o lo observado; no es un dato de fuente.
- **[P] Pendiente:** no se pudo verificar en esta tarea.

**Licencias y abreviaturas**

| Marca | Significado | Qué se puede hacer |
|---|---|---|
| **DP** | Dominio público. Así lo marca Wikimedia Commons (obra antigua y reproducción fiel de una obra plana) | Copiar, modificar y usar, también comercialmente. Citar la fuente es buena práctica |
| **PCC** | «Patrimonio cultural común», según la ficha de Memoria Chilena / Biblioteca Nacional de Chile: «puede ser utilizado y reproducido libremente» | Igual que DP. Las miniaturas de Memoria Chilena llevan una marca de agua del sitio |
| **NKC** | «No Known Copyright» o «No known copyright restrictions» (Princeton, British Library en Flickr Commons) | Uso libre según la institución |
| **NC** | David Rumsey Map Collection: «Images may be reproduced or transmitted, but not for commercial use», con licencia Creative Commons (CC BY-NC-SA 3.0 según la copia en Stanford) | **Solo referencia.** No se usan dentro del juego. Por decisión de Feño (comentario en T-034), las dos láminas de Paz Soldán (1865) se guardan en el repositorio como referencia; si el juego pasa a ser comercial, hay que revisar esta licencia. Los demás mapas NC solo se enlazan |
| **CC BY-SA** | Fotografía o dibujo moderno con licencia libre | Uso libre citando autor y licencia; las obras derivadas llevan la misma licencia |

**Por qué los mapas de 1879 son de dominio público [D/I].** Los autores identificados murieron hace más de 70 años: Alejandro Bertrand (1854–1942), Mariano Felipe Paz Soldán (1821–1886), Clements Markham (1830–1916). Chile y Perú protegen las obras durante la vida del autor más 70 años. En los mapas sin autor identificado, la fecha de publicación (1859–1887) deja el plazo muy atrás [I].

**Matiz sobre los escaneos [C].** Commons considera de dominio público la reproducción fiel de una obra plana antigua. Algunas instituciones (David Rumsey, Gallica de la BnF) ponen condiciones de uso propias a sus escaneos. Por eso, cuando un mapa de esas colecciones está también en Commons, aquí se anotan las dos situaciones. Para un uso **dentro del juego** (no solo como referencia), preferir las copias marcadas PCC, NKC o DP cuyo origen no tenga condiciones contractuales.

**Equilibrio entre los tres países.** La mayoría de los mapas de la guerra con licencia libre que se encontraron son **chilenos**: la Oficina Hidrográfica de la Armada de Chile y el *Boletín de la Guerra del Pacífico* (Santiago, 1879–1881), que la Biblioteca Nacional de Chile digitalizó y declaró de uso libre. Sus títulos y leyendas reflejan ese punto de vista («Territorio ocupado en Tarapacá por el ejército chileno», «Puntos de desembarco del Ejército Chileno»). Para compensar se incluyen la cartografía nacional peruana (Paz Soldán, 1865) y boliviana (Ondarza, Mujía y Camacho, 1859), un autor británico (Turner, 1879; Markham, 1882) y uno austrohúngaro (Gopčević, 1887). La búsqueda en la Biblioteca Nacional del Perú y en repositorios bolivianos queda **pendiente** (§6). Las cifras de bajas o de efectivos impresas en algunos planos son del bando que los publicó y **no se usan como dato**.

---

## 1. Resumen

| # | Archivo en `docs/referencias/mapas/` | Mapa | Año | Origen | Licencia |
|---|---|---|---|---|---|
| 1 | `atacama_1879_turner_stanford.png` | Turner, *District of Atacama* | 1879 | Reino Unido (RGS) | NKC |
| 2 | `bertrand_1879_teatro_guerra_loa_camarones.jpg` | Bertrand, *Mapa detallado del teatro de la guerra* (Loa–Camarones) | 1879 | Chile | PCC |
| 3 | `bertrand_1879_desiertos_tarapaca_atacama.jpg` | Bertrand / Oficina Hidrográfica, *Carta de los desiertos de Tarapacá i de Atacama* | 1879 | Chile | DP |
| 4 | `bertrand_1879_territorio_ocupado_tarapaca.jpg` | Bertrand, territorio ocupado en Tarapacá | 1879 | Chile | DP |
| 5 | `bertrand_1879_hoya_titicaca.jpg` | Bertrand, *Carta de la hoya del lago Titicaca* | 1879 | Chile | DP |
| 6 | `bertrand_1879_costas_peru_chilca_chancay.jpg` | Oficina Hidrográfica, *Costas del Perú entre Chilca i Chancay* | 1879 | Chile | DP |
| 7 | `prieto_1880_costas_peru_islay_chilca.jpg` | Prieto / Oficina Hidrográfica, *Costas del Perú, Islay–Chilca* | 1880 | Chile | DP |
| 8 | `markham_1882_campaign_of_tarapaca.jpg` | Markham, *Campaign of Tarapaca* | 1882 | Reino Unido | DP |
| 9 | `gopcevic_1887_kriegsgeschichtliche_studien_p697.jpg` | Gopčević, *Karte und Pläne zum Südamerikanischen Kriege* | 1887 | Austria-Hungría (ed. Leipzig) | NKC |
| 10 | `prieto_1879_combate_naval_iquique.jpg` | Prieto, *Combate naval de Iquique* | 1879 | Chile | DP |
| 11 | `bianchi_1879_combate_angamos.jpg` | Bianchi Tupper, *Combate de Angamos* | 1879 | Chile | DP |
| 12 | `prieto_1880_prise_arica.jpg` | Prieto, *Prise d'Arica, 7 juin 1880* | 1880 | Chile | PCC |
| 13 | `orrego_1881_lurin_lima.pdf` | Orrego, plano de Lurín a Lima (San Juan, Chorrillos, Miraflores) | 1881 | Chile | DP |
| 14 | `paz_soldan_1865_mapa_general_peru.jpg` | Paz Soldán, *Mapa general del Perú* | 1865 | Perú | DP en Commons / NC en Rumsey: **solo referencia** |
| 15 | `paz_soldan_1865_tacna_arica.jpg` | Paz Soldán, *Tacna y Arica* (departamento de Moquegua) | 1865 | Perú | DP en Commons / NC en Rumsey: **solo referencia** |
| 16 | `ondarza_colton_1859_bolivia.jpg` | Ondarza, Mujía y Camacho, *Mapa de la República de Bolivia* | 1859 | Bolivia (impreso en Nueva York) | DP |

Las imágenes grandes se guardaron reducidas (lado mayor de 2400 px, JPEG de calidad 82) para no inflar el repositorio. El enlace de cada ficha lleva al original en alta resolución.

---

## 2. Mapas generales del teatro de operaciones

### 2.1 Turner, *Map of the District of Atacama* (1879)

Ya descrito en [geografia-1879.md](geografia-1879.md) §1 y en el README de la carpeta, con los puntos de control para georreferenciarlo.

- **Autor y publicación [D]:** W. J. Turner (dibujo) y Edward Weller (grabado), para los *Proceedings of the Royal Geographical Society*, Londres, 1879.
- **Licencia [D]:** «No Known Copyright», según Princeton University Library.
- **Enlace:** https://maps.princeton.edu/catalog/princeton-4f16c534z
- **Interés para el estilo [O]:** es el único mapa del conjunto con **coloreado a mano de los tres países**: Perú en ocre, Bolivia en verde (más claro entre 23° y 24° S) y Chile en un rosado que el papel envejecido volvió salmón. Es la referencia principal de la paleta cartográfica (ver `estilo-visual.md` §2.2). Es un mapa británico, ajeno a los tres bandos.

### 2.2 Bertrand, *Mapa detallado del teatro de la guerra, desde el río Loa hasta Camarones* (1879)

- **Autor [D]:** Alejandro Bertrand (1854–1942), dibujante. Al pie: «Procedimiento L. Moock», «Fotoimp. Brandt». Santiago.
- **Fecha [C]:** el mapa dice 1879; el catálogo da «entre 1879 y 1884». Muestra los **puntos de desembarco del Ejército chileno** (estrellas en Pisagua y Junín), así que es posterior al 2 de noviembre de 1879 [I].
- **Cobertura [O]:** de la quebrada de Camarones (~19° 10′ S) a la desembocadura del Loa (~21° 25′ S), con el meridiano 70° W en el centro. Costa, Pampa del Tamarugal, cantones salitreros (Zapiga, Sal de Obispo, Negreiros, La Peña, Noria), Iquique, Pisagua, Tarapacá, Pica y la quebrada de Tarapacá.
- **Leyenda [O]:** ferrocarriles (línea gruesa), carreteras (línea con puntos), senderos (línea cortada), salitreras (punteado), salares (rayado), prefecturas y subprefecturas (círculos concéntricos), capitales de distrito, pueblos o estancias (círculo), aguadas y oficinas (punto negro), puntos de desembarco (estrella). Altitudes en metros. Escala gráfica en kilómetros.
- **Aspecto [O]:** fotograbado en tinta sepia oscura sobre papel crema, relieve con normales (rayitas de pendiente) y nombres de regiones en mayúsculas espaciadas («P A M P A  D E L  T A M A R U G A L»). Es el mejor modelo del conjunto para el **minimapa** (ver `estilo-visual.md` §4).
- **Licencia [D]:** PCC. «Este documento pertenece al patrimonio cultural común, por lo que puede ser utilizado y reproducido libremente.»
- **Enlace:** Memoria Chilena, https://www.memoriachilena.gob.cl/602/w3-article-546940.html (código BN MC0073663; PDF: https://www.memoriachilena.gob.cl/archivos2/pdfs/MC0073663.pdf). El JPEG local es la imagen incrustada en ese PDF, extraída sin recomprimir (2771 × 3864 px).

### 2.3 Bertrand / Oficina Hidrográfica, *Carta de los desiertos de Tarapacá i de Atacama* (1879)

- **Autor [D]:** Alejandro Bertrand, dibujante, para la Oficina Hidrográfica de Chile («Hidrografía Oficial», carta n.º 15). Litografía de P. Cadot, Santiago. Reproducida en el *Boletín de la Guerra del Pacífico*, p. 284.
- **Cobertura [O]:** de 19° a 24° S y de 71° a 68° W. Es decir, toda la costa entre Camarones y Morro Jara (al sur de Antofagasta), con Calama, Caracoles, San Pedro de Atacama y el Salar de Atacama. Encaja con el mapa de Turner.
- **Calidad [O]:** el escaneo de Commons tiene bandas en negro, partes borradas y la leyenda incompleta. Sirve para toponimia y trazado de caminos, no como modelo de estilo.
- **Licencia [D]:** DP.
- **Enlace:** https://commons.wikimedia.org/wiki/File:Carta_de_los_desiertos_de_tarapaca_y_atacama.png (hay otra copia más pequeña: https://commons.wikimedia.org/wiki/File:Carta_de_los_Desiertos_de_Tarapac%C3%A1_y_de_Atacama_1879.jpg, fechada «Santiago, abril 15 de 1879»).

### 2.4 Bertrand, territorio ocupado en Tarapacá (25 de noviembre de 1879)

- **Autor y fecha [D]:** Alejandro Bertrand Huillard, Santiago, 25 de noviembre de 1879. Biblioteca Nacional de Chile.
- **Interés:** fija la situación tras Pisagua y Dolores y antes de Tarapacá (27 de noviembre). El título refleja el punto de vista chileno.
- **Licencia [D]:** DP.
- **Enlace:** https://commons.wikimedia.org/wiki/File:Territorio_ocupado_en_Tarapac%C3%A1_por_el_ej%C3%A9rcito_chileno_(1879).jpg

### 2.5 Bertrand, *Carta de la hoya del lago Titicaca i de las vías de comunicación con la costa del océano Pacífico* (1879)

- **Autor y fecha [D/O]:** Alejandro Bertrand, carta n.º 14, «publicado de orden del Señor Ministro de Marina i bajo la dirección de la Oficina Hidrográfica en mayo 27 de 1879». Litografía de Pedro Cadot.
- **Cobertura [O]:** de Islay y Arequipa a La Paz y de Puno a Tacna y Arica. Muestra los ferrocarriles de Mollendo–Arequipa–Puno y Arica–Tacna y los caminos del altiplano. Leyenda de prefecturas, subprefecturas, capitales de distrito, villas, ferrocarriles, caminos y minerales; sondas y altitudes en metros.
- **Interés:** cubre las rutas de abastecimiento de Bolivia hacia la costa y la campaña de Tacna y Arica.
- **Licencia [D]:** DP.
- **Enlace:** https://commons.wikimedia.org/wiki/File:Carta_de_la_hoya_del_lago_Titicaca_i_de_las_v%C3%ADas_de_comunicaci%C3%B3n_con_la_costa_del_oce%C3%A1no_Pac%C3%ADfico.png

### 2.6 Oficina Hidrográfica, *Costas del Perú entre puerto Chilca i puerto Chancay* (1879)

- **Autor [D]:** Oficina Hidrográfica de la Armada de Chile, Alejandro Bertrand. *Boletín de la Guerra del Pacífico*, p. 421.
- **Cobertura [D]:** la costa de Lima y el Callao, de Chilca a Chancay. Es la referencia del sector norte de la caja del mapa (ADR-014) y de la lupa `lima_callao`.
- **Licencia [D]:** DP.
- **Enlace:** https://commons.wikimedia.org/wiki/File:Costas_del_Per%C3%BA_entre_puerto_Chilca_i_puerto_Chancay,_1879.png

### 2.7 Prieto / Oficina Hidrográfica, *Costas del Perú: carta del litoral comprendido entre Islay i puerto Chilca* (1880)

- **Autor [D]:** Carlos M. Prieto, dibujante; Oficina Hidrográfica. *Boletín de la Guerra del Pacífico*, p. 880.
- **Cobertura [O]:** de Arequipa e Islay a Chilca, con Ica, Pisco, Huancavelica y Ayacucho. Rosa de los vientos grande; relieve sombreado.
- **Licencia [D]:** DP.
- **Enlace:** https://commons.wikimedia.org/wiki/File:Costas_del_per%C3%BA_entre_islay_y_chilca.png

### 2.8 Markham, *Campaign of Tarapaca* (1882)

- **Autor [D]:** Clements R. Markham, *The War between Peru and Chili, 1879–1882*, Londres, Sampson Low, Marston & Co., 1882.
- **Perspectiva:** británico, con simpatía conocida por el Perú [I]. Útil como contrapeso de los mapas chilenos de la misma campaña.
- **Licencia [D]:** DP.
- **Enlace:** https://commons.wikimedia.org/wiki/File:Campaign_of_Tarapaca.jpg

### 2.9 Gopčević, *Karte und Pläne zum Südamerikanischen Kriege* (1887)

- **Autor [D]:** Spiridion Gopčević, *Kriegsgeschichtliche Studien*, Leipzig, 1887, p. 697. Escaneo de la British Library (Flickr Commons).
- **Contenido [O]:** una lámina con cinco mapas: plano de la batalla de Chorrillos (13 de enero de 1881) con escala en metros; batalla de Tacna (26 de mayo de 1880); combate de Dolores (19 de noviembre de 1879); batalla de Miraflores (15 de enero de 1881); y un mapa general de Arequipa a Antofagasta con la «frontera entre Bolivia y Chile hasta 1881».
- **Interés:** autor ajeno a los tres bandos; los planos usan símbolos sencillos (cuadros para unidades, flechas de movimiento, cruces para artillería) que sirven de modelo para el mapa táctico.
- **Licencia [D]:** NKC («No known copyright restrictions», British Library).
- **Enlace:** https://commons.wikimedia.org/wiki/File:Image_taken_from_page_697_of_%27Kriegsgeschichtliche_Studien%27_(11186664584).jpg

---

## 3. Planos de combates y batallas

Todos son chilenos salvo el de Gopčević (§2.9). Úsense para la forma del terreno y la ubicación, no para las cifras.

### 3.1 Prieto, *Combate naval de Iquique en 21 de mayo de 1879*

- **Autor [D/O]:** Carlos M. Prieto, delineador; litografía de P. Cadot, Santiago. «Según plano del Señor Eduardo Llanos (testigo ocular)». Publicado en Benjamín Vicuña Mackenna, *Chile. Episodios marítimos. Las dos Esmeraldas* (Santiago, 1879), p. 407. Escaneo de la British Library (signatura HMNTS 9781.e.4).
- **Contenido [O]:** derrotas de Huáscar, Independencia, Esmeralda, Covadonga y del vapor Lamar entre Punta Piedras y Punta Gruesa, con la hora de cada posición; escala de 4000 m. Cada buque tiene su propio trazo (continuo, discontinuo, punteado) y una silueta mínima.
- **Interés:** modelo para mostrar **estelas y rumbos de buques** en el mapa naval.
- **Licencia [D]:** DP.
- **Enlace:** https://commons.wikimedia.org/wiki/File:COMBAT_NAVAL_DE_IQUIQUE_-_1879.jpg

### 3.2 Bianchi Tupper, *Combate de Angamos* (1879)

- **Autor [D]:** Álvaro Bianchi Tupper. *Boletín de la Guerra del Pacífico*, p. 388.
- **Licencia [D]:** DP.
- **Enlace:** https://commons.wikimedia.org/wiki/File:Combate_de_angamos_BGP.png

### 3.3 Prieto, *Prise d'Arica, 7 juin 1880*

- **Autor [D]:** Carlos M. Prieto. Litografía de P. Cadot, [Chile], 1880. Texto en francés.
- **Contenido [O]:** plano **coloreado**: la ciudad de Arica en rojo, el relieve del Morro en sepia, los regimientos chilenos como **rectángulos bicolores** con su nombre (Lautaro, Buin, 3.º y 4.º de línea), los fuertes como cuadros rojos y los atrincheramientos con línea de puntos; los buques (Cochrane, Magallanes, Covadonga, Loa, Manco Cápac, transportes y neutrales) como pequeñas siluetas azules. Trae una tabla de pérdidas de ambos bandos (cifras del lado chileno; **no usar como dato**).
- **Interés:** es el mejor modelo del conjunto para la **simbología de unidades** del mapa táctico (ver `estilo-visual.md` §4).
- **Licencia [D]:** PCC.
- **Enlace:** https://www.memoriachilena.gob.cl/602/w3-article-68009.html (código BN MC0007391). La copia local es la única descarga que ofrece el sitio: 750 × 488 px, con la marca de agua de Memoria Chilena. Conviene pedir una copia mayor a la Biblioteca Nacional de Chile [P].

### 3.4 Orrego, plano de los terrenos entre Lurín y Lima (1881)

- **Autor [D]:** Augusto Orrego, «levantado según la orden del Ministro de la Guerra en campaña». Operaciones de San Juan, Chorrillos y Miraflores (13 y 15 de enero de 1881).
- **Licencia [D]:** DP.
- **Enlaces:** Commons (PDF), https://commons.wikimedia.org/wiki/File:San_Juan_Chorrillos_y_Miraflores_de_Augusto_Orrego_1881.pdf ; ficha original en la Biblioteca Nacional Digital de Chile, http://www.bibliotecanacionaldigital.cl/bnd/631/w3-article-311951.html [P: comprobar que el enlace sigue activo].

### 3.5 Otros planos, solo enlazados

| Plano | Origen | Licencia | Enlace |
|---|---|---|---|
| *Croquis de la batalla de Tarapacá* (Bertrand) | *Boletín de la Guerra del Pacífico*, p. 520 | DP | https://commons.wikimedia.org/wiki/File:Croquis_de_la_batalla_de_tarapaca.png |
| *Croquis de la acción del Loa* | *Boletín de la Guerra del Pacífico*, p. 44 | DP | https://commons.wikimedia.org/wiki/File:Croquis_de_la_accion_del_loa.png |
| *Croquis de la batalla de San Juan y Chorrillos* | *El Ferrocarril*, Santiago, 2 feb. 1881 | DP | https://commons.wikimedia.org/wiki/File:Croquis_de_la_Batalla_de_Chorrillos.jpg |
| Planos de Diego Barros Arana, *Historia de la Guerra del Pacífico* (1880–1881): Pisagua, Dolores, Tarapacá, Los Ángeles, Tacna, Arica, Chorrillos y Miraflores, expedición Lynch | Chile | DP | https://commons.wikimedia.org/wiki/Category:Mapas_de_Historia_de_la_GdP,_Diego_Barros_Arana |
| Hugo Reck, *Mapa topográfico de la altiplanicie central de Bolivia* | *Boletín de la Guerra del Pacífico* | DP | https://commons.wikimedia.org/wiki/File:Mapa_topografico_de_la_altiplanicie_central_de_bolivia.png |
| Mapas del *Boletín de la Guerra del Pacífico* (categoría completa) | Chile | DP | https://commons.wikimedia.org/wiki/Category:Mapas_del_Bolet%C3%ADn_de_la_Guerra_del_Pac%C3%ADfico |
| *Chipana* (croquis del combate del 12 de abril de 1879) | *El Comercio* (Lima), 26 jul. 1879, en el folleto *Luz y Sombra* | DP | https://commons.wikimedia.org/wiki/File:Naval_battle_of_Chipana.jpg |

El croquis de Chipana es de **origen peruano** y no se descargó porque es un esquema muy simple; conviene tenerlo presente por equilibrio.

---

## 4. Cartografía nacional anterior a la guerra

Mapas oficiales del Perú y de Bolivia, hechos por sus propios gobiernos. Muestran cómo cada país se representaba a sí mismo antes de 1879 y nombran los lugares con la toponimia de entonces.

### 4.1 Paz Soldán, *Atlas geográfico del Perú* (París, 1865)

- **Autor [D]:** Mariano Felipe Paz Soldán (1821–1886), publicado «a expensas del Gobierno Peruano» siendo presidente Ramón Castilla. Grabado por F. Delamare, París; Librería de Augusto Durand, 1865.
- **Láminas descargadas:**
  - *Mapa general del Perú* [O]: litografía en tinta negra y sepia con relieve sombreado de gran calidad. Llega por el sur hasta el Loa. Enlace: https://commons.wikimedia.org/wiki/File:Mapa_general_del_Peru._Paz_Soldan._Geografia_del_Peru._Grabado_por_Delamare,_Calle_St._Andre_des_Arts,_45_(IA_dr_mapa-general-del-peru-paz-soldan-geografia-del-peru-grabado-por-delamare-00574087).jpg
  - *Tacna y Arica* (antiguo departamento de Moquegua): https://commons.wikimedia.org/wiki/File:Tacna_y_Arica_1865.JPG
- **Otras láminas útiles, solo enlazadas:** *Plano topográfico de la ciudad del Callao* (L. Mariani, 1855, corregido en 1862), https://commons.wikimedia.org/wiki/File:L-Mariani-and-M-Paz-Soldan-Callao-topografico.jpeg ; *Departamento de Moquegua*, https://commons.wikimedia.org/wiki/File:Departamento_moquegua_1865.JPG [P: no revisado]; mapa mineralógico y planos de Arequipa y otras ciudades en la misma serie de Commons.
- **Licencia [C]:** Commons las marca DP, pero los escaneos vienen de la David Rumsey Map Collection, que pide no usarlos comercialmente (NC).
- **Decisión de Feño** (comentario en T-034): las dos láminas se quedan en `docs/referencias/mapas/` **solo como referencia** y no se usan dentro del juego. Si el juego pasa a ser comercial, hay que revisar esta licencia (pedir permiso a Cartography Associates o buscar otra copia en la BNP, Gallica o Internet Archive).
- **Perspectiva:** peruana oficial. La frontera sur con Bolivia en el Loa es la que Perú sostenía; Perú reclamaba también una franja al sur del Loa (ver `geografia-1879.md` §2.3 y ADR-015).

### 4.2 Ondarza, Mujía y Camacho, *Mapa de la República de Bolivia* (1859)

- **Autores [D]:** Juan Ondarza, Juan Mariano Mujía y Lucio Camacho, «levantado y organizado en los años de 1842 a 1859», mandado publicar por el gobierno del presidente José María Linares. Impreso por J. H. Colton, Nueva York, 1859.
- **Contenido [O]:** departamentos **coloreados a mano** (verdes, rosados, amarillos y azules pálidos), el Litoral boliviano con Cobija, planos de ciudades en recuadros, un mapa de Sudamérica, y un marco decorativo con viñetas de paisajes y tipos humanos.
- **Interés:** la representación oficial boliviana de su litoral antes del tratado de 1866. Su marco ornamental es una referencia posible para **pantallas de título y menús**.
- **Licencia [D]:** DP. La copia descargada la donó a Commons el comerciante Geographicus. Hay otras dos copias en Commons que vienen de Gallica (BnF): https://commons.wikimedia.org/wiki/File:Mapa_de_la_republica_de_Bolivia..._levantado_y_organizado_en_los_a%C3%B1os_de_1842_a_1859_-_por..._Juan_Ondarza_;_..._Juan_Mariano_Mujia_;_y..._Lucio_Camacho_-_btv1b53064537q_(1_of_2).jpg
- **Enlace:** https://commons.wikimedia.org/wiki/File:Mapa_de_la_Rep%C3%BAblica_de_Bolivia,_1859.jpg
- **Ojo [I]:** es veinte años anterior a la guerra. La frontera sur del Litoral cambió con los tratados de 1866 y 1874 (ver `geografia-1879.md` §2.1). No sirve para las fronteras de 1879, sí para el estilo y la toponimia.

### 4.3 Raimondi, *Mapa del Perú* (1877), solo enlazado [P]

- Commons tiene una imagen pequeña (962 × 783 px) atribuida a Antonio Raimondi, tomada de un blog, sin ficha de la institución que conserva el original: https://commons.wikimedia.org/wiki/File:Mapa_del_Per%C3%BA_(1877).jpg
- No se descargó por la procedencia dudosa. La gran *Carta del Perú* de Raimondi se publicó por hojas desde 1887, después de la guerra [P].

---

## 5. Solo enlazados por su licencia (no comercial)

Mencionados en la descripción de la tarea. **No se descargaron** porque la David Rumsey Map Collection no permite el uso comercial de sus imágenes. La excepción son las dos láminas de Paz Soldán (§4.1), que vienen de Rumsey a través de Commons y se guardan **solo como referencia** por decisión de Feño.

| Mapa | Año | Enlace | Nota |
|---|---|---|---|
| A. Fullarton & Co., *West Coast of South America including Chili & part of Bolivia & Peru* (*Royal Illustrated Atlas*), con láminas de A. Petermann y J. Bartholomew | 1872 [C: otro catálogo da ~1860] | https://www.davidrumsey.com/maps3016.html | A color, con viñetas de tipos humanos y paisajes alrededor |
| James Wyld, *Republic of Peru and Bolivia* (escala 1:10 000 000) | 1864 | https://mediacommons.unl.edu/luna/servlet/detail/RUMSEY~8~1~232244~5509228:Republic-of-peru-and-Bolivia (registro Rumsey en un espejo) | [P] enlace directo en davidrumsey.com |
| Paz Soldán, *Atlas geográfico del Perú* (copia original de Rumsey) | 1865 | https://www.davidrumsey.com/maps2724.html (una de las páginas del atlas) [P: comprobar la lámina] | Las láminas de §4.1 son las mismas, vía Commons |

---

## 6. Pendientes

- [ ] **Biblioteca Nacional del Perú** (https://bibliotecadigital.bnp.gob.pe): no se encontraron mapas de la guerra con licencia clara en esta tarea. Buscar planos peruanos de 1879–1881 (Arica, Tacna, defensas del Callao y de Lima). También en el Instituto Riva-Agüero y el repositorio de la PUCP (que tiene el diario *La Patria* de 1880).
- [ ] **Repositorios bolivianos** (Biblioteca y Archivo Histórico de la Asamblea Legislativa Plurinacional, Archivo y Biblioteca Nacionales de Bolivia): cartografía boliviana de 1879.
- [ ] **Library of Congress** (https://www.loc.gov/maps/): el sitio respondió con error 403 a las consultas automáticas. Buscar a mano mapas de 1879–1884.
- [ ] Mapa plegable de Boyd, *Chili: sketches of Chili and the Chilians during the war 1879–1880* (Londres, 1881), en Memoria Chilena: https://www.memoriachilena.gob.cl/602/w3-article-341597.html
- [ ] Mapas de Mariano Felipe Paz Soldán, *Narración histórica de la guerra de Chile contra el Perú y Bolivia* (Buenos Aires, 1884), versión peruana de la guerra. Hay escaneos de Google en Internet Archive (`narracionhistri00soldgoog`, `narracionhistri01soldgoog`); no se comprobó si incluyen los planos desplegados.
- [ ] Copia de mayor resolución de *Prise d'Arica* (§3.3).
- [ ] Georreferenciar los mapas 2, 5, 6 y 7 con el mismo método que el de Turner (`geografia-1879.md` §1).
- [ ] Revisar los enlaces de la Biblioteca Nacional Digital de Chile, que cambió de dominio (`bibliotecanacionaldigital.cl` → `bibliotecanacionaldigital.gob.cl`).

---

## Fuentes

**Consultadas en esta tarea** (17 de octubre de 2026):

- Princeton University Library, Digital Maps: ficha del mapa de Turner. https://maps.princeton.edu/catalog/princeton-4f16c534z
- Memoria Chilena, Biblioteca Nacional de Chile: fichas de *Mapa detallado del teatro de la guerra* (MC0073663) y *Prise d'Arica* (MC0007391), con su declaración de «patrimonio cultural común». https://www.memoriachilena.gob.cl/602/w3-article-546940.html , https://www.memoriachilena.gob.cl/602/w3-article-68009.html
- Wikimedia Commons: fichas y metadatos (autor, fecha, fuente, licencia) de cada archivo citado, consultados con la API de Commons. Categorías *Maps of the War of the Pacific* y subcategorías: https://commons.wikimedia.org/wiki/Category:Maps_of_the_War_of_the_Pacific
- David Rumsey Map Collection, página de Fullarton (1872) con sus condiciones de uso. https://www.davidrumsey.com/maps3016.html
- Stanford Digital Repository, *Mapa general del Perú* (Paz Soldán), licencia CC BY-NC-SA 3.0 (vista en resultados de búsqueda). https://purl.stanford.edu/vp094gd1938
- Internet Archive, búsqueda de *Narración histórica* de Paz Soldán. https://archive.org
- [geografia-1879.md](geografia-1879.md) (T-009), [sitios-clave-escala.md](sitios-clave-escala.md) (T-040) y [recursos-1879.md](recursos-1879.md) (T-035).

**Para completar** (no consultadas):

- Esposito, Gabriele. *Armies of the War of the Pacific 1879–83: Chile, Peru & Bolivia*. Osprey, Men-at-Arms 504, 2016 (láminas de uniformes; ver `estilo-visual.md`).
- Bulnes, Gonzalo. *Guerra del Pacífico*. 3 vols. Valparaíso, 1911–1919 (planos de las batallas).
- Paz Soldán, Mariano Felipe. *Narración histórica de la guerra de Chile contra el Perú y Bolivia*. Buenos Aires, 1884.
- Querejazu Calvo, Roberto. *Guano, salitre, sangre*. La Paz, 1979.
