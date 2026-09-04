extends Node2D
## Root scene: deployment (drag units + set doctrine), then the battle (with
## a general retreat order the player can give at any time), then the AAR
## report with a restart so you can change doctrine and try again.

var deployment_screen: DeploymentScreen
var doctrine_panel: DoctrinePanel
var start_button: Button

var battle_manager: BattleManager
var combat_log: CombatLog
var retreat_button: Button

var report_background: Control
var restart_button: Button


func _ready() -> void:
	_show_deployment()


func _clear_all() -> void:
	for node in [deployment_screen, doctrine_panel, start_button, battle_manager,
			combat_log, retreat_button, report_background, restart_button]:
		if node:
			node.queue_free()
	deployment_screen = null
	doctrine_panel = null
	start_button = null
	battle_manager = null
	combat_log = null
	retreat_button = null
	report_background = null
	restart_button = null


func _show_deployment() -> void:
	_clear_all()

	deployment_screen = DeploymentScreen.new()
	add_child(deployment_screen)

	doctrine_panel = DoctrinePanel.new()
	doctrine_panel.position = Vector2(1020, 20)
	add_child(doctrine_panel)

	start_button = Button.new()
	start_button.text = "Start Battle"
	start_button.position = Vector2(1020, 540)
	start_button.pressed.connect(_on_start_pressed)
	add_child(start_button)


func _on_start_pressed() -> void:
	var positions := deployment_screen.get_positions()
	var thresholds := doctrine_panel.get_squad_retreat_thresholds()

	var squads: Array[Dictionary] = []
	for i in positions.squad_positions.size():
		squads.append({
			"position": positions.squad_positions[i],
			"retreat_threshold": thresholds[i],
		})

	var mortar_doctrine := doctrine_panel.get_mortar_doctrine()
	mortar_doctrine["position"] = positions.mortar_position

	var doctrine := {
		"squads": squads,
		"mortar": mortar_doctrine,
	}

	deployment_screen.queue_free()
	deployment_screen = null
	doctrine_panel.queue_free()
	doctrine_panel = null
	start_button.queue_free()
	start_button = null

	combat_log = CombatLog.new()
	combat_log.position = Vector2(1020, 60)
	add_child(combat_log)

	retreat_button = Button.new()
	retreat_button.text = "Order General Retreat"
	retreat_button.position = Vector2(1020, 20)
	retreat_button.pressed.connect(_on_retreat_pressed)
	add_child(retreat_button)

	battle_manager = BattleManager.new()
	battle_manager.battle_ended.connect(_on_battle_ended)
	add_child(battle_manager)
	battle_manager.start_battle(doctrine, combat_log)


func _on_retreat_pressed() -> void:
	if battle_manager:
		battle_manager.order_general_retreat()


func _on_battle_ended(report_text: String) -> void:
	if retreat_button:
		retreat_button.queue_free()
		retreat_button = null

	report_background = ColorRect.new()
	report_background.color = Color(0.05, 0.05, 0.05, 0.85)
	report_background.position = Vector2(20, 20)
	report_background.size = Vector2(560, 500)
	add_child(report_background)

	var report_label := Label.new()
	report_label.text = report_text
	report_label.position = Vector2(10, 10)
	report_label.custom_minimum_size = Vector2(540, 480)
	report_label.size = report_label.custom_minimum_size
	report_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	report_background.add_child(report_label)

	restart_button = Button.new()
	restart_button.text = "Set new doctrine and try again"
	restart_button.position = Vector2(20, 540)
	restart_button.pressed.connect(_show_deployment)
	add_child(restart_button)
