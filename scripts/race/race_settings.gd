class_name RaceSettings
extends RefCounted
## Criterium settings chosen on the title screen (saved on this computer).

const PATH := "user://race_settings.cfg"
const POINT_OPTIONS: Array[int] = [5, 10, 15]
const RIDER_OPTIONS: Array[int] = [3, 5, 7]
enum Difficulty { EASIER, EQUAL, HARDER }
const DIFFICULTY_NAMES := ["Easier", "Equal", "Harder"]
const DRAFT_ASSIST_NAMES := ["Draft help: off", "Draft help: normal", "Draft help: strong"]

## First to this many points wins.
static var points_to_win: int = 10
## Number of computer riders.
static var opponents: int = 7
static var difficulty: Difficulty = Difficulty.EQUAL
## Sticky-wheel draft assist: 0 off, 1 normal, 2 strong.
static var draft_assist: int = 1


static func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	points_to_win = int(cfg.get_value("race", "points_to_win", points_to_win))
	opponents = int(cfg.get_value("race", "opponents", opponents))
	difficulty = int(cfg.get_value("race", "difficulty", difficulty)) as Difficulty
	draft_assist = clampi(int(cfg.get_value("race", "draft_assist", draft_assist)), 0, 2)


static func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("race", "points_to_win", points_to_win)
	cfg.set_value("race", "opponents", opponents)
	cfg.set_value("race", "difficulty", difficulty)
	cfg.set_value("race", "draft_assist", draft_assist)
	cfg.save(PATH)
