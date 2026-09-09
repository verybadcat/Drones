extends RefCounted
## Immutable-at-capture decision evidence. Reading this never invokes AI or RNG.
const MAX_EVENTS := 2000
var events: Array[Dictionary] = []
var latest: Dictionary = {}
var _signatures: Dictionary = {}
var _unit_numbers: Dictionary = {}

func label_for(unit: Unit) -> String:
	var id := unit.get_instance_id()
	if not _unit_numbers.has(id):
		_unit_numbers[id] = _unit_numbers.size() + 1
	return "%s #%d" % [unit.display_name(), _unit_numbers[id]]

func record(unit: Unit, time: float, channel: String, data: Dictionary) -> void:
	var key := "%d:%s" % [unit.get_instance_id(), channel]
	var entry := data.duplicate(true)
	entry.merge({"unit_id": unit.get_instance_id(), "unit": label_for(unit),
		"team": int(unit.team), "time": time, "channel": channel}, true)
	latest[key] = entry
	# Store changes, not one duplicate every frame. Scores remain available
	# in the latest record; a history event captures the scores at that time.
	var signature := str(data.get("choice", "")) + "|" + str(data.get("reason", "")) + "|" + str(data.get("sequence", "")) + "|" + str(data.get("destination", {}))
	if _signatures.get(key, "") == signature:
		return
	_signatures[key] = signature
	events.append(entry.duplicate(true))
	if events.size() > MAX_EVENTS:
		events.pop_front()

func records_for(unit_id: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in latest.values():
		if entry.unit_id == unit_id:
			result.append(entry.duplicate(true))
	return result

func history_for(unit_id: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in events:
		if entry.unit_id == unit_id:
			result.append(entry.duplicate(true))
	return result
