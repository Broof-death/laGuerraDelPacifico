"""Genera modelos low-poly del monitor Huáscar y la corbeta Esmeralda como .glb para Godot.

Uso (desde la raíz del repo):
    python tools/modelos/generar_barcos.py            # escribe assets/models/barcos/*.glb
    python tools/modelos/generar_barcos.py --vista    # además guarda vistas previas .png en tools/modelos/vistas/

Solo necesita numpy (y Pillow para las vistas previas).

Convenciones (Godot): metros, Y hacia arriba, la proa mira hacia -Z y el origen está en la línea de
flotación, en el centro del barco. Los materiales llevan nombre para poder cambiarlos desde Godot; el de
la bandera se llama «bandera_*».

Las medidas son aproximadas y deben ajustarse con la ficha histórica de armadas (T-015):
  Huáscar:   eslora ~60 m, manga ~10,7 m, francobordo muy bajo (~1,4 m), una torre giratoria con dos
             cañones, una chimenea, dos palos.
  Esmeralda: eslora ~61 m, manga ~10 m, casco de madera con banda de troneras, una chimenea,
             tres palos aparejados y bauprés.
"""

from __future__ import annotations

import argparse
import json
import math
import struct
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

RAIZ = Path(__file__).resolve().parents[2]
SALIDA = RAIZ / "assets" / "models" / "barcos"
VISTAS = Path(__file__).resolve().parent / "vistas"

COLORES = {
    "casco_negro": (0.08, 0.08, 0.09),
    "obra_viva": (0.45, 0.12, 0.10),  # casco bajo la línea de flotación
    "cubierta": (0.55, 0.42, 0.28),
    "franja_blanca": (0.85, 0.84, 0.80),
    "tronera": (0.03, 0.03, 0.03),
    "metal_oscuro": (0.18, 0.19, 0.21),
    "chimenea": (0.12, 0.12, 0.12),
    "madera_palo": (0.42, 0.30, 0.18),
    "bandera_rojo": (0.80, 0.08, 0.10),
    "bandera_blanco": (0.95, 0.95, 0.95),
    "bandera_azul": (0.05, 0.20, 0.60),
}


@dataclass
class Malla:
    """Triángulos agrupados por material, con normales planas (estilo low-poly)."""

    tris: dict[str, list[tuple[np.ndarray, np.ndarray, np.ndarray]]] = field(default_factory=dict)

    def tri(self, mat: str, a, b, c) -> None:
        a, b, c = (np.asarray(p, dtype=float) for p in (a, b, c))
        if np.linalg.norm(np.cross(b - a, c - a)) < 1e-9:
            return  # triángulo degenerado
        self.tris.setdefault(mat, []).append((a, b, c))

    def quad(self, mat: str, a, b, c, d) -> None:
        self.tri(mat, a, b, c)
        self.tri(mat, a, c, d)

    def caja(self, mat: str, centro, tam, rot_y: float = 0.0) -> None:
        cx, cy, cz = centro
        hx, hy, hz = (t / 2 for t in tam)
        cos, sin = math.cos(rot_y), math.sin(rot_y)

        def p(x, y, z):
            return (cx + x * cos + z * sin, cy + y, cz - x * sin + z * cos)

        v = [p(x, y, z) for x in (-hx, hx) for y in (-hy, hy) for z in (-hz, hz)]
        # índices: x*4 + y*2 + z  (0 = negativo, 1 = positivo)
        for q in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
            self.quad(mat, *(v[i] for i in q))

    def cilindro(self, mat: str, base, eje, radio: float, largo: float, lados: int = 10, tapa_mat: str | None = None) -> None:
        """Cilindro desde `base` a lo largo del vector unitario `eje`."""
        base = np.asarray(base, dtype=float)
        eje = np.asarray(eje, dtype=float) / np.linalg.norm(eje)
        ref = np.array([1.0, 0, 0]) if abs(eje[0]) < 0.9 else np.array([0, 0, 1.0])
        u = np.cross(eje, ref)
        u /= np.linalg.norm(u)
        w = np.cross(eje, u)
        anillo = [radio * (math.cos(t) * u + math.sin(t) * w) for t in np.linspace(0, 2 * math.pi, lados, endpoint=False)]
        tope = base + eje * largo
        for i in range(lados):
            a, b = anillo[i], anillo[(i + 1) % lados]
            self.quad(mat, base + a, base + b, tope + b, tope + a)
            self.tri(tapa_mat or mat, tope, tope + a, tope + b)
            self.tri(tapa_mat or mat, base, base + b, base + a)


def casco(m: Malla, eslora: float, manga: float, francobordo: float, calado: float, finura_proa: float,
          popa_ancho: float, franja: tuple[float, float] | None = None, estaciones: int = 28) -> None:
    """Casco por secciones transversales. La proa está en z = -eslora/2."""

    def semimanga(s: float) -> float:
        if s < finura_proa:
            t = s / finura_proa
            return 1 - (1 - t) ** 2.2
        if s > 0.82:
            t = (1 - s) / 0.18
            return popa_ancho + (1 - popa_ancho) * (1 - (1 - t) ** 2)
        return 1.0

    def seccion(s: float) -> list[tuple[str, np.ndarray]]:
        z = -eslora / 2 + s * eslora
        b = manga / 2 * semimanga(s)
        h = francobordo * (1 + 0.35 * (1 - s) ** 3)  # arrufo: la proa un poco más alta
        perfil = [(b * 0.97, h)]  # borde de cubierta (leve caída de costado)
        if franja:
            perfil += [(b * 0.985, h * franja[0]), (b * 0.995, h * franja[1])]
        perfil += [(b, 0.0), (b * 0.55, -calado * 0.85), (0.0, -calado)]
        derecha = [np.array([x, y, z]) for x, y in perfil]
        izquierda = [np.array([-x, y, z]) for x, y in reversed(perfil[:-1])]
        return derecha + izquierda

    # material de cada tramo del costado, de la cubierta hacia la quilla (lado derecho)
    tramos = ["casco_negro"] + (["franja_blanca", "casco_negro"] if franja else []) + ["obra_viva", "obra_viva"]
    mats = tramos + list(reversed(tramos))

    anillos = [seccion(s) for s in np.linspace(0.0, 1.0, estaciones)]
    for a, b in zip(anillos, anillos[1:]):
        for i, mat in enumerate(mats):
            m.quad(mat, a[i], b[i], b[i + 1], a[i + 1])
        m.quad("cubierta", a[-1], b[-1], b[0], a[0])
    # espejo de popa
    popa = anillos[-1]
    centro = sum(popa) / len(popa)
    for i in range(len(popa)):
        m.tri("casco_negro", centro, popa[i], popa[(i + 1) % len(popa)])


def cubierta_en(eslora: float, francobordo: float, s: float) -> float:
    return francobordo * (1 + 0.35 * (1 - s) ** 3)


def z_de(eslora: float, s: float) -> float:
    return -eslora / 2 + s * eslora


def palo(m: Malla, z: float, base_y: float, alto: float, vergas: list[tuple[float, float]], radio: float = 0.28) -> None:
    m.cilindro("madera_palo", (0, base_y, z), (0, 1, 0), radio, alto, lados=6)
    for frac, largo in vergas:
        m.cilindro("madera_palo", (-largo / 2, base_y + alto * frac, z), (1, 0, 0), radio * 0.6, largo, lados=5)


def bandera_peru(m: Malla, pos, ancho: float = 3.0, alto: float = 2.0) -> None:
    x, y, z = pos
    for i, color in enumerate(("bandera_rojo", "bandera_blanco", "bandera_rojo")):
        m.caja(color, (x, y, z + (i - 1) * ancho / 3), (0.05, alto, ancho / 3))


def bandera_chile(m: Malla, pos, ancho: float = 3.0, alto: float = 2.0) -> None:
    x, y, z = pos
    m.caja("bandera_rojo", (x, y - alto / 4, z), (0.05, alto / 2, ancho))
    m.caja("bandera_blanco", (x, y + alto / 4, z + ancho / 6), (0.05, alto / 2, ancho * 2 / 3))
    m.caja("bandera_azul", (x, y + alto / 4, z - ancho / 3), (0.06, alto / 2, ancho / 3))


def huascar() -> Malla:
    m = Malla()
    L, B, F, D = 60.0, 10.7, 1.4, 4.6
    casco(m, L, B, F, D, finura_proa=0.28, popa_ancho=0.6)
    # torre giratoria con dos cañones apuntando a proa
    zt = z_de(L, 0.34)
    yt = cubierta_en(L, F, 0.34)
    m.cilindro("metal_oscuro", (0, yt, zt), (0, 1, 0), 3.3, 2.6, lados=14)
    for x in (-0.9, 0.9):
        m.cilindro("metal_oscuro", (x, yt + 1.3, zt - 3.0), (0, 0, -1), 0.32, 4.2, lados=8)
    # torre de mando, chimenea y puente
    zm = z_de(L, 0.47)
    m.cilindro("metal_oscuro", (0, cubierta_en(L, F, 0.47), zm), (0, 1, 0), 1.1, 2.8, lados=8)
    zc = z_de(L, 0.56)
    m.cilindro("chimenea", (0, cubierta_en(L, F, 0.56), zc), (0, 1, 0), 1.15, 7.5, lados=10)
    m.caja("cubierta", (0, cubierta_en(L, F, 0.52) + 3.4, z_de(L, 0.52)), (7.0, 0.3, 3.0))
    # dos palos con vergas de bergantín
    palo(m, z_de(L, 0.16), cubierta_en(L, F, 0.16), 19.0, [(0.55, 11.0), (0.8, 8.0)])
    palo(m, z_de(L, 0.70), cubierta_en(L, F, 0.70), 17.0, [(0.6, 9.0)])
    # bandera del Perú en el pico de popa
    bandera_peru(m, (0, cubierta_en(L, F, 0.95) + 6.0, z_de(L, 0.97)))
    m.cilindro("madera_palo", (0, cubierta_en(L, F, 0.97), z_de(L, 0.97) - 1.6), (0, 1, 0), 0.12, 7.0, lados=5)
    return m


def esmeralda() -> Malla:
    m = Malla()
    L, B, F, D = 61.0, 10.0, 3.6, 4.0
    casco(m, L, B, F, D, finura_proa=0.22, popa_ancho=0.5, franja=(0.82, 0.55))
    # troneras sobre la franja blanca, en ambas bandas
    for s in np.linspace(0.22, 0.80, 10):
        z = z_de(L, s)
        y = cubierta_en(L, F, s) * 0.685
        for lado in (-1, 1):
            m.caja("tronera", (lado * (B / 2 + 0.02), y, z), (0.08, 0.8, 0.9))
    # chimenea entre trinquete y mayor
    m.cilindro("chimenea", (0, cubierta_en(L, F, 0.38), z_de(L, 0.38)), (0, 1, 0), 0.9, 6.5, lados=10)
    # tres palos aparejados en cruz y bauprés
    palo(m, z_de(L, 0.20), cubierta_en(L, F, 0.20), 30.0, [(0.40, 15.0), (0.62, 12.0), (0.82, 8.5)])
    palo(m, z_de(L, 0.50), cubierta_en(L, F, 0.50), 32.0, [(0.40, 16.0), (0.62, 13.0), (0.82, 9.0)])
    palo(m, z_de(L, 0.78), cubierta_en(L, F, 0.78), 25.0, [(0.45, 11.0), (0.70, 8.0)])
    proa = np.array([0, cubierta_en(L, F, 0.0), z_de(L, 0.0) + 0.5])
    m.cilindro("madera_palo", proa, (0, 0.35, -1), 0.25, 13.0, lados=6)
    # bandera de Chile en el pico de popa
    bandera_chile(m, (0, cubierta_en(L, F, 0.95) + 8.0, z_de(L, 0.97)))
    m.cilindro("madera_palo", (0, cubierta_en(L, F, 0.97), z_de(L, 0.97) - 1.6), (0, 1, 0), 0.12, 9.0, lados=5)
    return m


# ---------------------------------------------------------------- exportación glTF binario (.glb)

def escribir_glb(m: Malla, nombre: str, ruta: Path) -> None:
    binario = bytearray()
    accessors, views, primitivas, materiales = [], [], [], []

    def agregar(datos: bytes, target: int) -> int:
        while len(binario) % 4:
            binario.append(0)
        views.append({"buffer": 0, "byteOffset": len(binario), "byteLength": len(datos), "target": target})
        binario.extend(datos)
        return len(views) - 1

    for mat, tris in sorted(m.tris.items()):
        pos = np.array([p for t in tris for p in t], dtype=np.float32)
        normales = []
        for a, b, c in tris:
            n = np.cross(b - a, c - a)
            normales += [n / np.linalg.norm(n)] * 3
        nor = np.array(normales, dtype=np.float32)
        idx = np.arange(len(pos), dtype=np.uint32)

        vp = agregar(pos.tobytes(), 34962)
        accessors.append({"bufferView": vp, "componentType": 5126, "count": len(pos), "type": "VEC3",
                          "min": pos.min(axis=0).tolist(), "max": pos.max(axis=0).tolist()})
        vn = agregar(nor.tobytes(), 34962)
        accessors.append({"bufferView": vn, "componentType": 5126, "count": len(nor), "type": "VEC3"})
        vi = agregar(idx.tobytes(), 34963)
        accessors.append({"bufferView": vi, "componentType": 5125, "count": len(idx), "type": "SCALAR"})

        r, g, b = COLORES[mat]
        materiales.append({"name": mat, "pbrMetallicRoughness": {"baseColorFactor": [r, g, b, 1.0],
                                                                 "metallicFactor": 0.0, "roughnessFactor": 0.85}})
        primitivas.append({"attributes": {"POSITION": len(accessors) - 3, "NORMAL": len(accessors) - 2},
                           "indices": len(accessors) - 1, "material": len(materiales) - 1})

    while len(binario) % 4:
        binario.append(0)
    gltf = {
        "asset": {"version": "2.0", "generator": "La Guerra del Pacífico - tools/modelos/generar_barcos.py"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"name": nombre, "mesh": 0}],
        "meshes": [{"name": nombre, "primitives": primitivas}],
        "materials": materiales,
        "accessors": accessors,
        "bufferViews": views,
        "buffers": [{"byteLength": len(binario)}],
    }
    texto = json.dumps(gltf, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    texto += b" " * ((4 - len(texto) % 4) % 4)
    total = 12 + 8 + len(texto) + 8 + len(binario)
    with open(ruta, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(texto), 0x4E4F534A) + texto)
        f.write(struct.pack("<II", len(binario), 0x004E4942) + bytes(binario))


# ---------------------------------------------------------------- vista previa (rasterizador simple)

def vista_previa(modelos: list[tuple[str, Malla]], ruta: Path, guiñada: float, cabeceo: float, ancho: int = 1400, alto: int = 700) -> None:
    from PIL import Image, ImageDraw

    luz = np.array([-0.4, 0.8, -0.45])
    luz /= np.linalg.norm(luz)
    cy, sy = math.cos(guiñada), math.sin(guiñada)
    cp, sp = math.cos(cabeceo), math.sin(cabeceo)

    def camara(p):
        x, y, z = p
        x, z = x * cy - z * sy, x * sy + z * cy  # giro en Y
        y, z = y * cp - z * sp, y * sp + z * cp  # inclinación
        return np.array([x, y, z])

    caras = []
    separacion = 75.0
    for i, (_, m) in enumerate(modelos):
        desplazamiento = np.array([(i - (len(modelos) - 1) / 2) * separacion, 0, 0])
        for mat, tris in m.tris.items():
            for t in tris:
                if max(p[1] for p in t) < 0.05:
                    continue  # bajo la línea de flotación
                mundo = [p + desplazamiento for p in t]
                n = np.cross(mundo[1] - mundo[0], mundo[2] - mundo[0])
                n /= np.linalg.norm(n)
                brillo = 0.35 + 0.65 * max(0.0, float(n @ luz))
                cam = [camara(p) for p in mundo]
                caras.append((sum(c[2] for c in cam) / 3, cam, mat, brillo))

    todos = np.array([c for _, cam, _, _ in caras for c in cam])
    mn, mx = todos.min(axis=0), todos.max(axis=0)
    escala = min((ancho - 80) / (mx[0] - mn[0]), (alto - 120) / (mx[1] - mn[1]))
    img = Image.new("RGB", (ancho, alto), (70, 120, 160))
    d = ImageDraw.Draw(img)

    def pantalla(c):
        return (40 + (c[0] - mn[0]) * escala, alto - 60 - (c[1] - mn[1]) * escala)

    for _, cam, mat, brillo in sorted(caras, key=lambda c: -c[0]):
        r, g, b = COLORES[mat]
        color = tuple(int(255 * min(1.0, v * brillo)) for v in (r, g, b))
        d.polygon([pantalla(c) for c in cam], fill=color)
    # barra de escala de 10 m y nombres
    d.rectangle([40, alto - 30, 40 + 10 * escala, alto - 24], fill="white")
    d.text((45 + 10 * escala, alto - 34), "10 m", fill="white")
    for i, (nombre, _) in enumerate(modelos):
        x = ancho / 2 + (i - (len(modelos) - 1) / 2) * separacion * escala * cy
        d.text((x - 30, 15), nombre, fill="white")
    img.save(ruta)


def main() -> None:
    import sys

    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--vista", action="store_true", help="guardar vistas previas en tools/modelos/vistas/")
    args = parser.parse_args()

    barcos = [("huascar", huascar()), ("esmeralda", esmeralda())]
    SALIDA.mkdir(parents=True, exist_ok=True)
    for nombre, malla in barcos:
        ruta = SALIDA / f"{nombre}.glb"
        escribir_glb(malla, nombre, ruta)
        n = sum(len(t) for t in malla.tris.values())
        print(f"{ruta.relative_to(RAIZ)}: {n} triángulos, {ruta.stat().st_size // 1024} KB")

    if args.vista:
        VISTAS.mkdir(exist_ok=True)
        vista_previa(barcos, VISTAS / "rts.png", guiñada=math.radians(35), cabeceo=math.radians(-38))
        for nombre, malla in barcos:
            vista_previa([(nombre, malla)], VISTAS / f"perfil_{nombre}.png", guiñada=math.radians(90), cabeceo=0.0, alto=420)
        print(f"Vistas previas en {VISTAS.relative_to(RAIZ)}")


if __name__ == "__main__":
    main()
