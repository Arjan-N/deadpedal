extends Node
## Automated checks for the core gameplay systems.
## Run:  godot --headless --path . res://tests/unit_tests.tscn
## Exit code 0 = all passed, 1 = something failed.

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	test_ride_model()
	test_simulated_input()
	test_input_manager_effort_is_ftp_relative()
	test_route()
	test_endless_route()
	test_gate_objective()
	test_zombie_director()
	test_runners()
	test_sound_bank()
	test_high_scores()
	test_loop_route()
	test_points_race()
	test_slipstream_and_battery()
	await test_trainer_bridge_input()
	print("")
	if _failures == 0:
		print("ALL TESTS PASSED (%d checks)" % _checks)
	else:
		print("%d OF %d CHECKS FAILED" % [_failures, _checks])
	get_tree().quit(0 if _failures == 0 else 1)


func check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("  ok   %s" % description)
	else:
		_failures += 1
		print("  FAIL %s" % description)


func test_ride_model() -> void:
	print("RideModel")
	var m := RideModel.new()
	check(m.target_speed(0.0) == 0.0, "no effort -> target speed 0")
	check(is_equal_approx(m.target_speed(1.0), m.max_speed_mps), "full effort -> max speed")
	var increasing := true
	var prev := 0.0
	for i in range(1, 21):
		var s := m.target_speed(i / 20.0)
		if s < prev:
			increasing = false
		prev = s
	check(increasing, "target speed increases with effort")
	# Accelerate from standstill at 60% effort for 20 s.
	var speed := 0.0
	var max_step := 0.0
	for i in 20 * 60:
		var new_speed := m.step_speed(speed, 0.6, 1.0 / 60.0)
		max_step = maxf(max_step, absf(new_speed - speed))
		speed = new_speed
	check(absf(speed - m.target_speed(0.6)) < 0.2, "reaches steady speed (%.1f m/s)" % speed)
	check(max_step * 60.0 <= m.acceleration_mps2 + m.sprint_acceleration_bonus_mps2 + 0.01, "acceleration is limited (smooth)")
	# Stop pedalling: momentum carries, then slows.
	var after_1s := speed
	for i in 60:
		after_1s = m.step_speed(after_1s, 0.0, 1.0 / 60.0)
	check(after_1s < speed and after_1s > speed - m.deceleration_mps2 - 0.01, "coasting decelerates gradually")
	check(m.step_speed(10.0, 0.6, 1.0 / 60.0, true) > m.step_speed(10.0, 0.6, 1.0 / 60.0, false), "drafting gives a bonus")


func test_simulated_input() -> void:
	print("SimulatedCyclingInput")
	var sim := SimulatedCyclingInput.new()
	sim.ftp_watts = 200.0
	sim.full_effort_watts = 320.0
	check(sim.get_power_watts() == 0.0, "starts at 0 W")
	sim.cruise_level = 3
	for i in 300:
		sim.step(1.0 / 60.0, false, false, false)
	check(absf(sim._power - 170.0) < 1.0, "cruise level 3 settles at 85%% FTP (%.0f W)" % sim._power)
	for i in 120:
		sim.step(1.0 / 60.0, true, false, false)
	var pushed := sim._power
	check(pushed > 300.0, "holding push raises power (%.0f W)" % pushed)
	for i in 30:
		sim.step(1.0 / 60.0, false, false, false)
	check(sim._power < pushed, "releasing push lowers power")
	for i in 300:
		sim.step(1.0 / 60.0, false, false, false)
	check(absf(sim._power - 170.0) < 1.0, "...back to cruise")
	for i in 30:
		sim.step(1.0 / 60.0, false, true, false)
	check(sim._power > 300.0, "sprint ramps quickly (%.0f W in 0.5 s)" % sim._power)
	for i in 120:
		sim.step(1.0 / 60.0, false, false, true)
	check(sim._power == 0.0, "stop key drops power to 0")
	check(sim.get_effort() == 0.0, "no power -> no effort")
	check(sim.is_input_valid(), "simulated input is valid")
	check(sim.get_source_name().contains("SIMULATED"), "source is clearly labelled simulated")
	sim.free()


func test_input_manager_effort_is_ftp_relative() -> void:
	print("CyclingInputManager")
	var original_ftp := CyclingInputManager.rider_ftp_watts
	var original_source := CyclingInputManager.source
	var a := ScriptedCyclingInput.new()
	a.constant_watts = 150.0
	CyclingInputManager.source = null  # keep the original alive; swap manually
	CyclingInputManager.set_source(a)
	CyclingInputManager.rider_ftp_watts = 150.0
	var effort_weak := CyclingInputManager.get_effort()
	a.constant_watts = 300.0
	CyclingInputManager.rider_ftp_watts = 300.0
	var effort_strong := CyclingInputManager.get_effort()
	check(is_equal_approx(effort_weak, effort_strong), "same %%FTP gives same effort for different riders (%.2f)" % effort_weak)
	check(CyclingInputManager.get_source_type() == CyclingInputSource.SourceType.SCRIPTED, "source can be swapped")
	# Restore.
	var swapped := CyclingInputManager.source
	CyclingInputManager.remove_child(swapped)
	swapped.free()
	CyclingInputManager.source = original_source
	CyclingInputManager.rider_ftp_watts = original_ftp


func test_route() -> void:
	print("Route")
	var r := Route.new()
	add_child(r)
	var length := r.get_length()
	check(length > 1950.0 and length < 2150.0, "route length ~2 km (%.0f m)" % length)
	var smooth := true
	var orthonormal := true
	var prev := r.get_point(0.0)
	for i in range(1, 400):
		var d := i * 5.0
		if d > length:
			break
		var p := r.get_point(d)
		if absf(p.distance_to(prev) - 5.0) > 0.3:
			smooth = false
		prev = p
		var b := r.get_frame(d).basis
		if not b.is_conformal() or absf(b.x.dot(b.z)) > 0.001:
			orthonormal = false
	check(smooth, "distance along route matches world distance")
	check(orthonormal, "route frames are orthonormal")
	var f := r.get_frame(100.0)
	check(f.basis.x.dot(r.get_point(100.0, 2.0) - r.get_point(100.0)) > 1.9, "positive lateral offset = right side")
	r.free()


func test_gate_objective() -> void:
	print("GateObjective")
	var g := GateObjective.new()
	add_child(g)
	var solo_target := g.get_target(1)
	var duo_target := g.get_target(2)
	check(duo_target > solo_target and duo_target < solo_target * 2.0, "two riders need more total effort, but less than double")
	# Solo at 60% vs two riders at 60%.
	var t_solo := 0.0
	while g.progress < 1.0 and t_solo < 120.0:
		g.add_effort({1: 0.6}, 0.1, 1)
		t_solo += 0.1
	g.progress = 0.0
	g.contributions.clear()
	var t_duo := 0.0
	while g.progress < 1.0 and t_duo < 120.0:
		g.add_effort({1: 0.6, 2: 0.6}, 0.1, 2)
		t_duo += 0.1
	check(t_duo < t_solo, "a team opens the gate faster (solo %.1fs, duo %.1fs)" % [t_solo, t_duo])
	g.progress = 0.0
	g.contributions.clear()
	var t_mixed := 0.0
	while g.progress < 1.0 and t_mixed < 120.0:
		g.add_effort({1: 0.9, 2: 0.3}, 0.1, 2)
		t_mixed += 0.1
	check(absf(t_mixed - t_duo) < 0.25, "a strong rider can carry a weaker one (same total effort, %.1fs)" % t_mixed)
	check(g.contributions[1] > g.contributions[2], "contributions are tracked per rider")
	g.free()


func test_zombie_director() -> void:
	print("ZombieDirector")
	var r := Route.new()
	add_child(r)
	var z := ZombieDirector.new()
	add_child(z)
	z.route = r
	z.surge_interval = Vector2(1000, 1000)  # no random surges in tests
	check(z.get_danger(100.0) == 0.0, "no danger before pursuit")
	z.set_phase(ZombieDirector.Phase.PURSUIT, 200.0)
	check(is_equal_approx(z.get_gap(200.0), z.start_gap), "horde appears start_gap behind")

	# Riding at different steady speeds settles at different, sensible gaps.
	var gaps := {}
	var pace := z.pursuit_pace
	for speed: float in [pace - 2.0, pace, pace + 2.0, 15.0]:
		var rider := 200.0
		z.front_distance = rider - z.start_gap
		z.grab_progress = 0.0
		for i in 600:  # 60 s
			rider += speed * 0.1
			z.simulate(0.1, rider, speed)
		gaps[speed] = z.get_gap(rider)
	check(gaps[pace - 2.0] < gaps[pace] and gaps[pace] < gaps[pace + 2.0], "faster riding keeps the horde further back (%s)" % [gaps])
	check(absf(gaps[pace] - z.base_gap) < 1.0, "riding at the horde's pace settles at base_gap")
	check(gaps[15.0] <= z.max_gap + 0.01, "the horde never drops further back than max_gap")
	check(gaps[pace - 2.0] > z.catch_distance, "slightly slow riding is dangerous but survivable")

	# Stopping dead: warning time, then a grab, then caught.
	var stop_at := 500.0
	z.front_distance = stop_at - 30.0
	z.grab_progress = 0.0
	var t := 0.0
	while not z.is_grabbing() and t < 60.0:
		z.simulate(0.1, stop_at, 0.0)
		t += 0.1
	check(t >= 30.0 / z.max_close_rate - 0.2, "from 30 m a stopped rider gets at least %.0f s warning (%.1f s)" % [30.0 / z.max_close_rate, t])
	check(not z.is_catching(), "being grabbed is not instantly fatal")
	var grabbed_for := 0.0
	while not z.is_catching() and grabbed_for < 10.0:
		z.simulate(0.1, stop_at, 0.0)
		grabbed_for += 0.1
	check(absf(grabbed_for - z.escape_time) < 0.25, "caught after escape_time of being grabbed (%.1f s)" % grabbed_for)

	# Sprinting out of a grab.
	z.front_distance = stop_at - z.catch_distance
	z.grab_progress = 0.5
	var rider2 := stop_at
	for i in 40:  # 4 s of sprinting
		rider2 += 15.0 * 0.1
		z.simulate(0.1, rider2, 15.0)
	check(not z.is_catching() and z.grab_progress == 0.0, "sprinting breaks free from a grab")

	var near := z.get_danger(z.front_distance + 5.0)
	var far := z.get_danger(z.front_distance + 35.0)
	check(near > far, "danger rises as the horde gets closer")
	r.free()
	z.free()


func test_runners() -> void:
	print("Runners")
	var r := Route.new()
	add_child(r)
	var z := ZombieDirector.new()
	add_child(z)
	z.route = r
	z.surge_interval = Vector2(1000, 1000)
	var pace := z.pursuit_pace
	var reached := [0]
	z.runner_reached.connect(func(_d: float) -> void: reached[0] += 1)

	# Story mode: no runners.
	z.set_phase(ZombieDirector.Phase.PURSUIT, 200.0)
	var rider := 200.0
	for i in 600:
		rider += pace * 0.1
		z.simulate(0.1, rider, pace)
	check(z.runners.is_empty() and reached[0] == 0, "no runners unless runner_interval is set")

	# Riding at the horde's pace, a runner breaks out and reaches you.
	z.runner_interval = Vector2(1.0, 1.0)
	z.max_runners = 1
	for i in 150:
		rider += pace * 0.1
		z.simulate(0.1, rider, pace)
	check(reached[0] >= 1, "a runner reaches a rider riding at the horde's pace")

	# Sprinting away: the runner tires and drops back into the horde.
	z.runner_interval = Vector2(1000, 1000)
	z.runners = [[z.front_distance + 0.5, pace, 0.0]]
	reached[0] = 0
	var sprint := pace + z.runner_speed_bonus + 1.0
	for i in 150:
		rider += sprint * 0.1
		z.simulate(0.1, rider, sprint)
	check(reached[0] == 0 and z.runners.is_empty(), "sprinting away from a runner works")

	# Runners travel in the network snapshot.
	z.runners = [[rider - 10.0, 13.0, 1.0]]
	var copy := ZombieDirector.new()
	copy.apply_snapshot(z.get_snapshot())
	check(copy.runners.size() == 1 and absf(float(copy.runners[0][0]) - (rider - 10.0)) < 0.01, "runners are sent to other players")
	check(absf(copy.nearest_runner_gap(rider) - 10.0) < 0.01, "distance from the nearest runner")
	copy.free()
	r.free()
	z.free()


func test_loop_route() -> void:
	print("LoopRoute (criterium circuit)")
	var r := LoopRoute.new()
	add_child(r)
	var length := r.get_length()
	check(length > 450.0 and length < 700.0, "a lap is a few hundred metres (%.0f m)" % length)
	check(r.get_point(0.0).distance_to(r.get_point(length)) < 0.01, "the circuit closes (end = start)")
	check(r.get_point(10.0).distance_to(r.get_point(10.0 + length * 3.0)) < 0.01, "distances wrap around laps")
	check(r.get_point(-5.0).distance_to(r.get_point(length - 5.0)) < 0.01, "negative distances (the start grid) wrap too")
	var smooth := true
	var d := 0.0
	while d < length:
		var step := r.get_point(d).distance_to(r.get_point(d + 1.0))
		if absf(step - 1.0) > 0.02:
			smooth = false
		d += 1.0
	check(smooth, "no jumps anywhere around the lap")
	check(r.get_outline(5.0).size() > 80, "outline for the HUD map")
	r.free()


func test_points_race() -> void:
	print("PointsRace (scoring)")
	var p := PointsRace.new()
	p.points_to_win = 5
	p.bell_every = 5
	p.bell_points = 2
	p.setup([1, 2, 3])
	check(p.lap_completed(2, 1) == 1, "first across the line scores a point")
	check(p.lap_completed(1, 1) == 0, "second across the line scores nothing")
	check(not p.is_bell_lap(4) and p.is_bell_lap(5) and p.is_bell_lap(10), "every 5th lap is a bell lap")
	for lap in [2, 3, 4]:
		p.lap_completed(1, lap)
	check(p.lap_completed(3, 5) == 2, "the bell lap is worth 2 points")
	check(p.points[1] == 3 and p.laps_won[1] == 3 and p.points[3] == 2, "points and laps won are counted")
	check(p.winner == -1, "nobody has won yet")
	p.lap_completed(1, 6)
	p.lap_completed(1, 7)
	check(p.winner == 1, "first to the target wins")
	check(p.lap_completed(2, 8) == 0, "no more points after the race is won")
	check(p.standings()[0] == 1 and p.standings()[1] == 3, "standings sorted by points")


func test_slipstream_and_battery() -> void:
	print("Slipstream and battery")
	var full := RaceManager.draft_bonus_for_gap(1.0, 0.2, 1.5, 8.0)
	var mid := RaceManager.draft_bonus_for_gap(5.0, 0.2, 1.5, 8.0)
	check(is_equal_approx(full, 0.2), "full shelter right on a wheel")
	check(mid > 0.0 and mid < full, "less shelter further back")
	check(RaceManager.draft_bonus_for_gap(9.0, 0.2, 1.5, 8.0) == 0.0, "no shelter out of range")
	check(RaceManager.draft_bonus_for_gap(0.1, 0.2, 1.5, 8.0) == 0.0, "no shelter riding side by side")
	var m := RideModel.new()
	var e := m.effort_for_speed(11.0, 0.2)
	check(absf(m.target_speed(e) * 1.2 - 11.0) < 0.05, "effort_for_speed inverts the ride model")
	check(m.effort_for_speed(11.0, 0.2) < m.effort_for_speed(11.0, 0.0), "sheltered riders need less effort")
	var b := 10.0
	for i in 100:  # 10 s all-out
		b = RideModel.step_battery(b, 1.0, 0.1, 10.0, 0.5)
	check(absf(b - (10.0 - (1.0 - RideModel.FTP_EFFORT) * 10.0)) < 0.01, "all-out drains the battery")
	for i in 600:
		b = RideModel.step_battery(b, 0.0, 0.1, 10.0, 0.5)
	check(is_equal_approx(b, 10.0), "easy riding refills it (to capacity)")
	check(RideModel.cap_effort(1.0, 0.0) == RideModel.FTP_EFFORT, "empty battery: capped at FTP")
	check(RideModel.cap_effort(1.0, 3.0) == 1.0, "with battery left: full effort")


func test_sound_bank() -> void:
	print("SoundBank")
	# Every sound id the game plays must have at least one recording.
	var ids := ["wind_loop", "tyre_loop", "drivetrain_loop", "freewheel_loop", "horde_loop", "ambience_loop",
		"groan", "heartbeat", "gate_ratchet", "gate_open", "countdown_beep", "go", "horde_roar", "success", "failure"]
	var missing := []
	for id: String in ids:
		if SoundBank.get_variants(id).is_empty():
			missing.append(id)
	check(missing.is_empty(), "all %d game sounds have recordings%s" % [ids.size(), "" if missing.is_empty() else " - missing: %s" % [missing]])
	check(SoundBank.get_variants("groan").size() >= 4, "several groan variations (%d)" % SoundBank.get_variants("groan").size())


func test_trainer_bridge_input() -> void:
	print("TrainerBridgeInput")
	var input := TrainerBridgeInput.new()
	add_child(input)
	check(input.is_listening(), "listens for the trainer bridge on UDP %d" % TrainerBridgeInput.PORT)
	check(not input.is_input_valid() and input.get_gear() == 0, "no data yet: invalid, no gear")
	var udp := PacketPeerUDP.new()
	udp.connect_to_host("127.0.0.1", TrainerBridgeInput.PORT)
	udp.put_packet(JSON.stringify({"power": 215.0, "cadence": 88.0, "device": "Test", "simulated": false, "gear": 9, "gears": 24}).to_utf8_buffer())
	for i in 10:
		await get_tree().process_frame
	check(input.is_input_valid() and is_equal_approx(input.get_power_watts(), 215.0), "receives power from the bridge")
	check(input.get_gear() == 9 and input.get_gear_count() == 24, "receives the virtual gear (%d/%d)" % [input.get_gear(), input.get_gear_count()])
	check(input.get_source_type() == CyclingInputSource.SourceType.SMART_TRAINER, "real trainer data is labelled SMART_TRAINER")
	udp.put_packet(JSON.stringify({"power": 100.0, "gear": 0, "gears": 0}).to_utf8_buffer())
	for i in 10:
		await get_tree().process_frame
	check(input.get_gear() == 0, "no Click connected: no gear shown")
	udp.close()
	input.queue_free()


func test_endless_route() -> void:
	print("EndlessRoute")
	var a := EndlessRoute.new()
	var b := EndlessRoute.new()
	var c := EndlessRoute.new()
	a.reset(42)
	b.reset(42)
	c.reset(7)
	var smooth := true
	var same := true
	var max_turn := 0.0
	var prev := a.get_point(0.0)
	var prev_fwd := -a.get_frame(0.0).basis.z
	for i in range(1, 4001):  # 20 km in 5 m steps
		var d := i * 5.0
		var p := a.get_point(d)
		if absf(p.distance_to(prev) - 5.0) > 0.05:
			smooth = false
		if p.distance_to(b.get_point(d)) > 0.001:
			same = false
		var fwd := -a.get_frame(d).basis.z
		max_turn = maxf(max_turn, rad_to_deg(prev_fwd.angle_to(fwd)))
		prev = p
		prev_fwd = fwd
	check(smooth, "distance along the endless road matches travelled distance (20 km)")
	check(max_turn < 3.0, "no sharp kinks: max %.2f deg per 5 m" % max_turn)
	check(same, "same seed gives the same road on every machine")
	check(a.get_point(3000.0).distance_to(c.get_point(3000.0)) > 1.0, "a different seed gives a different road")
	check(a.get_point(20000.0).z < -15000.0, "the road keeps heading onwards (no loops)")
	check(a.get_point(-50.0).distance_to(a.get_point(0.0)) > 49.0, "positions behind the start are defined")
	a.free()
	b.free()
	c.free()


func test_high_scores() -> void:
	print("HighScores")
	var real_path := HighScores.path
	HighScores.path = "user://test_scores.cfg"
	DirAccess.remove_absolute(HighScores.path)
	check(HighScores.load_scores().is_empty(), "starts empty")
	check(HighScores.add({"score": 1000, "distance": 900.0}) == 1, "first run is #1")
	check(HighScores.add({"score": 500, "distance": 450.0}) == 2, "a lower score ranks below")
	check(HighScores.add({"score": 2000, "distance": 1800.0}) == 1, "a better score takes #1")
	for i in 12:
		HighScores.add({"score": 600 + i, "distance": 500.0})
	check(HighScores.load_scores().size() == HighScores.MAX_ENTRIES, "keeps only the top %d" % HighScores.MAX_ENTRIES)
	check(HighScores.add({"score": 1, "distance": 1.0}) == 0, "a score below the table isn't ranked")
	check(int(HighScores.best()["score"]) == 2000, "best() returns the top score")
	DirAccess.remove_absolute(HighScores.path)
	HighScores.path = real_path
