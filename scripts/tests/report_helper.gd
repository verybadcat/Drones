extends RefCounted
## Test helper (not a test): opens a BattleReport on `main` for `battle_manager` (null is
## fine: a report with no battle behind it) the way the battle screen does at the end of a
## battle — the report records the score to main's history and shows it. The caller frees the
## report when done with it (a real one is freed with its battle screen).

static func open_report(main, battle_manager, report_text: String) -> BattleReport:
	var report := BattleReport.new()
	report.battle_manager = battle_manager
	report.map_viewport = main.map_viewport
	report.score_log = main.score_log
	report.recon_mode = main.recon_mode
	main.add_child(report)
	report.open(report_text)
	return report
