extends Node
## Autoload "DevTools" - development and automated-testing helpers driven by
## command-line options. Has no effect during normal play.
##
## Pass options after "--" on the Godot command line, e.g.
##   godot --path . -- --solo
##   godot --path . -- --host --auto-start=2       (start when 2 players are in)
##   godot --path . -- --join=127.0.0.1 --name=Bob
##
## Options:
##   --solo                 skip the menu and start a solo mission
##   --host                 host a game; --auto-start=N starts at N players
##   --join=IP              join a game at IP
##   --port=N               network port (default 7777)
##   --name=NAME            rider name      --ftp=W   rider FTP
##   --input=trainer        use the smart-trainer bridge input (keyboard = default)
##   --autopilot=W          replace keyboard input with a constant W watts
##   --autopilot-profile=T:W,T:W,...   watts changing at times T (seconds)
##   --autopilot-react=W    with --autopilot: ride at W watts while the horde
##                          surges or grabs (simulates a player who sprints)
##   --log-horde            print the horde gap every 2 s (balance tuning)
##   --timescale=F          speed the game up (testing)
##   --screenshot=PATH      save screenshots; with --screenshot-at=S1,S2,...
##                          (seconds since the mission started). PATH may
##                          contain %d for the index.
##   --exit-on-results      quit after the results screen; exit code 0 =
##                          success, 2 = failure
##   --replays=N            (with --exit-on-results) the host presses Replay
##                          N times before quitting - tests mission restart
##   --quit-after=S         quit after S seconds no matter what (safety net)

var options: Dictionary = {}

var _mission_time: float = 0.0
var _mission_ref: WeakRef
var _shots: Array = []
var _shot_index: int = 0
var _exit_pending := false
var _auto_start_players: int = 0
var _real_time: float = 0.0
var _results_seen: int = 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var kv := arg.substr(2).split("=", true, 1)
			options[kv[0]] = kv[1] if kv.size() > 1 else "true"
	if options.is_empty():
		return
	print("[DevTools] options: %s" % options)
	process_mode = Node.PROCESS_MODE_ALWAYS
	if options.has("name"):
		CyclingInputManager.rider_name = options["name"]
	if options.has("ftp"):
		CyclingInputManager.rider_ftp_watts = float(options["ftp"])
	if options.get("input", "") == "trainer":
		CyclingInputManager.set_input_mode(CyclingInputManager.InputMode.TRAINER)
	if options.has("autopilot") or options.has("autopilot-profile"):
		var src := ScriptedCyclingInput.new()
		src.constant_watts = float(options.get("autopilot", "200"))
		if options.has("autopilot-profile"):
			for pair in String(options["autopilot-profile"]).split(","):
				var tw := pair.split(":")
				src.profile.append([float(tw[0]), float(tw[1])])
		CyclingInputManager.set_source(src)
	if options.has("timescale"):
		Engine.time_scale = float(options["timescale"])
	if options.has("screenshot-at"):
		for s in String(options["screenshot-at"]).split(","):
			_shots.append(float(s))
	_start_mode.call_deferred()


func _start_mode() -> void:
	var port := int(options.get("port", str(MultiplayerManager.DEFAULT_PORT)))
	if options.has("solo"):
		MultiplayerManager.start_solo()
	elif options.has("host"):
		MultiplayerManager.host_game(port)
		_auto_start_players = int(options.get("auto-start", "0"))
	elif options.has("join"):
		MultiplayerManager.join_game(options["join"], port)


func _process(delta: float) -> void:
	if options.is_empty():
		return
	_real_time += delta / maxf(Engine.time_scale, 0.001)
	if options.has("quit-after") and _real_time > float(options["quit-after"]):
		print("[DevTools] quit-after reached")
		get_tree().quit(3)
		return
	if _auto_start_players > 0 and MultiplayerManager.players.size() >= _auto_start_players:
		_auto_start_players = 0
		print("[DevTools] auto-starting with %d players" % MultiplayerManager.players.size())
		MultiplayerManager.start_mission.call_deferred()

	var mission := get_tree().get_first_node_in_group("mission") as MissionManager
	if mission == null:
		return
	if _mission_ref == null or _mission_ref.get_ref() != mission:
		_mission_ref = weakref(mission)
		_mission_time = 0.0
		_shot_index = 0
		if options.has("exit-on-results"):
			mission.mission_finished.connect(_on_mission_finished)
	var prev_time := _mission_time
	_mission_time += delta
	if options.has("log-horde") and int(_mission_time / 2.0) != int(prev_time / 2.0):
		var z := mission.zombies
		print("[Horde] t=%5.1f stage=%s gap=%5.1f target=%5.1f speed=%4.1f surge=%s grab=%.2f" % [mission.elapsed,
			MissionManager.STAGE_NAMES[mission.stage], mission.get_horde_gap(), z.get_target_gap(mission.get_rearmost_speed()),
			mission.get_rearmost_speed(), z.surging, z.grab_progress])
	if options.has("autopilot-react") and CyclingInputManager.source is ScriptedCyclingInput:
		var react := mission.zombies.surging or mission.zombies.is_grabbing()
		(CyclingInputManager.source as ScriptedCyclingInput).constant_watts = float(options["autopilot-react"] if react else options.get("autopilot", "200"))
	if options.has("screenshot") and _shot_index < _shots.size() and _mission_time >= _shots[_shot_index]:
		var path := String(options["screenshot"])
		if path.contains("%d"):
			path = path % _shot_index
		get_viewport().get_texture().get_image().save_png(path)
		print("[DevTools] screenshot saved: %s" % path)
		_shot_index += 1


func _on_mission_finished(results: Dictionary) -> void:
	if _exit_pending:
		return
	_results_seen += 1
	var replays := int(options.get("replays", "0"))
	if _results_seen <= replays:
		print("[DevTools] RESULT #%d success=%s time=%.1f - replaying" % [_results_seen, results.get("success"), results.get("time", 0.0)])
		if MultiplayerManager.is_host():
			await get_tree().create_timer(1.0 * Engine.time_scale).timeout
			MultiplayerManager.start_mission()
		return
	_exit_pending = true
	print("[DevTools] RESULT success=%s time=%.1f gate=%.0f%% my_distance=%.0f my_max_speed=%.1f riders=%d" % [
		results.get("success"), results.get("time", 0.0), float(results.get("gate_progress", 0.0)) * 100.0,
		results.get("my_distance", 0.0), results.get("my_max_speed", 0.0), (results.get("riders", []) as Array).size()])
	# Give the last network messages a moment, and let screenshots of the
	# results screen happen if requested.
	await get_tree().create_timer(1.5 * Engine.time_scale).timeout
	get_tree().quit(0 if results.get("success", false) else 2)
