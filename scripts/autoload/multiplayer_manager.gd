extends Node
## Autoload "MultiplayerManager".
##
## Hosting, joining, the player list ("roster") and loading the mission on
## every machine at once. Uses Godot's built-in ENet networking.
##
## Network model:
##  * The HOST is authoritative for the mission: stage, horde position, gate
##    progress, success/failure (see MissionManager).
##  * Each player is authoritative only for their OWN cyclist, driven by their
##    own cycling input, and broadcasts its position/speed/effort.
##  * Solo play uses Godot's OfflineMultiplayerPeer, where this machine is the
##    "host", so exactly the same code runs in single-player.

signal roster_changed
signal connected_to_host
signal connection_failed(reason: String)
signal player_left(peer_id: int)

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 6
## Game modes and their scenes.
const MODE_STORY := "story"
const MODE_ENDLESS := "endless"
## The criterium points race (solo against computer riders).
const MODE_RACE := "race"
const MISSION_SCENES := {
	MODE_STORY: "res://scenes/mission/escape_the_town.tscn",
	MODE_ENDLESS: "res://scenes/mission/endless_survival.tscn",
	MODE_RACE: "res://scenes/race/criterium.tscn",
}
const MENU_SCENE := "res://scenes/ui/main_menu.tscn"

## peer_id -> { "name": String }
var players: Dictionary = {}
var is_online: bool = false
## Shown by the main menu after returning from a dropped session.
var last_message: String = ""
## The mode and world seed of the current/last mission (same on every machine).
var mission_mode: String = MODE_STORY
var mission_seed: int = 1


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _exit_tree() -> void:
	# Free shared caches at shutdown so Godot doesn't report leaks.
	MeshKit.clear_cache()
	SoundBank.clear_cache()


func is_host() -> bool:
	return multiplayer.is_server()


## Sorted list of peer ids. Index in this list = lane and jersey colour.
func get_roster() -> Array:
	var ids := players.keys()
	ids.sort()
	return ids


func get_player_name(peer_id: int) -> String:
	return str(players.get(peer_id, {}).get("name", "Rider %d" % peer_id))


func start_solo(mode: String = MODE_STORY) -> void:
	leave()
	players = {1: {"name": CyclingInputManager.rider_name}}
	start_mission(mode)


func host_game(port: int = DEFAULT_PORT) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_online = true
	players = {1: {"name": CyclingInputManager.rider_name}}
	roster_changed.emit()
	print("[Net] Hosting on port %d" % port)
	return OK


func join_game(address: String, port: int = DEFAULT_PORT) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_online = true
	print("[Net] Connecting to %s:%d" % [address, port])
	return OK


func leave() -> void:
	if multiplayer.multiplayer_peer and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	is_online = false
	players.clear()


## Host only: load the mission on every machine (also used for "Replay").
## Each run gets a new world seed; every machine builds the same world from it.
func start_mission(mode: String = MODE_STORY) -> void:
	if not is_host():
		return
	if is_online:
		multiplayer.multiplayer_peer.refuse_new_connections = true
	var seed_value := randi() % 1000000 + 1
	if DevTools.options.has("seed"):
		seed_value = int(DevTools.options["seed"])
	_net_load_mission.rpc(players, mode, seed_value)


## Leave the session and go back to the title screen.
func return_to_menu(message: String = "") -> void:
	leave()
	last_message = message
	get_tree().change_scene_to_file(MENU_SCENE)


@rpc("authority", "call_local", "reliable")
func _net_load_mission(roster: Dictionary, mode: String, seed_value: int) -> void:
	players = roster
	mission_mode = mode if MISSION_SCENES.has(mode) else MODE_STORY
	mission_seed = seed_value
	get_tree().change_scene_to_file(MISSION_SCENES[mission_mode])


## Client -> host: introduce ourselves after connecting.
@rpc("any_peer", "call_remote", "reliable")
func _net_register(player_name: String) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	players[id] = {"name": player_name.substr(0, 16)}
	print("[Net] Player %d joined as '%s'" % [id, player_name])
	_net_roster.rpc(players)
	roster_changed.emit()


## Host -> everyone: the current player list.
@rpc("authority", "call_remote", "reliable")
func _net_roster(roster: Dictionary) -> void:
	players = roster
	roster_changed.emit()


func _on_peer_connected(id: int) -> void:
	print("[Net] Peer connected: %d" % id)


func _on_peer_disconnected(id: int) -> void:
	print("[Net] Peer disconnected: %d" % id)
	if players.has(id):
		players.erase(id)
		if is_host():
			_net_roster.rpc(players)
		roster_changed.emit()
		player_left.emit(id)


func _on_connected_to_server() -> void:
	print("[Net] Connected to host as peer %d" % multiplayer.get_unique_id())
	_net_register.rpc_id(1, CyclingInputManager.rider_name)
	connected_to_host.emit()


func _on_connection_failed() -> void:
	leave()
	connection_failed.emit("Could not connect to host.")


func _on_server_disconnected() -> void:
	print("[Net] Host disconnected")
	return_to_menu("The host left the game.")
