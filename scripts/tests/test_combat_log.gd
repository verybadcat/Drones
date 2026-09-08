extends CombatLog
class_name TestCombatLog
## A CombatLog substitute for headless characterization runs — production
## code calls combat_log.add_entry(...) constantly throughout a battle,
## and CombatLog's real implementation needs its own _ready() to have
## fired (building a ScrollContainer/VBoxContainer for the on-screen log)
## before add_entry can touch it, which never happens for a node that's
## never actually added to a live scene tree. Overriding add_entry as a
## no-op sidesteps that entirely — none of this suite's metrics come from
## reading log text (see TestUnit/TestBattleManager for where they
## actually come from instead), so there's nothing to lose, and it avoids
## silently accumulating thousands of Label nodes across a long run of
## trials.
var captured: Array[String] = []

func add_entry(text: String) -> void:
	captured.append(text)
