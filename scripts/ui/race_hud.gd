class_name RaceHUD
extends CanvasLayer
## Criterium HUD: lap and distance to the line, points table, a live map of
## the circuit, your ride, how sheltered you are and your sprint battery.
## Only reads from RaceManager, apart from the results screen buttons.

signal replay_requested
signal menu_requested

const COL_TEXT := HudKit.COL_TEXT
const COL_DIM := HudKit.COL_DIM
const COL_WARN := HudKit.COL_WARN
const COL_DANGER := HudKit.COL_DANGER
const COL_GOOD := HudKit.COL_GOOD
const COL_SHELTER := Color(0.5, 0.85, 1.0)

var race: RaceManager

var _lap: Label
var _lap_sub: Label
var _to_line: Label
var _standings: VBoxContainer
var _map: RaceMap
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
var _gear_label: Label
var _shelter: Label
var _battery_bar: ProgressBar
var _battery_label: Label
var _position_label: Label
var _dev_panel: PanelContainer
var _dev_label: Label
var _results: PanelContainer
var _results_box: VBoxContainer
var _time: float = 0.0


func setup(p_race: RaceManager) -> void:
	race = p_race
	race.announced.connect(_on_announced)
	_build()


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Top centre: lap, what it's worth, distance to the line.
	var top := VBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 0)
	root.add_child(top)
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.offset_left = -330
	top.offset_right = 330
	top.offset_top = 12
	_lap = HudKit.label(top, "LAP 1", 54, COL_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_lap_sub = HudKit.label(top, "", 26, COL_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_to_line = HudKit.label(top, "", 30, COL_WARN, HORIZONTAL_ALIGNMENT_CENTER)

	# Top left: points table.
	var table := HudKit.panel(root)
	table.set_anchors_preset(Control.PRESET_TOP_LEFT)
	table.offset_left = 20
	table.offset_top = 20
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 2)
	table.add_child(tv)
	HudKit.label(tv, "POINTS  -  first to %d" % race.rules.points_to_win, 20, COL_DIM)
	_standings = VBoxContainer.new()
	_standings.add_theme_constant_override("separation", 0)
	tv.add_child(_standings)

	# Top right: map.
	var map_panel := HudKit.panel(root, 0.5)
	map_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	map_panel.offset_left = -330
	map_panel.offset_right = -20
	map_panel.offset_top = 20
	map_panel.offset_bottom = 290
	_map = RaceMap.new()
	_map.custom_minimum_size = Vector2(278, 238)
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_panel.add_child(_map)

	# Banner.
	_banner = VBoxContainer.new()
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_banner)
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.offset_left = -700
	_banner.offset_right = 700
	_banner.offset_top = -250
	_banner.offset_bottom = -110
	_banner_title = HudKit.label(_banner, "", 66, COL_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_banner_sub = HudKit.label(_banner, "", 30, COL_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_banner.modulate.a = 0.0
	_countdown = HudKit.label(root, "", 200, COL_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_countdown.set_anchors_preset(Control.PRESET_CENTER)
	_countdown.offset_left = -300
	_countdown.offset_right = 300
	_countdown.offset_top = -60
	_countdown.offset_bottom = 160

	# Bottom left: your ride + shelter.
	var ride := HudKit.panel(root)
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
	_speed = HudKit.label(speed_row, "0", 96)
	var kmh := HudKit.label(speed_row, " km/h", 30, COL_DIM)
	kmh.size_flags_vertical = Control.SIZE_SHRINK_END
	_power = HudKit.label(rv, "0 W", 48, COL_WARN)
	_effort_bar = HudKit.bar(rv, Vector2(360, 28), Color(1.0, 0.6, 0.1))
	var effort_row := HBoxContainer.new()
	rv.add_child(effort_row)
	_effort_label = HudKit.label(effort_row, "EFFORT 0%", 22, COL_DIM)
	_effort_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cadence = HudKit.label(effort_row, "", 22, COL_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	_shelter = HudKit.label(rv, "", 30, COL_SHELTER)
	_gear_label = HudKit.label(rv, "", 30, COL_TEXT)

	# Bottom right: battery + position on the road.
	var bat := HudKit.panel(root)
	bat.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	bat.offset_right = -24
	bat.offset_bottom = -24
	bat.offset_left = -420
	bat.offset_top = -24
	bat.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	bat.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var bv := VBoxContainer.new()
	bat.add_child(bv)
	HudKit.label(bv, "SPRINT BATTERY", 28, COL_TEXT)
	_battery_bar = HudKit.bar(bv, Vector2(370, 34), COL_GOOD)
	_battery_label = HudKit.label(bv, "", 24, COL_DIM)
	_position_label = HudKit.label(bv, "", 24, COL_DIM)

	# Dev / keyboard help (F1).
	_dev_panel = HudKit.panel(root, 0.35)
	_dev_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_dev_panel.offset_left = 20
	_dev_panel.offset_top = 340
	_dev_label = HudKit.label(_dev_panel, "", 16, COL_DIM)

	_results = HudKit.panel(root, 0.85)
	_results.set_anchors_preset(Control.PRESET_CENTER)
	_results.offset_left = -440
	_results.offset_right = 440
	_results.offset_top = -340
	_results.offset_bottom = 340
	_results.mouse_filter = Control.MOUSE_FILTER_STOP
	_results_box = VBoxContainer.new()
	_results_box.add_theme_constant_override("separation", 8)
	_results.add_child(_results_box)
	_results.visible = false
	_map.setup(race.route)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F1:
		_dev_panel.visible = not _dev_panel.visible


func _process(delta: float) -> void:
	if race == null or race.local_cyclist == null:
		return
	_time += delta
	var me := race.local_cyclist

	# Lap and the line.
	var lap := race.current_lap()
	var bell := race.rules.is_bell_lap(lap)
	if race.stage == RaceManager.Stage.FINISHED:
		_lap.text = "FINISHED"
		_lap_sub.text = ""
		_to_line.text = ""
	else:
		_lap.text = "LAP %d" % lap
		_lap.label_settings.font_color = COL_WARN if bell and int(_time * 2.0) % 2 == 0 else COL_TEXT
		_lap_sub.text = "BELL LAP  -  %d POINTS" % race.rules.points_for_lap(lap) if bell else "1 point for the first across the line"
		_lap_sub.label_settings.font_color = COL_WARN if bell else COL_DIM
		var to_line := race.metres_to_line(me)
		_to_line.text = "%d m to the line" % roundi(to_line)
		_to_line.label_settings.font_color = COL_DANGER if to_line < 250.0 else COL_WARN

	# Ride.
	_speed.text = "%d" % roundi(me.speed * 3.6)
	_power.text = "%d W" % roundi(me.power_avg)
	# Effort as % of FTP (effort 1 = 160%); the bar tops out at 300%.
	var ftp_pct := me.requested_effort * 160.0
	_effort_bar.value = clampf(ftp_pct / 300.0, 0.0, 1.0)
	_effort_label.text = "%d%% of FTP" % roundi(ftp_pct)
	_cadence.text = "%d rpm" % roundi(me.cadence) if me.cadence >= 0.0 else ""
	var fill := _effort_bar.get_theme_stylebox("fill") as StyleBoxFlat
	fill.bg_color = Color(0.3, 0.8, 1.0).lerp(Color(1.0, 0.35, 0.1), clampf(ftp_pct / 200.0, 0.0, 1.0))
	var gear := CyclingInputManager.get_gear()
	_gear_label.visible = CyclingInputManager.show_gear and gear > 0
	_gear_label.text = "GEAR %d / %d" % [gear, CyclingInputManager.get_gear_count()]

	# Shelter.
	match race.shelter_state(me):
		"SHELTERED":
			_shelter.text = "SHELTERED -%d%% wind  behind %s" % [roundi(me.draft_bonus_override * 100.0), me.drafting_behind]
			_shelter.label_settings.font_color = COL_SHELTER
		"DROPPED":
			_shelter.text = "DROPPED - alone in the wind"
			_shelter.label_settings.font_color = COL_DANGER
		_:
			_shelter.text = "IN THE WIND"
			_shelter.label_settings.font_color = COL_WARN

	# Battery.
	var frac := me.battery / maxf(me.battery_capacity, 0.001)
	_battery_bar.value = frac
	(_battery_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = COL_DANGER.lerp(COL_GOOD, clampf(frac * 1.6, 0.0, 1.0))
	if me.battery <= 0.0:
		_battery_label.text = "EMPTY - you can't go above FTP"
		_battery_label.label_settings.font_color = COL_DANGER if int(_time * 3.0) % 2 == 0 else COL_WARN
	elif me.effort > me.battery_threshold:
		_battery_label.text = "Draining  (%d%%)" % roundi(frac * 100.0)
		_battery_label.label_settings.font_color = COL_WARN
	elif frac < 0.999:
		_battery_label.text = "Recharging  (%d%%)" % roundi(frac * 100.0)
		_battery_label.label_settings.font_color = COL_DIM
	else:
		_battery_label.text = "Full"
		_battery_label.label_settings.font_color = COL_GOOD
	var place := race.order.find(me) + 1
	if place == 1:
		_position_label.text = "1st on the road"
	elif place > 1:
		var leader: CyclistController = race.order[0]
		_position_label.text = "%s on the road, %d m behind the front" % [_ordinal(place), roundi(leader.distance - me.distance)]

	_update_standings()
	_update_map()

	# Countdown and banner.
	_countdown.text = str(int(ceil(race.countdown_left))) if race.stage == RaceManager.Stage.COUNTDOWN else ""
	if _banner_time > 0.0:
		_banner_time -= delta
		_banner.modulate.a = minf(1.0, _banner_time * 2.0)
	_update_dev()


static func _ordinal(n: int) -> String:
	if n % 100 in [11, 12, 13]:
		return "%dth" % n
	match n % 10:
		1: return "%dst" % n
		2: return "%dnd" % n
		3: return "%drd" % n
	return "%dth" % n


func _update_standings() -> void:
	var distances := {}
	for id: int in race.riders:
		distances[id] = (race.riders[id] as CyclistController).distance
	var ids := race.rules.standings(distances)
	while _standings.get_child_count() < ids.size():
		HudKit.label(_standings, "", 22)
	for i in ids.size():
		var c: CyclistController = race.riders[ids[i]]
		var row := _standings.get_child(i) as Label
		var you := c == race.local_cyclist
		row.text = "%d. %-10s %2d  %s" % [i + 1, c.player_name.substr(0, 10), race.rules.points[ids[i]],
			"<- you" if you else race.personality_of(ids[i])]
		row.label_settings.font_color = c.jersey_color.lightened(0.35) if not you else COL_TEXT
		row.label_settings.font_size = 24 if you else 21


func _update_map() -> void:
	var dots := []
	for c: CyclistController in race.get_riders():
		var p := c.global_position
		dots.append([Vector2(p.x, p.z), c.jersey_color, c == race.local_cyclist])
	_map.riders = dots
	_map.queue_redraw()


func _update_dev() -> void:
	if not _dev_panel.visible:
		return
	var text := "INPUT:\n%s" % CyclingInputManager.get_source_name()
	var src := CyclingInputManager.source
	if src is SimulatedCyclingInput:
		var sim := src as SimulatedCyclingInput
		var names := ["Stopped", "Recovery", "Easy", "Normal", "Hard", "All-out"]
		text += "  -  cruise: %s (%d W)" % [names[sim.cruise_level], roundi(sim.get_cruise_watts())]
		text += "\n[1-5] cruise level   [0] stop pedalling"
		text += "\n[W/Up] push harder   [Space] sprint   [S/Down] stop"
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
	var won: bool = r.get("success", false)
	HudKit.label(_results_box, "YOU WIN!" if won else "%s WINS" % String(r.get("winner", "")).to_upper(), 58,
		COL_GOOD if won else COL_WARN, HORIZONTAL_ALIGNMENT_CENTER)
	var t: float = r.get("time", 0.0)
	HudKit.label(_results_box, "CRITERIUM  -  %d laps in %d:%02d" % [int(r.get("laps", 0)), int(t) / 60, int(t) % 60], 24, COL_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 30)
	_results_box.add_child(grid)
	for h in ["", "RIDER", "POINTS", "LAPS WON"]:
		HudKit.label(grid, h, 20, COL_DIM)
	var place := 1
	for s: Dictionary in r.get("standings", []):
		var col: Color = COL_TEXT if s["is_player"] else (s["color"] as Color).lightened(0.3)
		HudKit.label(grid, "%d." % place, 24, col)
		HudKit.label(grid, "%s%s" % [s["name"], "  (you)" if s["is_player"] else "  - " + String(s["personality"])], 24, col)
		HudKit.label(grid, str(s["points"]), 24, col)
		HudKit.label(grid, str(s["laps_won"]), 24, col)
		place += 1
	var stats := GridContainer.new()
	stats.columns = 2
	stats.add_theme_constant_override("h_separation", 40)
	_results_box.add_child(stats)
	var rows := [
		["Time in the wind", "%d%%" % roundi(float(r.get("time_in_wind", 0.0)) * 100.0)],
		["Peak power (3 s)", "%d W" % roundi(float(r.get("my_max_power", 0.0)))],
		["Fastest sprint", "%.1f km/h" % (float(r.get("my_best_sprint", 0.0)) * 3.6)],
	]
	for row: Array in rows:
		HudKit.label(stats, row[0], 24, COL_DIM)
		HudKit.label(stats, row[1], 24, COL_TEXT)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_results_box.add_child(spacer)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 30)
	_results_box.add_child(buttons)
	for b: Array in [["RACE AGAIN", replay_requested], ["MAIN MENU", menu_requested]]:
		var button := Button.new()
		button.text = b[0]
		button.custom_minimum_size = Vector2(260, 64)
		button.add_theme_font_size_override("font_size", 28)
		var sig: Signal = b[1]
		button.pressed.connect(func() -> void: sig.emit())
		buttons.add_child(button)
	_results.visible = true
