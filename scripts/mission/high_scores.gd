class_name HighScores
extends RefCounted
## Endless Survival high-score table, saved on this computer.

## Where the table is saved (tests point this somewhere else).
static var path := "user://endless_scores.cfg"
const MAX_ENTRIES := 10


## Best runs first. Each entry: {score, distance, time, checkpoints, survivors, names, date}.
static func load_scores() -> Array:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return []
	var list: Array = cfg.get_value("scores", "list", [])
	return list.filter(func(e: Variant) -> bool: return e is Dictionary and e.has("score"))


## Adds a run and returns its rank (1 = best), or 0 if it didn't make the table.
static func add(entry: Dictionary) -> int:
	var list := load_scores()
	entry["date"] = Time.get_date_string_from_system()
	list.append(entry)
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] > b["score"])
	var rank := list.find(entry) + 1
	list = list.slice(0, MAX_ENTRIES)
	var cfg := ConfigFile.new()
	cfg.set_value("scores", "list", list)
	cfg.save(path)
	return rank if rank <= MAX_ENTRIES else 0


static func best() -> Dictionary:
	var list := load_scores()
	return list[0] if list.size() > 0 else {}
