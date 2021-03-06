extends Node

signal player_chose_targets

const UIActionMenuScene: PackedScene = preload("res://CombatSystem/UserInterface/UIActionMenu/UIActionMenu.tscn")
const SelectArrow: PackedScene = preload("res://CombatSystem/UserInterface/SelectArrow.tscn")

# Allows pausing the Active Time Battle during combat intro or a cut-scene.
var is_active := true setget set_is_active
# Multiplier for the global pace of battle, to slow down time while the player is taking decisions.
# This is meant for accessibility and to control difficulty.
var time_scale := 1.0 setget set_time_scale

# Stack of player units that have to take turns.
var _queue_player := []

var _party_members := []
var _opponents := []

onready var battlers := get_children()


func _ready() -> void:
	connect("player_chose_targets", self, "_on_player_chose_targets")
	for battler in battlers:
		battler.connect("ready_to_act", self, "_on_Battler_ready_to_act", [battler])
		if battler.is_player_controlled():
			_party_members.append(battler)
		else:
			_opponents.append(battler)


func set_is_active(value: bool) -> void:
	is_active = value
	for battler in battlers:
		battler.is_active = is_active


func set_time_scale(value: float) -> void:
	time_scale = value
	for battler in battlers:
		battler.time_scale = time_scale


func _play_turn(battler: Battler) -> void:
	battler.stats.energy += 1

	battler.is_selected = true
	var action: Action
	var targets := []
	
	var potential_targets := []
	for opponent in _opponents:
		if opponent.is_selectable:
			potential_targets.append(opponent)

	if battler.is_player_controlled():
		set_time_scale(0.05)
		var is_selection_complete := false
		# Wait for the player to select a valid action and target(s).
		while not is_selection_complete:
			action = yield(_player_select_action_async(battler.actions), "completed")
			if action.is_targetting_self:
				targets = [battler]
			else:
				targets = yield(_player_select_targets_async(action, potential_targets), "completed")
			is_selection_complete = action != null && targets != []
		set_time_scale(1.0)
		emit_signal("player_chose_targets")
	else:
		var result: Dictionary = battler.ai.choose(battler, battlers)
		action = result.action
		targets = result.targets

	battler.is_selected = false
	battler.act(action, targets)
	yield(battler, "action_finished")


func _player_select_action_async(actions: Array) -> Action:
	var action_menu: UIActionMenu = UIActionMenuScene.instance()
	add_child(action_menu)
	action_menu.open(actions)
	var action: Action = yield(action_menu, "action_selected")
	return action


func _player_select_targets_async(_action: Action, opponents: Array) -> Array:
	var arrow: SelectBattlerArrow = SelectArrow.instance()
	add_child(arrow)
	arrow.setup(opponents)
	var targets = yield(arrow, "target_selected")
	arrow.queue_free()
	return targets


func _on_player_chose_targets() -> void:
	if _queue_player != []:
		_play_turn(_queue_player.pop_front())


func _on_Battler_ready_to_act(battler: Battler) -> void:
	if battler.is_player_controlled():
		_queue_player.append(battler)
		var can_play_turn := true
		for party_member in _party_members:
			if party_member.is_selected:
				can_play_turn = false
		if can_play_turn:
			_play_turn(_queue_player.pop_front())
	else:
		_play_turn(battler)
