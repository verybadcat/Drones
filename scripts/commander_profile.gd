extends RefCounted
## Game archetypes, not claims about real people or military organizations.
## Baseline deliberately keeps the original decision rules and random draws.

const IDS := ["baseline", "cautious", "aggressive", "deliberate"]
const LABELS := ["Original doctrine", "Cautious", "Aggressive", "Deliberate evaluator"]
const AXES := ["protection", "pressure", "counter_mortar", "conservation"]
const AXIS_LABELS := ["Protect the force", "Apply pressure", "Counter enemy mortars", "Conserve ammunition"]

static func preset(id: String) -> Dictionary:
	var p := {"id": id, "protection": 1.0, "pressure": 1.0,
		"counter_mortar": 1.0, "conservation": 1.0, "deterministic": false,
		"retreat_threshold": 0.30}
	match id:
		"cautious":
			p.merge({"protection": 2.5, "pressure": 0.5, "counter_mortar": 1.0,
				"conservation": 1.5, "retreat_threshold": 0.20}, true)
		"aggressive":
			p.merge({"protection": 0.5, "pressure": 2.5, "counter_mortar": 1.5,
				"conservation": 0.4, "retreat_threshold": 0.60}, true)
		"deliberate":
			p.merge({"protection": 1.5, "pressure": 1.0, "counter_mortar": 1.5,
				"deterministic": true, "retreat_threshold": 0.35}, true)
		_:
			p.id = "baseline"
	return p

static func sanitize(input: Dictionary) -> Dictionary:
	var p := preset(str(input.get("id", "baseline")))
	if p.id == "baseline":
		return p
	for axis in AXES:
		var value := float(input.get(axis, p[axis]))
		p[axis] = clampf(value, 0.1, 3.0) if is_finite(value) else p[axis]
	p.deterministic = bool(input.get("deterministic", p.deterministic))
	var threshold := float(input.get("retreat_threshold", p.retreat_threshold))
	p.retreat_threshold = clampf(threshold, 0.1, 0.9) if is_finite(threshold) else p.retreat_threshold
	return p

static func label(p: Dictionary) -> String:
	return LABELS[IDS.find(p.id)]

static func description(id: String) -> String:
	match id:
		"cautious": return "Protect nearby allies, spend ammunition carefully, withdraw earlier."
		"aggressive": return "Favor pressure, spend more ammunition, accept more losses before withdrawing."
		"deliberate": return "Choose the highest target score and use fixed hold-fire decisions. Combat and other behavior still include chance."
	return "The original rules, including absolute priority for a visible enemy mortar."
