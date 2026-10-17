extends GdUnitTestSuite
## ENetTransport en 127.0.0.1 dentro del mismo proceso: conexión, canales y una partida mínima
## MatchServer <-> MatchClient por red real. (La prueba con dos procesos está en tests/net/.)


func _port() -> int:
	return 30000 + randi() % 20000


func _pump_until(cond: Callable, transports: Array, timeout_msec: int = 3000) -> bool:
	var end: int = Time.get_ticks_msec() + timeout_msec
	while Time.get_ticks_msec() < end:
		for t: Variant in transports:
			if t is Transport:
				(t as Transport).poll()
			else:
				t.call()
		if cond.call():
			return true
		OS.delay_msec(2)
	return false


func test_connect_and_exchange_on_all_channels() -> void:
	var port := _port()
	var server := ENetTransport.create_server(port, 4)
	assert_object(server).is_not_null()
	var client := ENetTransport.create_client("127.0.0.1", port)
	var got_server: Array[PackedByteArray] = []
	var got_client: Array[PackedByteArray] = []
	var peers: Array[int] = []
	server.peer_connected.connect(func(id: int) -> void: peers.append(id))
	server.packet_received.connect(func(_id: int, d: PackedByteArray) -> void: got_server.append(d))
	client.packet_received.connect(func(_id: int, d: PackedByteArray) -> void: got_client.append(d))
	var connected := [false]
	client.peer_connected.connect(func(id: int) -> void: connected[0] = id == Transport.SERVER_PEER)
	assert_bool(_pump_until(func() -> bool: return connected[0] and peers.size() == 1, [server, client])).is_true()
	for ch: int in Transport.CHANNEL_COUNT:
		client.send(Transport.SERVER_PEER, ch, PackedByteArray([ch, 1, 2, 3]))
		server.send(peers[0], ch, PackedByteArray([ch, 9]))
	assert_bool(_pump_until(func() -> bool: return got_server.size() == 3 and got_client.size() == 3, [server, client])).is_true()
	client.close()
	server.close()


func test_match_over_enet() -> void:
	var port := _port()
	var sim := SimTestHelpers.make_sim()
	var ms := MatchServer.new(sim)
	ms.spawn_test_armies(2, 8, 60.0)
	ms.add_transport(ENetTransport.create_server(port, 4))
	var mc := MatchClient.new(ENetTransport.create_client("127.0.0.1", port), sim.game_data.catalog_hash())
	var step := func() -> void:
		ms.poll()
		ms.tick_once()
		mc.update(0.05)
	assert_bool(_pump_until(func() -> bool: return mc.state.count == 16, [step], 5000)).is_true()
	assert_int(mc.player_id).is_equal(1)
	assert_int(mc.receiver.latest_complete_tick).is_greater(0)
	mc.close()
	ms.close()
