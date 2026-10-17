extends Node3D
## Escena de prueba de la cámara RTS (T-006).
##
## Para capturas automáticas se puede fijar la vista inicial con argumentos de
## usuario (después de "--"), por ejemplo:
##   godot --path . res://tests/sandbox/camera_sandbox.tscn --write-movie x.png
##         --quit-after 30 --fixed-fps 10 -- --zoom=0.1 --yaw=40 --focus=60,0
## zoom en [0, 1], yaw en grados, focus en metros (x,z).

@onready var _camera: RtsCamera = $RtsCamera


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		if parts.size() != 2:
			continue
		match parts[0]:
			"zoom":
				_camera.set_zoom(float(parts[1]), true)
			"yaw":
				_camera.set_yaw(deg_to_rad(float(parts[1])), true)
			"focus":
				var xz := parts[1].split_floats(",")
				if xz.size() == 2:
					_camera.focus_on(Vector3(xz[0], 0.0, xz[1]), true)
