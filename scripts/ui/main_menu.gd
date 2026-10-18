extends Control
## Title screen: rider profile, solo start, host/join and a simple lobby.

const COL_RED := Color(0.75, 0.1, 0.07)
const COL_TEXT := Color(0.92, 0.92, 0.88)
const COL_DIM := Color(0.6, 0.62, 0.6)

var _name_edit: LineEdit
var _ftp_spin: SpinBox
var _ip_edit: LineEdit
var _port_spin: SpinBox
var _input_option: OptionButton
var _input_status: Label
var _main_box: VBoxContainer
var _lobby_box: VBoxContainer
var _lobby_status: Label
var _lobby_players: Label
var _lobby_start: Button
var _message: Label


func _ready() -> void:
	_build()
	MultiplayerManager.roster_changed.connect(_refresh_lobby)
	MultiplayerManager.connected_to_host.connect(_on_connected)
	MultiplayerManager.connection_failed.connect(_on_connection_failed)
	if MultiplayerManager.last_message != "":
		_message.text = MultiplayerManager.last_message
		MultiplayerManager.last_message = ""


func _label(parent: Node, text: String, font_size: int, color: Color = COL_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	var s := LabelSettings.new()
	s.font_size = font_size
	s.font_color = color
	s.outline_size = 4
	s.outline_color = Color(0, 0, 0, 0.8)
	l.label_settings = s
	parent.add_child(l)
	return l


func _button(parent: Node, text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(420, 62)
	b.add_theme_font_size_override("font_size", 28)
	b.pressed.connect(callback)
	parent.add_child(b)
	return b


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.07)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var stripe := ColorRect.new()
	stripe.color = Color(0.45, 0.05, 0.04, 0.5)
	stripe.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	stripe.offset_right = 14
	add_child(stripe)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 70)
	add_child(margin)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 80)
	margin.add_child(columns)

	# Left column: title + actions.
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 14)
	columns.add_child(left)
	_label(left, "DEAD PEDAL", 110, COL_RED)
	_label(left, "Ride together. Stay together. Survive.", 30, COL_DIM)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 30)
	left.add_child(gap)

	_main_box = VBoxContainer.new()
	_main_box.add_theme_constant_override("separation", 14)
	left.add_child(_main_box)
	_button(_main_box, "START MISSION (solo)", _on_solo)
	_button(_main_box, "HOST GAME", _on_host)
	var join_row := HBoxContainer.new()
	_main_box.add_child(join_row)
	_button(join_row, "JOIN GAME", _on_join).custom_minimum_size = Vector2(200, 62)
	_ip_edit = LineEdit.new()
	_ip_edit.text = "127.0.0.1"
	_ip_edit.placeholder_text = "Host IP address"
	_ip_edit.custom_minimum_size = Vector2(212, 62)
	_ip_edit.add_theme_font_size_override("font_size", 24)
	join_row.add_child(_ip_edit)
	_button(_main_box, "QUIT", func() -> void: get_tree().quit())

	_lobby_box = VBoxContainer.new()
	_lobby_box.add_theme_constant_override("separation", 12)
	_lobby_box.visible = false
	left.add_child(_lobby_box)
	_label(_lobby_box, "LOBBY", 40, COL_TEXT)
	_lobby_status = _label(_lobby_box, "", 22, COL_DIM)
	_lobby_players = _label(_lobby_box, "", 28, COL_TEXT)
	_lobby_start = _button(_lobby_box, "START MISSION", func() -> void: MultiplayerManager.start_mission())
	_button(_lobby_box, "LEAVE", _on_leave)

	_message = _label(left, "", 24, Color(1.0, 0.6, 0.3))

	# Right column: rider profile + how to play.
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 12)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)
	_label(right, "RIDER", 34, COL_TEXT)
	_label(right, "Name", 22, COL_DIM)
	_name_edit = LineEdit.new()
	_name_edit.text = CyclingInputManager.rider_name
	_name_edit.max_length = 16
	_name_edit.custom_minimum_size = Vector2(360, 50)
	_name_edit.add_theme_font_size_override("font_size", 24)
	right.add_child(_name_edit)
	_label(right, "FTP (watts) - your effort is scaled to your own fitness", 22, COL_DIM)
	_ftp_spin = SpinBox.new()
	_ftp_spin.min_value = 50
	_ftp_spin.max_value = 600
	_ftp_spin.step = 5
	_ftp_spin.value = CyclingInputManager.rider_ftp_watts
	_ftp_spin.custom_minimum_size = Vector2(200, 50)
	right.add_child(_ftp_spin)
	_label(right, "Cycling input", 22, COL_DIM)
	_input_option = OptionButton.new()
	_input_option.add_item("Keyboard (simulated - development)", CyclingInputManager.InputMode.KEYBOARD)
	_input_option.add_item("Smart trainer (Bluetooth via trainer bridge)", CyclingInputManager.InputMode.TRAINER)
	_input_option.select(_input_option.get_item_index(CyclingInputManager.input_mode))
	_input_option.custom_minimum_size = Vector2(360, 50)
	_input_option.add_theme_font_size_override("font_size", 20)
	_input_option.item_selected.connect(_on_input_selected)
	right.add_child(_input_option)
	_input_status = _label(right, "", 20, COL_DIM)
	_label(right, "Port", 22, COL_DIM)
	_port_spin = SpinBox.new()
	_port_spin.min_value = 1024
	_port_spin.max_value = 65535
	_port_spin.value = MultiplayerManager.DEFAULT_PORT
	_port_spin.custom_minimum_size = Vector2(200, 50)
	right.add_child(_port_spin)

	var help_gap := Control.new()
	help_gap.custom_minimum_size = Vector2(0, 20)
	right.add_child(help_gap)
	_label(right, "HOW TO PLAY", 30, COL_TEXT)
	var help := _label(right, "Your pedalling is your controller. Keep your speed up -\n" +
		"the horde follows the slowest rider, so stick together.\n" +
		"At the locked gate, everyone pedals to wind it open.\n\n" +
		"DEVELOPMENT - simulated trainer (keyboard):\n" +
		"  1-5   steady effort (recovery ... all-out)    0   stop pedalling\n" +
		"  W / Up   hold to push harder    Space   sprint    S / Down   stop", 20, COL_DIM)
	help.autowrap_mode = TextServer.AUTOWRAP_OFF


func _process(_delta: float) -> void:
	# Live input status, so you can check the trainer works before riding.
	var src := CyclingInputManager.source
	if src is TrainerBridgeInput:
		if CyclingInputManager.is_input_valid():
			_input_status.text = "%s:  %d W   %d rpm" % [CyclingInputManager.get_source_name(),
				roundi(CyclingInputManager.get_power_watts()), maxi(roundi(CyclingInputManager.get_cadence_rpm()), 0)]
			_input_status.label_settings.font_color = Color(0.45, 1.0, 0.5)
		else:
			_input_status.text = "No trainer data. Run tools/trainer_bridge/start_bridge.bat\nand pedal to wake the trainer."
			_input_status.label_settings.font_color = Color(1.0, 0.6, 0.3)
	else:
		_input_status.text = "Keys: 1-5 effort, W push, Space sprint (see below)"
		_input_status.label_settings.font_color = COL_DIM


func _on_input_selected(index: int) -> void:
	CyclingInputManager.set_input_mode(_input_option.get_item_id(index) as CyclingInputManager.InputMode)
	CyclingInputManager.save_settings()


func _save_profile() -> void:
	CyclingInputManager.rider_name = _name_edit.text.strip_edges() if _name_edit.text.strip_edges() != "" else "Rider"
	CyclingInputManager.rider_ftp_watts = _ftp_spin.value
	CyclingInputManager.save_settings()


func _on_solo() -> void:
	_save_profile()
	MultiplayerManager.start_solo()


func _on_host() -> void:
	_save_profile()
	var port := int(_port_spin.value)
	var err := MultiplayerManager.host_game(port)
	if err != OK:
		_message.text = "Could not host on port %d (error %d). Is it already in use?" % [port, err]
		return
	var ips := []
	for ip in IP.get_local_addresses():
		if ip.count(".") == 3 and not ip.begins_with("127.") and not ip.begins_with("169.254"):
			ips.append(ip)
	_show_lobby("Hosting on port %d. Other players join using one of:\n%s" % [port, ", ".join(ips) if ips.size() > 0 else "127.0.0.1 (this computer)"])
	_refresh_lobby()


func _on_join() -> void:
	_save_profile()
	var err := MultiplayerManager.join_game(_ip_edit.text.strip_edges(), int(_port_spin.value))
	if err != OK:
		_message.text = "Could not start connection (error %d)." % err
		return
	_show_lobby("Connecting to %s..." % _ip_edit.text)


func _on_connected() -> void:
	_lobby_status.text = "Connected! Waiting for the host to start the mission."


func _on_connection_failed(reason: String) -> void:
	_show_main()
	_message.text = reason


func _on_leave() -> void:
	MultiplayerManager.leave()
	_show_main()


func _show_lobby(status: String) -> void:
	_main_box.visible = false
	_lobby_box.visible = true
	_lobby_status.text = status
	_lobby_start.visible = MultiplayerManager.is_host()
	_message.text = ""
	_refresh_lobby()


func _show_main() -> void:
	_main_box.visible = true
	_lobby_box.visible = false


func _refresh_lobby() -> void:
	var lines := []
	for id: int in MultiplayerManager.get_roster():
		lines.append("- %s%s" % [MultiplayerManager.get_player_name(id), "  (host)" if id == 1 else ""])
	_lobby_players.text = "\n".join(lines) if lines.size() > 0 else "-"
	_lobby_start.disabled = MultiplayerManager.get_roster().size() < 1
