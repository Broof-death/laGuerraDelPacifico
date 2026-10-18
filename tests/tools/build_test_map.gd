extends SceneTree
## Regenera el mapa provisional de prueba (T-013) en data/map/ (MapDef, sectores y grafos HPA*).
##   godot --headless --path . -s res://tests/tools/build_test_map.gd
## Cuando exista el pipeline del mapa real (T-011), sus datos reemplazan a estos.


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var m := TestMapBuilder.build(true)
	var t1 := Time.get_ticks_msec()
	var err := TestMapBuilder.save(m)
	var mem := m.memory_bytes()
	print("BUILD_TEST_MAP generar %d ms (grafos: %d ms la última capa), guardar %d ms, error %d" % [t1 - t0, PathGraphBuilder.last_build_msec, Time.get_ticks_msec() - t1, err])
	print("BUILD_TEST_MAP sectores con datos %d, rejilla %.2f MB, grafos %.2f MB, nodos tierra %d, nodos mar %d" % [
		mem["sectors_loaded"], mem["grid"] / 1048576.0, mem["graphs"] / 1048576.0,
		m.graph(Terrain.Layer.LAND).node_count(), m.graph(Terrain.Layer.SEA).node_count()])
	quit(0 if err == OK else 1)
