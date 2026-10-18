class_name HUDController
extends CanvasLayer
## In-mission HUD. Large, high-contrast elements that can be read at a glance
## while riding. Built in code so it's easy to tweak sizes/colours below.
## It only *reads* game state from MissionManager; it never changes it, except
## for the Replay / Menu buttons on the results screen.

signal replay_requested
signal menu_requested

const DANGER_SHADER := preload("res://shaders/danger_vignette.gdshader")
const COL_TEXT := Color(0.95, 0.95, 0.92)
const COL_DIM := Color(0.7, 0.72, 0.7)
const COL_WARN := Color(1.0, 0.7, 0.15)
const COL_DANGER := Color(1.0, 0.25, 0.18)
const COL_GOOD := Color(0.4, 1.0, 0.45)

var mission: MissionManager

var _vignette: ColorRect
var _route_bar: RouteProgressBar
var _objective: Label
var _next_objective: Label
var _banner: VBoxContainer
var _banner_title: Label
var _banner_sub: Label
var _banner_time: float = 0.0
var _countdown: Label
var _speed: Label
var _power: Label
var _effort_bar: ProgressBar
var _effort_label: Label
var _cadence: Label
var _draft: Label
var _danger_bar: ProgressBar
var _danger_gap: Label
var _danger_status: Label
var _gate_panel: PanelContainer
var _gate_bar: ProgressBar
var _gate_pct: Label
var _gate_list: Label
var _team_panel: PanelContainer
var _team_list: VBoxContainer
var _dev_panel: PanelContainer
var _dev_label: Label
var _mirror: PanelContainer
var _mirror_style: StyleBoxFlat
var _mirror_cam: Camera3D
var _results: PanelContainer
var _results_box: VBoxContainer
var _time: float = 0.0


func setup(p_mission: MissionManager) -> void:
	mission = p_mission
	mission.announced.connect(_on_announced)
	_build()


# --- Building ----------------------------------------------------------------

func _settings(font_size: int, color: Color = COL_TEXT) -> LabelSettings:
	var s := LabelSettings.new()
	s.font_size = font_size
	s.font_color = color
	s.outline_size = maxi(4, font_size / 8)
	s.outline_color = Color(0, 0, 0, 0.85)
	s.shadow_size = 2
	s.shadow_color = Color(0, 0, 0, 0.4)
	return s


func _label(parent: Node, text: String, font_size: int, color: Color = COL_TEXT, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.label_settings = _settings(font_size, color)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _panel(parent: Node, alpha: float = 0.45) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.04, 0.04, alpha)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(16)
	sb.border_color = Color(1, 1, 1, 0.08)
	sb.set_border_width_all(1)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	return p


func _bar(parent: Node, min_size: Vector2, fill: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = min_size
	b.show_percentage = false
	b.max_value = 1.0
	b.step = 0.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.6)
	bg.set_corner_radius_all(6)
	bg.border_color = Color(1, 1, 1, 0.35)
	bg.set_border_width_all(2)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	fg.set_corner_radius_all(6)
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fg)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(b)
	return b


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Danger vignette (behind everything else).
	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vm := ShaderMaterial.new()
	vm.shader = DANGER_SHADER
	_vignette.material = vm
	root.add_child(_vignette)

	# Top: route progress + objective.
	var top := VBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 2)
	root.add_child(top)
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.offset_left = -480
	top.offset_right = 480
	top.offset_top = 14
	var marks := HBoxContainer.new()
	top.add_child(marks)
	var l_start := _label(marks, "START", 18, COL_DIM)
	l_start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l_gate := _label(marks, "GATE", 18, COL_WARN, HORIZONTAL_ALIGNMENT_CENTER)
	l_gate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l_end := _label(marks, "EXTRACTION", 18, COL_GOOD, HORIZONTAL_ALIGNMENT_RIGHT)
	l_end.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_route_bar = RouteProgressBar.new()
	_route_bar.custom_minimum_size = Vector2(960, 30)
	_route_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_route_bar)
	_objective = _label(top, "", 34, COL_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_next_objective = _label(top, "", 26, COL_WARN, HORIZONTAL_ALIGNMENT_CENTER)

	# Announcement banner.
	_banner = VBoxContainer.new()
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_banner)
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.offset_left = -700
	_banner.offset_right = 700
	_banner.offset_top = -300
	_banner.offset_bottom = -160
	_banner_title = _label(_banner, "", 72, COL_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_banner_sub = _label(_banner, "", 32, COL_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_banner.modulate.a = 0.0

	_countdown = _label(root, "", 200, COL_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_countdown.set_anchors_preset(Control.PRESET_CENTER)
	_countdown.offset_left = -300
	_countdown.offset_right = 300
	_countdown.offset_top = -100
	_countdown.offset_bottom = 120

	# Bottom-left: your ride.
	var ride := _panel(root)
	ride.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	ride.offset_left = 24
	ride.offset_bottom = -24
	ride.offset_top = -24
	ride.offset_right = 420
	ride.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 0)
	ride.add_child(rv)
	var speed_row := HBoxContainer.new()
	rv.add_child(speed_row)
	_speed = _label(speed_row, "0", 96)
	var kmh := _label(speed_row, " km/h", 30, COL_DIM)
	kmh.size_flags_vertical = Control.SIZE_SHRINK_END
	_power = _label(rv, "0 W", 48, COL_WARN)
	_effort_bar = _bar(rv, Vector2(360, 28), Color(1.0, 0.6, 0.1))
	var effort_row := HBoxContainer.new()
	rv.add_child(effort_row)
	_effort_label = _label(effort_row, "EFFORT 0%", 22, COL_DIM)
	_effort_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cadence = _label(effort_row, "", 22, COL_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	_draft = _label(rv, "", 22, Color(0.5, 0.85, 1.0))

	# Bottom-right: danger.
	var danger := _panel(root)
	danger.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	danger.offset_right = -24
	danger.offset_bottom = -24
	danger.offset_left = -420
	danger.offset_top = -24
	danger.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	danger.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var dv := VBoxContainer.new()
	danger.add_child(dv)
	var drow := HBoxContainer.new()
	dv.add_child(drow)
	var dtitle := _label(drow, "HORDE", 30, COL_DANGER)
	dtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_danger_gap = _label(drow, "--", 48, COL_TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	_danger_bar = _bar(dv, Vector2(370, 34), COL_DANGER)
	_danger_status = _label(dv, "", 30, COL_DIM)

	# Centre: gate objective.
	_gate_panel = _panel(root, 0.6)
	# Bottom centre, between the ride and danger panels, so the gate and
	# the rider stay visible.
	_gate_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_gate_panel.offset_left = -360
	_gate_panel.offset_right = 360
	_gate_panel.offset_top = -24
	_gate_panel.offset_bottom = -24
	_gate_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var gv := VBoxContainer.new()
	_gate_panel.add_child(gv)
	_label(gv, "OPEN THE GATE", 40, COL_WARN, HORIZONTAL_ALIGNMENT_CENTER)
	_label(gv, "Pedal together - everyone's effort winds the winch", 20, COL_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_gate_bar = _bar(gv, Vector2(680, 46), COL_GOOD)
	_gate_pct = _label(gv, "0%", 30, COL_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_gate_list = _label(gv, "", 22, COL_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_gate_panel.visible = false

	# Left, under the dev panel: team (multiplayer only).
	_team_panel = _panel(root)
	_team_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_team_panel.offset_left = 20
	_team_panel.offset_top = 150
	_team_list = VBoxContainer.new()
	_team_panel.add_child(_team_list)
	_team_panel.visible = mission.cyclists.size() > 1

	# Top-left: development input info (F1 to hide).
	_dev_panel = _panel(root, 0.35)
	_dev_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_dev_panel.offset_left = 20
	_dev_panel.offset_top = 20
	_dev_label = _label(_dev_panel, "", 16, COL_DIM)

	_build_mirror(root)
	_build_results(root)


## Rear-view mirror: a second camera looking back at the horde, rendered into
## a small SubViewport that shares the main 3D world.
func _build_mirror(root: Control) -> void:
	_mirror = PanelContainer.new()
	_mirror_style = StyleBoxFlat.new()
	_mirror_style.bg_color = Color.BLACK
	_mirror_style.set_border_width_all(4)
	_mirror_style.border_color = Color(0.2, 0.2, 0.2)
	_mirror_style.set_corner_radius_all(8)
	_mirror.add_theme_stylebox_override("panel", _mirror_style)
	_mirror.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_mirror)
	_mirror.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_mirror.offset_left = -318
	_mirror.offset_right = -20
	_mirror.offset_top = 14
	_mirror.offset_bottom = 172
	var container := SubViewportContainer.new()
	container.stretch = true
	container.custom_minimum_size = Vector2(290, 150)
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mirror.add_child(container)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(290, 150)
	viewport.audio_listener_enable_3d = false
	container.add_child(viewport)
	_mirror_cam = Camera3D.new()
	_mirror_cam.fov = 58.0
	_mirror_cam.far = 200.0
	_mirror_cam.current = true
	viewport.add_child(_mirror_cam)
	var title := _label(_mirror, "REAR VIEW", 16, COL_DIM)
	title.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_mirror.visible = false


func _build_results(root: Control) -> void:
	_results = _panel(root, 0.82)
	_results.set_anchors_preset(Control.PRESET_CENTER)
	_results.offset_left = -430
	_results.offset_right = 430
	_results.offset_top = -330
	_results.offset_bottom = 330
	_results.mouse_filter = Control.MOUSE_FILTER_STOP
	_results_box = VBoxContainer.new()
	_results_box.add_theme_constant_override("separation", 10)
	_results.add_child(_results_box)
	_results.visible = false


# --- Updating ----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F1:
		_dev_panel.visible = not _dev_panel.visible


func _process(delta: float) -> void:
	if mission == null or mission.local_cyclist == null:
		return
	_time += delta
	var me := mission.local_cyclist
	var danger := mission.get_danger()

	# Ride stats.
	_speed.text = "%d" % roundi(me.speed * 3.6)
	_power.text = "%d W" % roundi(me.power_watts)
	_effort_bar.value = me.effort
	_effort_label.text = "EFFORT %d%%" % roundi(me.effort * 100.0)
	_cadence.text = "%d rpm" % roundi(me.cadence) if me.cadence >= 0.0 else ""
	_draft.text = "SLIPSTREAM +%d%%" % roundi(me.ride_model.draft_bonus * 100.0) if me.is_drafting else ""
	var effort_fill := (_effort_bar.get_theme_stylebox("fill") as StyleBoxFlat)
	effort_fill.bg_color = Color(0.3, 0.8, 1.0).lerp(Color(1.0, 0.35, 0.1), me.effort)

	# Objective + route.
	_objective.text = mission.get_objective_text()
	var next := mission.get_next_objective()
	_next_objective.text = "%s  %d m" % [next[0], roundi(next[1])] if mission.is_riding_stage() else ""
	var waiting_to_ride := mission.stage in [MissionManager.Stage.COUNTDOWN, MissionManager.Stage.DEPARTURE, MissionManager.Stage.PURSUIT]
	if waiting_to_ride and me.power_watts < 1.0:
		var hint := "  (keyboard: press 3)" if CyclingInputManager.source is SimulatedCyclingInput else ""
		_next_objective.text = "START PEDALLING!" + hint
	if not CyclingInputManager.is_input_valid() and mission.stage != MissionManager.Stage.SUCCESS and mission.stage != MissionManager.Stage.FAILED:
		_next_objective.text = "TRAINER SIGNAL LOST - check the trainer bridge window"
		_next_objective.label_settings.font_color = COL_DANGER if int(_time * 3.0) % 2 == 0 else COL_WARN
	else:
		_next_objective.label_settings.font_color = COL_WARN
	_route_bar.total = mission.extraction_distance
	_route_bar.gate_at = mission.gate_distance
	_route_bar.gate_open = mission.gate.is_open
	var horde_visible := mission.zombies.phase != ZombieDirector.Phase.DORMANT
	_route_bar.horde_at = mission.zombies.front_distance if horde_visible else -1.0
	var dots := []
	for c: CyclistController in mission.get_riders():
		dots.append([c.distance, c.jersey_color, c == me])
	_route_bar.riders = dots
	_route_bar.queue_redraw()

	# Danger.
	var gap := mission.get_horde_gap()
	_danger_bar.value = danger
	if not horde_visible:
		_danger_gap.text = "--"
		_danger_status.text = "Not yet..."
		_danger_status.label_settings.font_color = COL_DIM
	else:
		_danger_gap.text = "%d m" % maxi(roundi(gap), 0)
		if danger > 0.75:
			_danger_status.text = "RUN!" if int(_time * 4.0) % 2 == 0 else ""
			_danger_status.label_settings.font_color = COL_DANGER
		elif danger > 0.45:
			_danger_status.text = "CLOSING IN"
			_danger_status.label_settings.font_color = COL_WARN
		else:
			_danger_status.text = "Holding them off"
			_danger_status.label_settings.font_color = COL_DIM
		if mission.zombies.surging:
			_danger_status.text = "SURGE!"
			_danger_status.label_settings.font_color = COL_DANGER
		if mission.zombies.is_grabbing():
			# Show how long is left to break free.
			var left := (1.0 - mission.zombies.grab_progress) * mission.zombies.escape_time
			_danger_status.text = "GRABBED! %.1fs" % left
			_danger_status.label_settings.font_color = COL_DANGER
			_danger_bar.value = 1.0 - mission.zombies.grab_progress
			_banner_title.text = "THEY'VE GOT YOU!"
			_banner_sub.text = "Sprint to break free!" if mission.local_cyclist.distance - mission.get_rearmost_distance() < 1.0 \
				else "A teammate is grabbed - drop back and tow them out!"
			_banner_time = maxf(_banner_time, 0.5)
	var heartbeat := pow(maxf(sin(_time * lerpf(5.0, 11.0, danger)), 0.0), 8.0)
	var vm := _vignette.material as ShaderMaterial
	vm.set_shader_parameter("intensity", smoothstep(0.3, 1.0, danger))
	vm.set_shader_parameter("pulse", heartbeat)

	# Gate.
	var at_gate := mission.stage == MissionManager.Stage.GATE
	_gate_panel.visible = at_gate
	if at_gate:
		var gate := mission.gate
		_gate_bar.value = gate.progress
		_gate_pct.text = "%d%%" % roundi(gate.progress * 100.0)
		if me.distance < mission.gate_distance - gate.work_range:
			_gate_pct.text += "   -  get to the gate to help!"
		var parts := []
		for c: CyclistController in mission.get_riders():
			parts.append("%s %.0f" % [c.player_name, float(gate.contributions.get(c.peer_id, 0.0))])
		_gate_list.text = "Team effort:  " + "   ".join(parts) if mission.cyclists.size() > 1 else ""

	# Countdown.
	if mission.stage == MissionManager.Stage.COUNTDOWN:
		_countdown.text = str(int(ceil(mission.countdown_left)))
	elif mission.stage == MissionManager.Stage.WAITING:
		_countdown.text = "..."
	else:
		_countdown.text = ""

	# Banner fade.
	if _banner_time > 0.0:
		_banner_time -= delta
		_banner.modulate.a = minf(1.0, _banner_time * 2.0)

	_update_mirror(danger)
	_update_team()
	_update_dev()


func _update_mirror(danger: float) -> void:
	var active := mission.zombies.phase != ZombieDirector.Phase.DORMANT and not _results.visible
	_mirror.visible = active
	if not active:
		return
	var me := mission.local_cyclist
	var route := mission.route
	# Just ahead of and above the rider, looking back down the road.
	_mirror_cam.global_position = route.get_point(me.distance + 2.5, me.lane_offset * 0.5) + Vector3.UP * 2.6
	_mirror_cam.look_at(route.get_point(me.distance - 16.0) + Vector3.UP * 0.4, Vector3.UP)
	var flash := danger > 0.6 and int(_time * 5.0) % 2 == 0
	_mirror_style.border_color = COL_DANGER if flash else Color(0.25, 0.25, 0.25)


func _update_team() -> void:
	if not _team_panel.visible:
		return
	var riders := mission.get_riders()
	while _team_list.get_child_count() < riders.size():
		_label(_team_list, "", 22)
	for i in _team_list.get_child_count():
		var l := _team_list.get_child(i) as Label
		if i >= riders.size():
			l.text = ""
			continue
		var c: CyclistController = riders[i]
		var bars := int(round(c.effort * 10.0))
		l.text = "%s  %s  %d km/h" % [c.player_name.substr(0, 10), "|".repeat(bars) + ".".repeat(10 - bars), roundi(c.speed * 3.6)]
		l.label_settings.font_color = c.jersey_color.lightened(0.25)


func _update_dev() -> void:
	if not _dev_panel.visible:
		return
	var text := "INPUT: %s" % CyclingInputManager.get_source_name()
	var src := CyclingInputManager.source
	if src is SimulatedCyclingInput:
		var sim := src as SimulatedCyclingInput
		var names := ["Stopped", "Recovery", "Easy", "Normal", "Hard", "All-out"]
		text += "  -  cruise: %s (%d W)" % [names[sim.cruise_level], roundi(sim.get_cruise_watts())]
		text += "\n[1-5] cruise level   [0] stop pedalling"
		text += "\n[W/Up] hold to push harder   [Space] sprint   [S/Down] stop"
	text += "\nFTP %d W   [F1] hide" % roundi(CyclingInputManager.rider_ftp_watts)
	_dev_label.text = text


func _on_announced(title: String, subtitle: String, duration: float) -> void:
	_banner_title.text = title
	_banner_sub.text = subtitle
	_banner_time = duration
	_banner.modulate.a = 1.0


# --- Results -----------------------------------------------------------------

func show_results(r: Dictionary) -> void:
	for c in _results_box.get_children():
		c.queue_free()
	var success: bool = r.get("success", false)
	_label(_results_box, "MISSION COMPLETE" if success else "MISSION FAILED", 56, COL_GOOD if success else COL_DANGER, HORIZONTAL_ALIGNMENT_CENTER)
	_label(_results_box, mission.mission_title, 26, COL_DIM, HORIZONTAL_ALIGNMENT_CENTER)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	_results_box.add_child(grid)
	var t: float = r.get("time", 0.0)
	var rows := [
		["Time", "%d:%02d" % [int(t) / 60, int(t) % 60]],
		["Distance travelled", "%d m" % roundi(r.get("my_distance", 0.0))],
		["Highest speed", "%.1f km/h" % (float(r.get("my_max_speed", 0.0)) * 3.6)],
		["Gate objective", ("Opened" if r.get("gate_opened", false) else "Not opened") + " (%d%%)" % roundi(float(r.get("gate_progress", 0.0)) * 100.0)],
	]
	for row: Array in rows:
		_label(grid, row[0], 28, COL_DIM)
		_label(grid, row[1], 28, COL_TEXT)

	var riders: Array = r.get("riders", [])
	if riders.size() > 1:
		_label(_results_box, "TEAM", 26, COL_WARN)
		for rd: Dictionary in riders:
			_label(_results_box, "%s   %d m   top %.0f km/h   gate effort %.0f" % [rd["name"], roundi(rd["distance"]), float(rd["max_speed"]) * 3.6, float(rd["gate_effort"])], 22, (rd["color"] as Color).lightened(0.25))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_results_box.add_child(spacer)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 30)
	_results_box.add_child(buttons)
	var replay := Button.new()
	replay.custom_minimum_size = Vector2(260, 64)
	replay.add_theme_font_size_override("font_size", 28)
	if mission.is_host():
		replay.text = "REPLAY"
		replay.pressed.connect(func() -> void: replay_requested.emit())
	else:
		replay.text = "Waiting for host..."
		replay.disabled = true
	buttons.add_child(replay)
	var menu := Button.new()
	menu.text = "MAIN MENU"
	menu.custom_minimum_size = Vector2(260, 64)
	menu.add_theme_font_size_override("font_size", 28)
	menu.pressed.connect(func() -> void: menu_requested.emit())
	buttons.add_child(menu)
	_results.visible = true
	_gate_panel.visible = false
