class_name ScreenProjector
extends RefCounted
## Proyección de posiciones del mundo a la pantalla, sin colisionadores ni GPU (ADR-006 punto 7,
## T-007). Guarda la matriz vista-proyección de una cámara y el tamaño del viewport, así se puede
## construir desde la Camera3D del juego (from_camera) o desde parámetros sintéticos en las pruebas
## (from_params). También da el punto del suelo (plano y = 0) bajo un punto de la pantalla: hasta
## que exista TerrainView (ADR-010 punto 1) el suelo es ese plano.
##
## Convenciones: pantalla en píxeles del viewport, origen arriba a la izquierda, y hacia abajo
## (igual que InputEventMouse.position). Las columnas de `m` siguen la clase Projection de Godot.

## Vista-proyección (proyección * inversa de la transformación de la cámara).
var m: Projection
## Inversa de `m` (para pasar de la pantalla al mundo).
var inv: Projection
## Tamaño del viewport en píxeles.
var size: Vector2 = Vector2(1, 1)
## Posición de la cámara en el mundo.
var origin: Vector3
## Píxeles por metro a 1 m de profundidad (para pasar radios del mundo a la pantalla).
var focal_px: float = 1.0


## Desde parámetros (pruebas): transformación global de la cámara, fov vertical en grados (como
## Camera3D con keep_aspect = KEEP_HEIGHT), planos cercano y lejano, y tamaño del viewport.
static func from_params(cam_xform: Transform3D, fov_deg: float, near: float, far: float, p_size: Vector2) -> ScreenProjector:
	var proj := Projection.create_perspective(fov_deg, p_size.x / maxf(p_size.y, 1.0), near, far)
	return from_matrices(proj, cam_xform, p_size)


## Desde la cámara del juego. Debe estar en el árbol (usa su viewport).
static func from_camera(cam: Camera3D) -> ScreenProjector:
	var vp_size: Vector2 = cam.get_viewport().get_visible_rect().size
	return from_matrices(cam.get_camera_projection(), cam.get_camera_transform(), vp_size)


static func from_matrices(proj: Projection, cam_xform: Transform3D, p_size: Vector2) -> ScreenProjector:
	var p := ScreenProjector.new()
	p.size = p_size
	p.origin = cam_xform.origin
	p.m = proj * Projection(cam_xform.affine_inverse())
	p.inv = p.m.inverse()
	p.focal_px = p_size.y * 0.5 * proj.y.y
	return p


## Proyecta un punto. Devuelve Vector3(x px, y px, profundidad w); w <= 0 = detrás de la cámara.
func project(p: Vector3) -> Vector3:
	var c: Vector4 = m * Vector4(p.x, p.y, p.z, 1.0)
	if c.w <= 0.0:
		return Vector3(0.0, 0.0, c.w)
	return Vector3((c.x / c.w * 0.5 + 0.5) * size.x, (0.5 - c.y / c.w * 0.5) * size.y, c.w)


## Dirección (normalizada) del rayo de la cámara que pasa por el punto de pantalla `screen`.
func ray_direction(screen: Vector2) -> Vector3:
	var nx: float = screen.x / size.x * 2.0 - 1.0
	var ny: float = 1.0 - screen.y / size.y * 2.0
	# Cualquier profundidad en NDC entre los planos cae sobre el mismo rayo.
	var v: Vector4 = inv * Vector4(nx, ny, 0.5, 1.0)
	var p := Vector3(v.x, v.y, v.z) / v.w
	return (p - origin).normalized()


## Punto del suelo (y = `height`) bajo el punto de pantalla, o null si el rayo no lo corta.
func ground_point(screen: Vector2, height: float = 0.0) -> Variant:
	return Plane(Vector3.UP, height).intersects_ray(origin, ray_direction(screen))
