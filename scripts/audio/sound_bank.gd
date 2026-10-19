class_name SoundBank
extends RefCounted
## Finds recorded sound files by name in res://audio/.
##
## A sound "id" maps to every file named <id>.ogg/.wav/.mp3 or <id>_<n>.ogg/... in
## any folder under res://audio/, e.g. groan_1.ogg, groan_2.ogg, groan_3.ogg.
## When there are several, a random one is picked each time, so repeated
## sounds don't feel canned. To change a sound, just replace or add files;
## no code changes needed. Credits for every file are in audio/CREDITS.md.

const ROOT := "res://audio"
const EXTENSIONS := ["ogg", "wav", "mp3"]

static var _index: Dictionary = {}  # id -> Array[String] of paths
static var _loaded: Dictionary = {}  # path -> AudioStream
static var _indexed := false


## All recordings for this id (empty if there are none).
static func get_variants(id: String) -> Array[AudioStream]:
	_ensure_index()
	var result: Array[AudioStream] = []
	for path: String in _index.get(id, []):
		if not _loaded.has(path):
			_loaded[path] = load(path)
		if _loaded[path]:
			result.append(_loaded[path])
	return result


## A random recording for this id, or null if there is none.
static func pick(id: String) -> AudioStream:
	var variants := get_variants(id)
	return variants[randi() % variants.size()] if variants.size() > 0 else null


static func has(id: String) -> bool:
	_ensure_index()
	return _index.has(id)


static func clear_cache() -> void:
	_loaded.clear()


static func _ensure_index() -> void:
	if _indexed:
		return
	_indexed = true
	_scan(ROOT)


static func _scan(dir_path: String) -> void:
	# ResourceLoader.list_directory also works inside exported games, where the
	# original files are replaced by imported versions.
	for entry in ResourceLoader.list_directory(dir_path):
		if entry.ends_with("/"):
			_scan(dir_path.path_join(entry.trim_suffix("/")))
			continue
		if entry.get_extension().to_lower() not in EXTENSIONS:
			continue
		var base := entry.get_basename()
		# groan_2 -> groan ; wind_loop -> wind_loop
		var parts := base.rsplit("_", true, 1)
		var id := parts[0] if parts.size() == 2 and parts[1].is_valid_int() else base
		if not _index.has(id):
			_index[id] = []
		_index[id].append(dir_path.path_join(entry))
