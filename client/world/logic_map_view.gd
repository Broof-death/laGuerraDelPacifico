class_name LogicMapView
extends Node3D
## Terreno PROVISIONAL del cliente (T-013) dibujado desde el MISMO mapa lógico que usa el servidor
## (LogicMap, ADR-009): así la línea de costa que se ve es la de las rutas. Lo reemplazará el
## terreno visual de ADR-010 (Terrain3D o sectores propios, T-036/T-039), que saldrá del pipeline
## del mapa a partir de la misma fuente.
##
## - Un plano de agua grande en y = WATER_Y.
## - Una malla por sector jugable con tierra: plana si el sector es uniforme, con 128 x 128 quads
##   (32 m) si tiene datos. Un shader lee dos texturas con una texel por celda de 16 m (clase de
##   terreno y altura uint16) y descarta lo que es agua con interpolación bilineal de "es tierra"
##   entre centros de celda: el borde visible cae justo en el borde de las celdas lógicas.
##   Los vértices suben con la altura lógica solo en tierra (cerros, quebradas); la tierra
##   transitable es llana (y = 0), como suponen las vistas de las unidades.
## - Memoria: dos texturas de 1 y 2 B por celda de la zona jugable (con el mapa de prueba,
##   1536 x 2048 celdas: 3 + 6 MB). Para el mapa real (8192² celdas) no sirve: es provisional.

const WATER_Y: float = -0.3
const RELIEF_SUBDIVISIONS: int = 127

@export_file("*.tres") var map_path: String = MapDef.DEFAULT_PATH
@export var sand_color: Color = Color(0.64, 0.52, 0.36)
@export var beach_color: Color = Color(0.55, 0.45, 0.32)
@export var rock_color: Color = Color(0.36, 0.31, 0.27)
@export var ford_color: Color = Color(0.42, 0.42, 0.38)
@export var water_color: Color = Color(0.03, 0.14, 0.24)

var map: LogicMap
## Rectángulo de la zona dibujada (los sectores que no son OUT), en metros.
var drawn_rect: Rect2 = Rect2()
var _material: ShaderMaterial

const SHADER_CODE: String = """
shader_type spatial;
render_mode cull_back;

uniform sampler2D kind_tex : filter_nearest, repeat_disable;
uniform sampler2D height_tex : filter_nearest, repeat_disable;
uniform vec2 origin;
uniform vec2 tex_size;
uniform float cell = 16.0;
uniform vec3 sand_color;
uniform vec3 beach_color;
uniform vec3 rock_color;
uniform vec3 ford_color;

varying vec2 world_xz;

int kind_at(ivec2 c) {
	c = clamp(c, ivec2(0), ivec2(tex_size) - ivec2(1));
	return int(texelFetch(kind_tex, c, 0).r * 255.0 + 0.5) & 15;
}

bool is_land(int k) {
	return k >= 2 && k <= 6;
}

float height_at(ivec2 c) {
	c = clamp(c, ivec2(0), ivec2(tex_size) - ivec2(1));
	if (!is_land(kind_at(c))) {
		return 0.0;
	}
	vec2 rg = texelFetch(height_tex, c, 0).rg * 255.0;
	return (floor(rg.r + 0.5) + floor(rg.g + 0.5) * 256.0) * 0.01 - 60.0;
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	ivec2 c = ivec2(floor((wp.xz - origin) / cell));
	float h = height_at(c);
	float hl = height_at(c - ivec2(1, 0));
	float hr = height_at(c + ivec2(1, 0));
	float hd = height_at(c - ivec2(0, 1));
	float hu = height_at(c + ivec2(0, 1));
	VERTEX.y += h;
	NORMAL = normalize(vec3(hl - hr, 2.0 * cell, hd - hu));
	world_xz = wp.xz;
}

void fragment() {
	vec2 cf = (world_xz - origin) / cell - vec2(0.5);
	ivec2 c0 = ivec2(floor(cf));
	vec2 f = fract(cf);
	float l00 = is_land(kind_at(c0)) ? 1.0 : 0.0;
	float l10 = is_land(kind_at(c0 + ivec2(1, 0))) ? 1.0 : 0.0;
	float l01 = is_land(kind_at(c0 + ivec2(0, 1))) ? 1.0 : 0.0;
	float l11 = is_land(kind_at(c0 + ivec2(1, 1))) ? 1.0 : 0.0;
	float land = mix(mix(l00, l10, f.x), mix(l01, l11, f.x), f.y);
	if (land < 0.5) {
		discard;
	}
	// Color: mezcla bilineal de playa, roca y vado (bordes suaves, como la costa).
	int k00 = kind_at(c0);
	int k10 = kind_at(c0 + ivec2(1, 0));
	int k01 = kind_at(c0 + ivec2(0, 1));
	int k11 = kind_at(c0 + ivec2(1, 1));
	float rock = mix(mix(float(k00 == 6), float(k10 == 6), f.x), mix(float(k01 == 6), float(k11 == 6), f.x), f.y);
	float beach = mix(mix(float(k00 == 2), float(k10 == 2), f.x), mix(float(k01 == 2), float(k11 == 2), f.x), f.y);
	float ford = mix(mix(float(k00 == 4), float(k10 == 4), f.x), mix(float(k01 == 4), float(k11 == 4), f.x), f.y);
	vec3 col = mix(sand_color, beach_color, smoothstep(0.35, 0.65, beach));
	col = mix(col, ford_color, smoothstep(0.35, 0.65, ford));
	col = mix(col, rock_color, smoothstep(0.35, 0.65, rock));
	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.1;
}
"""


func _ready() -> void:
	map = LogicMap.load_shared(map_path)
	if map == null:
		push_error("LogicMapView: no se pudo cargar el mapa %s" % map_path)
		return
	_build()


## Rectángulo que conviene para los límites de la cámara.
func playable_rect() -> Rect2:
	return drawn_rect


func _build() -> void:
	var sr: Rect2i = map.active_sector_rect()
	if not sr.has_area():
		return
	var cells := MapGrid.SECTOR_CELLS
	var w: int = sr.size.x * cells
	var h: int = sr.size.y * cells
	var origin := Vector2(sr.position) * MapGrid.SECTOR - Vector2(MapGrid.MAP_HALF, MapGrid.MAP_HALF)
	drawn_rect = Rect2(origin, Vector2(sr.size) * MapGrid.SECTOR)
	var kind_img := Image.create_empty(w, h, false, Image.FORMAT_R8)
	var height_img := Image.create_empty(w, h, false, Image.FORMAT_RG8)
	var has_land: Array[bool] = []
	var relief: Array[bool] = []
	for sz: int in range(sr.position.y, sr.end.y):
		for sx: int in range(sr.position.x, sr.end.x):
			var idx: int = sz * MapGrid.SECTORS_PER_SIDE + sx
			var dst := Vector2i((sx - sr.position.x) * cells, (sz - sr.position.y) * cells)
			if map.sector_loaded(idx):
				kind_img.blit_rect(Image.create_from_data(cells, cells, false, Image.FORMAT_R8, map.sector_cells(idx)), Rect2i(0, 0, cells, cells), dst)
				height_img.blit_rect(Image.create_from_data(cells, cells, false, Image.FORMAT_RG8, map.sector_heights(idx)), Rect2i(0, 0, cells, cells), dst)
				has_land.append(true)
				relief.append(true)
			else:
				var k: int = map.uniform_kind(idx)
				var q: int = Terrain.encode_height(map.uniform_height(idx))
				kind_img.fill_rect(Rect2i(dst, Vector2i(cells, cells)), Color8(k, 0, 0))
				height_img.fill_rect(Rect2i(dst, Vector2i(cells, cells)), Color8(q & 255, q >> 8, 0))
				var kk: int = k & Terrain.KIND_MASK
				has_land.append(kk >= Terrain.Kind.BEACH and kk <= Terrain.Kind.IMPASSABLE)
				relief.append(false)
	_material = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = SHADER_CODE
	_material.shader = shader
	_material.set_shader_parameter("kind_tex", ImageTexture.create_from_image(kind_img))
	_material.set_shader_parameter("height_tex", ImageTexture.create_from_image(height_img))
	_material.set_shader_parameter("origin", origin)
	_material.set_shader_parameter("tex_size", Vector2(w, h))
	_material.set_shader_parameter("cell", MapGrid.TERRAIN_CELL)
	_material.set_shader_parameter("sand_color", Vector3(sand_color.r, sand_color.g, sand_color.b))
	_material.set_shader_parameter("beach_color", Vector3(beach_color.r, beach_color.g, beach_color.b))
	_material.set_shader_parameter("rock_color", Vector3(rock_color.r, rock_color.g, rock_color.b))
	_material.set_shader_parameter("ford_color", Vector3(ford_color.r, ford_color.g, ford_color.b))

	var flat := PlaneMesh.new()
	flat.size = Vector2(MapGrid.SECTOR, MapGrid.SECTOR)
	var bumpy := PlaneMesh.new()
	bumpy.size = Vector2(MapGrid.SECTOR, MapGrid.SECTOR)
	bumpy.subdivide_width = RELIEF_SUBDIVISIONS
	bumpy.subdivide_depth = RELIEF_SUBDIVISIONS
	var i: int = 0
	for sz: int in range(sr.position.y, sr.end.y):
		for sx: int in range(sr.position.x, sr.end.x):
			if has_land[i]:
				var mi := MeshInstance3D.new()
				mi.name = "Sector_%d_%d" % [sx, sz]
				mi.mesh = bumpy if relief[i] else flat
				mi.material_override = _material
				mi.extra_cull_margin = 200.0
				mi.position = MapGrid.to_render((sx + 0.5) * MapGrid.SECTOR - MapGrid.MAP_HALF, (sz + 0.5) * MapGrid.SECTOR - MapGrid.MAP_HALF)
				add_child(mi)
			i += 1

	var water_mat := StandardMaterial3D.new()
	water_mat.albedo_color = water_color
	water_mat.metallic_specular = 0.7
	water_mat.roughness = 0.3
	var water_mesh := PlaneMesh.new()
	water_mesh.size = drawn_rect.size + Vector2(40000.0, 40000.0)
	water_mesh.material = water_mat
	var water := MeshInstance3D.new()
	water.name = "Mar"
	water.mesh = water_mesh
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.position = Vector3(drawn_rect.get_center().x, WATER_Y, drawn_rect.get_center().y)
	add_child(water)
