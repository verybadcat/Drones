extends RefCounted
class_name BattleScoreLog
const BattleScore = preload("res://scripts/battle_score.gd")
## The durable history of battle scores — the player's record of how each
## scenario has gone, kept across game restarts AND code updates.
##
## How it survives each:
##  * Restarts: it's a file, not memory, written the moment a battle ends.
##  * Code updates: it lives in Godot's per-user data folder (user://),
##    entirely outside the project, so nothing that replaces or rewrites the
##    game's own files can touch it. Each line also stores the RAW COUNTS the
##    score was computed from (not just the number), plus RUBRIC_VERSION, so
##    if the scoring rubric is ever tuned, summaries RE-SCORE the whole
##    history with the current rubric instead of mixing old and new numbers.
##    A scenario is keyed by the map's internal id (stable when a map's
##    display name changes) plus the recon mode's name.
##  * Damage: append-only, one JSON object per line (JSON Lines). A crash
##    mid-write can only ever cost the one line being written; a line that
##    can't be read is skipped, never deleted; and an append always starts
##    on a fresh line, so a previously cut-off line can't swallow the next
##    record. Nothing here ever rewrites or truncates existing history.
##
## Deliberately kept out of BattleManager: that class runs in every test and
## in the characterization harness (200 battles at a time) and must never
## write to a real player's history. Only main.gd records, at the real end of
## a real battle. `path` exists so tests (and nothing else) can point
## somewhere disposable.

const DEFAULT_PATH: String = "user://battle_scores.jsonl"
## Schema of one stored line — bump only for an incompatible change (adding a
## field isn't one: readers ignore fields they don't know).
const RECORD_VERSION: int = 1

## Where the history lives. EMPTY means "no history": record() writes nothing
## and load_records() reads nothing — how automated runs are kept from ever
## touching a real player's history (see main.gd, which empties it under a
## headless run: a precaution, since several tests drive main.gd's real
## battle-end flow).
var path: String = DEFAULT_PATH
## Lines the last load_records() couldn't use (kept in the file, just not counted).
var skipped_lines: int = 0


## Appends one finished battle. `result` is BattleManager.battle_result.
## Returns false (never throws) if it couldn't be written.
func record(result: Dictionary, map_id: String, recon_mode: String) -> bool:
	if result.is_empty() or path.is_empty():
		return false
	var line: Dictionary = {
		"v": RECORD_VERSION,
		"time_utc": Time.get_datetime_string_from_system(true),
		"map_id": map_id,
		"recon_mode": recon_mode,
		"rubric_version": result.get("rubric_version", BattleScore.RUBRIC_VERSION),
		"verdict": result.get("verdict", ""),
		"score": result.get("score", 0.0),
		"inputs": result.get("inputs", {}),
	}
	return _append_line(JSON.stringify(line))


func _append_line(text: String) -> bool:
	var f: FileAccess = null
	if FileAccess.file_exists(path):
		f = FileAccess.open(path, FileAccess.READ_WRITE)
	else:
		f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("BattleScoreLog: couldn't open %s for writing (error %d)" % [path, FileAccess.get_open_error()])
		return false
	f.seek_end()
	var length: int = f.get_position()
	if length > 0:
		f.seek(length - 1)
		var last_byte: int = f.get_8()
		f.seek_end()
		if last_byte != 10: # the file doesn't end on a line boundary (an earlier write was cut off) — never glue onto it
			f.store_8(10)
	f.store_line(text)
	f.flush()
	f.close()
	return true


## Every readable record, oldest first. Unreadable lines are skipped (and
## counted in skipped_lines), never removed from the file.
func load_records() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	skipped_lines = 0
	if path.is_empty() or not FileAccess.file_exists(path):
		return records
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return records
	while not f.eof_reached():
		var line: String = f.get_line().strip_edges()
		if line.is_empty():
			continue
		var parser := JSON.new()
		if parser.parse(line) != OK or not (parser.data is Dictionary) or not _usable(parser.data):
			skipped_lines += 1
			continue
		records.append(parser.data)
	return records


func _usable(rec: Dictionary) -> bool:
	if not (rec.get("map_id") is String) or not (rec.get("recon_mode") is String):
		return false
	var has_counts: bool = rec.get("inputs") is Dictionary and not rec.inputs.is_empty()
	return has_counts or _is_number(rec.get("score"))


static func _is_number(value) -> bool:
	return value is float or value is int


## The score of a stored battle under the CURRENT rubric: re-scored
## from its stored counts when it has them (so tuning the rubric re-scores
## history), else the number that was stored at the time.
static func rescored(rec: Dictionary) -> float:
	var inputs = rec.get("inputs")
	if inputs is Dictionary and not inputs.is_empty():
		return BattleScore.score(inputs)
	return float(rec.get("score", 0.0))


## Per-scenario summary, one entry per (map, recon mode) that has any
## history, sorted by map id then recon mode: {map_id, recon_mode, count,
## average, best, worst, latest}. All scores are the current rubric's.
static func summarize(records: Array[Dictionary]) -> Array[Dictionary]:
	var groups: Dictionary = {}
	for rec in records:
		var key: String = "%s|%s" % [rec.map_id, rec.recon_mode]
		if not groups.has(key):
			groups[key] = {"map_id": rec.map_id, "recon_mode": rec.recon_mode, "scores": []}
		groups[key].scores.append(rescored(rec))
	var out: Array[Dictionary] = []
	for key in groups:
		var scores: Array = groups[key].scores
		var total := 0.0
		for s in scores:
			total += s
		out.append({
			"map_id": groups[key].map_id,
			"recon_mode": groups[key].recon_mode,
			"count": scores.size(),
			"average": total / scores.size(),
			"best": scores.max(),
			"worst": scores.min(),
			"latest": scores[-1],
		})
	out.sort_custom(func(a, b): return a.map_id < b.map_id if a.map_id != b.map_id else a.recon_mode < b.recon_mode)
	return out


## The summary for one scenario, or an empty Dictionary if it has no history.
static func scenario_summary(records: Array[Dictionary], map_id: String, recon_mode: String) -> Dictionary:
	for entry in summarize(records):
		if entry.map_id == map_id and entry.recon_mode == recon_mode:
			return entry
	return {}
