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
##   --mode=endless         with --solo / --host: Endless Survival
##   --seed=N               fixed world seed (endless mode)
##   --host                 host a game; --auto-start=N starts at N players
##   --join=IP              join a game at IP
##   --port=N               network port (default 7777)
##   --name=NAME            rider name      --ftp=W   rider FTP
##   --input=trainer        use the smart-trainer bridge input (keyboard = default)
##   --autopilot=W          replace keyboard input with a constant W watts
##   --autopilot-profile=T:W,T:W,...   watts changing at times T (seconds)
##   --autopilot-react=W    with --autopilot: ride at W watts while the horde
##                          surges or grabs (simulates a player who sprints)
##   --autopilot-pickup     with --autopilot (endless mode): ease off for
##                          survivors, crates and exhausted companions, and
##                          sprint past screamers
##   --mode=race            (with --solo) the criterium; also --race-points=N,
##                          --race-opponents=N, --race-difficulty=0|1|2 and
##                          --autopilot-sprint-at=M (metres before the line),
##                          --autopilot-race=sprinter|diesel|... (you race
##                          like that computer rider), --log-race
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
## Autopilot sprint reserve (joules above FTP, like a rider's W'), so test
## riders can't sprint forever.
const AUTOPILOT_RESERVE := 18000.0
var _reserve: float = AUTOPILOT_RESERVE
var _sprinting := false


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
		MultiplayerManager.start_solo(options.get("mode", MultiplayerManager.MODE_STORY))
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
		MultiplayerManager.start_mission.call_deferred(options.get("mode", MultiplayerManager.MODE_STORY))

	var mission := get_tree().get_first_node_in_group("mission") as MissionManager
	if mission == null:
		_process_race(delta)
		return
	if _mission_ref == null or _mission_ref.get_ref() != mission:
		_mission_ref = weakref(mission)
		_mission_time = 0.0
		_shot_index = 0
		_reserve = AUTOPILOT_RESERVE
		if options.has("exit-on-results"):
			mission.mission_finished.connect(_on_mission_finished)
	var prev_time := _mission_time
	_mission_time += delta
	if options.has("log-horde") and int(_mission_time / 2.0) != int(prev_time / 2.0):
		var z := mission.zombies
		print("[Horde] t=%5.1f stage=%s gap=%5.1f target=%5.1f speed=%4.1f surge=%s grab=%.2f" % [mission.elapsed,
			MissionManager.STAGE_NAMES[mission.stage], mission.get_horde_gap(), z.get_target_gap(mission.get_rearmost_speed()),
			mission.get_rearmost_speed(), z.surging, z.grab_progress])
	if CyclingInputManager.source is ScriptedCyclingInput and (options.has("autopilot-react") or options.has("autopilot-pickup")):
		var watts := float(options.get("autopilot", "200"))
		var sprint := float(options.get("autopilot-react", str(watts * 1.8)))
		var me := mission.local_cyclist
		var runner_close := me != null and mission.zombies.nearest_runner_gap(me.distance) < 40.0
		var endless := mission as EndlessMission
		if options.has("autopilot-react") and (mission.zombies.surging or mission.zombies.is_grabbing() or runner_close):
			watts = sprint
		elif options.has("autopilot-pickup") and endless and me:
			var screamer := endless.distance_to_next_screamer(me.distance)
			var exhausted := endless.exhausted_companion_gap(me.distance)
			var pickup := endless.distance_to_next_pickup(me.distance)
			if screamer >= 0.0 and screamer < 90.0:
				watts = sprint  # fly past screamers
			elif exhausted > 6.0:
				watts = 0.0 if me.speed > 4.0 else 30.0  # let them catch your wheel
			elif pickup >= 0.0 and pickup < 80.0:
				# Brake just enough to roll past the survivor / crate at ~18 km/h.
				var brake_speed := sqrt(5.0 * 5.0 + 2.0 * 1.1 * maxf(pickup - 4.0, 0.0))
				if me.speed > brake_speed:
					watts = 0.0
		# Sprints above FTP drain the reserve; riding below FTP refills it.
		var ftp := CyclingInputManager.rider_ftp_watts
		if watts > ftp and _reserve <= 0.0:
			watts = ftp
		if watts > ftp:
			_reserve -= (watts - ftp) * delta
		else:
			_reserve = minf(_reserve + (ftp - watts) * 0.5 * delta, AUTOPILOT_RESERVE)
		(CyclingInputManager.source as ScriptedCyclingInput).constant_watts = watts
	_maybe_screenshot()


func _maybe_screenshot() -> void:
	if options.has("screenshot") and _shot_index < _shots.size() and _mission_time >= _shots[_shot_index]:
		var path := String(options["screenshot"])
		if path.contains("%d"):
			path = path % _shot_index
		get_viewport().get_texture().get_image().save_png(path)
		print("[DevTools] screenshot saved: %s" % path)
		_shot_index += 1


## Criterium: exit on results, screenshots and the racing autopilot
## (--autopilot=W rides at W watts in the bunch and sprints for the line).
func _process_race(delta: float) -> void:
	var race := get_tree().get_first_node_in_group("race") as RaceManager
	if race == null:
		return
	if _mission_ref == null or _mission_ref.get_ref() != race:
		_mission_ref = weakref(race)
		_mission_time = 0.0
		_shot_index = 0
		_sprinting = false
		if options.has("exit-on-results"):
			race.race_finished.connect(_on_race_finished)
	var prev := _mission_time
	_mission_time += delta
	var me := race.local_cyclist
	if options.has("log-race") and int(_mission_time / 3.0) != int(prev / 3.0) and race.order.size() > 0:
		var lead: float = (race.order[0] as CyclistController).distance
		var parts := []
		for c: CyclistController in race.order:
			parts.append("%s(%s) -%.0f e%.2f b%.0f%%%s" % [c.player_name, race.personality_of(c.peer_id).substr(0, 4), lead - c.distance,
				c.effort, c.battery / c.battery_capacity * 100.0, " d" if c.draft_bonus_override > 0.005 else ""])
		print("[RaceLog] t=%.0f lap %d to_line %.0f v=%.1f | %s" % [race.elapsed, race.current_lap(), race.metres_to_line(race.order[0]),
			(race.order[0] as CyclistController).speed, "  ".join(parts)])
	if CyclingInputManager.source is ScriptedCyclingInput and me and race.order.size() > 0 and not options.has("autopilot-profile") \
			and not options.has("autopilot-race"):
		var watts := float(options.get("autopilot", "200"))
		var sprint := float(options.get("autopilot-react", str(watts * 2.0)))
		var to_line := race.metres_to_line(me)
		var lead_gap := (race.order[0] as CyclistController).distance - me.distance
		var sprint_at := float(options.get("autopilot-sprint-at", "220"))
		if not race.is_racing() or to_line > sprint_at or lead_gap > 30.0:
			_sprinting = false
		elif not _sprinting and me.battery > me.battery_capacity * 0.4:
			_sprinting = true
		if _sprinting:
			watts = sprint
		else:
			var i := race.order.find(me)
			if i == 0:
				watts *= 0.8  # on the front: don't do all the work
			else:
				var gap := (race.order[i - 1] as CyclistController).distance - me.distance
				if gap > 3.0 and gap < 25.0:
					watts *= 1.3  # close the gap to the wheel ahead
		(CyclingInputManager.source as ScriptedCyclingInput).constant_watts = watts
	_maybe_screenshot()


func _on_race_finished(results: Dictionary) -> void:
	if _exit_pending:
		return
	_exit_pending = true
	var points := []
	for s: Dictionary in results.get("standings", []):
		points.append("%s:%d" % [s["name"], s["points"]])
	print("[DevTools] RESULT race success=%s winner=%s laps=%d time=%.1f points=%s" % [results.get("success"), results.get("winner"),
		results.get("laps", 0), results.get("time", 0.0), ", ".join(points)])
	await get_tree().create_timer(1.5 * Engine.time_scale).timeout
	get_tree().quit(0 if results.get("success", false) else 2)


func _on_mission_finished(results: Dictionary) -> void:
	if _exit_pending:
		return
	_results_seen += 1
	var replays := int(options.get("replays", "0"))
	if _results_seen <= replays:
		print("[DevTools] RESULT #%d success=%s time=%.1f - replaying" % [_results_seen, results.get("success"), results.get("time", 0.0)])
		if MultiplayerManager.is_host():
			await get_tree().create_timer(1.0 * Engine.time_scale).timeout
			MultiplayerManager.start_mission(MultiplayerManager.mission_mode)
		return
	_exit_pending = true
	print("[DevTools] RESULT success=%s time=%.1f gate=%.0f%% my_distance=%.0f my_max_speed=%.1f riders=%d" % [
		results.get("success"), results.get("time", 0.0), float(results.get("gate_progress", 0.0)) * 100.0,
		results.get("my_distance", 0.0), results.get("my_max_speed", 0.0), (results.get("riders", []) as Array).size()])
	# Give the last network messages a moment, and let screenshots of the
	# results screen happen if requested.
	await get_tree().create_timer(1.5 * Engine.time_scale).timeout
	get_tree().quit(0 if results.get("success", false) else 2)
