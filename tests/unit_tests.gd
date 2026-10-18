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
	test_gate_objective()
	test_zombie_director()
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
	CyclingInputManager.source.queue_free()
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
