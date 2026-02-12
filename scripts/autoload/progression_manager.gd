extends Node
## ProgressionManager - Contextual objectives, round tier milestones, and achievements

signal objective_changed(text: String, target: Node)
signal tier_changed(tier_name: String, tier_color: Color)
signal achievement_unlocked(achievement_name: String, description: String)

# --- Round Tier Definitions ---
const TIERS: Array[Dictionary] = [
	{"name": "THE BEGINNING", "min_round": 1, "max_round": 4, "color": Color.WHITE},
	{"name": "FIRST BLOOD", "min_round": 5, "max_round": 9, "color": Color.YELLOW},
	{"name": "INTO THE DARK", "min_round": 10, "max_round": 14, "color": Color.ORANGE},
	{"name": "NO MERCY", "min_round": 15, "max_round": 19, "color": Color.RED},
	{"name": "ENDLESS NIGHT", "min_round": 20, "max_round": 999, "color": Color(0.7, 0.3, 1.0)},
]

# --- Achievement Definitions ---
const ACHIEVEMENTS: Dictionary = {
	"FIRST BLOOD": {"desc": "Kill your first zombie", "unlocked": false},
	"HEADHUNTER": {"desc": "Get your first headshot", "unlocked": false},
	"LOCKED AND LOADED": {"desc": "Purchase a weapon", "unlocked": false},
	"JUICED UP": {"desc": "Purchase a perk", "unlocked": false},
	"POWER ON": {"desc": "Activate the power switch", "unlocked": false},
	"PACK A PUNCH": {"desc": "Upgrade a weapon", "unlocked": false},
	"DECIMATOR": {"desc": "Kill 100 zombies in one game", "unlocked": false},
	"UNTOUCHABLE": {"desc": "Complete a round without taking damage", "unlocked": false},
	"BOSS SLAYER": {"desc": "Kill a Tank zombie", "unlocked": false},
	"SURVIVOR": {"desc": "Reach round 10", "unlocked": false},
	"VETERAN": {"desc": "Reach round 20", "unlocked": false},
}

# State
var current_tier_index: int = -1
var current_objective: String = ""
var current_objective_target: Node = null
var session_kills: int = 0
var session_headshots: int = 0
var took_damage_this_round: bool = false
var unlocked_achievements: Dictionary = {}  # name -> true
var local_player: Node = null

# Refresh timer
var objective_timer: float = 0.0
const OBJECTIVE_REFRESH_INTERVAL := 5.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Connect to GameManager signals
	GameManager.round_started.connect(_on_round_started)
	GameManager.round_ended.connect(_on_round_ended)
	GameManager.zombie_killed.connect(_on_zombie_killed)
	GameManager.power_activated.connect(_on_power_activated)


func _process(delta: float) -> void:
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return

	# Find local player if needed
	if not local_player or not is_instance_valid(local_player):
		_find_local_player()

	# Periodic objective refresh
	objective_timer += delta
	if objective_timer >= OBJECTIVE_REFRESH_INTERVAL:
		objective_timer = 0.0
		_evaluate_objective()

	# Update tier progress every frame (cheap)
	_check_kill_achievements()


func _find_local_player() -> void:
	var tree := get_tree()
	if not tree or not tree.current_scene:
		return
	var players_node := tree.current_scene.get_node_or_null("Players")
	if not players_node:
		return

	var local_id := multiplayer.get_unique_id()
	for player in players_node.get_children():
		if player.get("player_id") == local_id:
			local_player = player
			_connect_player_signals()
			break


func _connect_player_signals() -> void:
	if not local_player:
		return

	if local_player.has_signal("perk_acquired") and not local_player.perk_acquired.is_connected(_on_perk_acquired):
		local_player.perk_acquired.connect(_on_perk_acquired)

	if local_player.has_signal("weapon_changed") and not local_player.weapon_changed.is_connected(_on_weapon_changed):
		local_player.weapon_changed.connect(_on_weapon_changed)

	if local_player.has_signal("health_changed") and not local_player.health_changed.is_connected(_on_health_changed):
		local_player.health_changed.connect(_on_health_changed)


# --- Round Events ---

func _on_round_started(round_number: int) -> void:
	took_damage_this_round = false
	_update_tier(round_number)
	_evaluate_objective()

	# Round milestone achievements
	if round_number >= 10:
		_try_unlock("SURVIVOR")
	if round_number >= 20:
		_try_unlock("VETERAN")


func _on_round_ended(round_number: int) -> void:
	# Untouchable check
	if not took_damage_this_round and round_number >= 1:
		_try_unlock("UNTOUCHABLE")

	_evaluate_objective()


# --- Kill Tracking ---

func _on_zombie_killed(zombie: Node, killer_id: int, _points: int) -> void:
	# Only track for local player
	if not local_player or killer_id != local_player.get("player_id"):
		return

	session_kills += 1

	# First kill
	if session_kills == 1:
		_try_unlock("FIRST BLOOD")

	# Check headshot from stats
	if local_player.get("player_id") in GameManager.player_stats:
		var stats: Dictionary = GameManager.player_stats[local_player.get("player_id")]
		var hs: int = stats.get("headshots", 0)
		if hs > session_headshots:
			session_headshots = hs
			_try_unlock("HEADHUNTER")

	# Tank kill
	if zombie and is_instance_valid(zombie):
		var enemy_type: String = zombie.get("enemy_type") if zombie.get("enemy_type") else ""
		if enemy_type == "tank":
			_try_unlock("BOSS SLAYER")

	_evaluate_objective()


func _check_kill_achievements() -> void:
	if session_kills >= 100:
		_try_unlock("DECIMATOR")


# --- Player Events ---

func _on_perk_acquired(_perk_name: String) -> void:
	_try_unlock("JUICED UP")
	_evaluate_objective()


func _on_weapon_changed(_weapon: Node) -> void:
	# Check if this is a purchased weapon (not starting pistol)
	if local_player and local_player.get("weapons"):
		var weapons: Array = local_player.weapons
		if weapons.size() > 1:
			_try_unlock("LOCKED AND LOADED")
	_evaluate_objective()


func _on_health_changed(new_health: int, _max_health: int) -> void:
	if local_player and new_health < local_player.get("max_health"):
		took_damage_this_round = true


func _on_power_activated() -> void:
	_try_unlock("POWER ON")
	_evaluate_objective()


# --- Tier System ---

func _update_tier(round_number: int) -> void:
	var new_tier_index := _get_tier_index(round_number)
	if new_tier_index != current_tier_index:
		current_tier_index = new_tier_index
		var tier: Dictionary = TIERS[current_tier_index]
		tier_changed.emit(tier["name"], tier["color"])


func _get_tier_index(round_number: int) -> int:
	for i in TIERS.size():
		var tier: Dictionary = TIERS[i]
		if round_number >= tier["min_round"] and round_number <= tier["max_round"]:
			return i
	return TIERS.size() - 1


func get_tier_progress() -> float:
	if current_tier_index < 0 or current_tier_index >= TIERS.size():
		return 0.0

	var tier: Dictionary = TIERS[current_tier_index]
	var min_r: int = tier["min_round"]
	var max_r: int = tier["max_round"]
	var current_r: int = GameManager.current_round

	if max_r >= 999:
		# Endless tier - show progress every 5 rounds
		return fmod(float(current_r - min_r), 5.0) / 5.0 * 100.0

	var range_size: int = max_r - min_r + 1
	var progress: float = float(current_r - min_r) / float(range_size) * 100.0
	return clampf(progress, 0.0, 100.0)


# --- Contextual Objective System ---

func _evaluate_objective() -> void:
	var new_objective := ""
	var new_target: Node = null
	var round_num := GameManager.current_round

	if round_num == 0:
		_set_objective("", null)
		return

	# Boss round active
	if GameManager.is_boss_round() and GameManager.zombies_remaining > 0:
		new_objective = "Defeat the Tank!"
		_set_objective(new_objective, null)
		return

	# Between rounds
	if GameManager.zombies_remaining <= 0 and round_num >= 1:
		new_objective = "Prepare for Round %d" % (round_num + 1)
		_set_objective(new_objective, null)
		return

	# Round 1: basic survival
	if round_num == 1:
		new_objective = "Survive Round 1"
		_set_objective(new_objective, null)
		return

	# No good weapon (only starting pistol), round 2+
	if local_player and is_instance_valid(local_player):
		var weapons: Array = local_player.get("weapons") if local_player.get("weapons") else []
		var has_good_weapon := false
		for w: Node in weapons:
			var wid: String = w.get("weapon_id") if w.get("weapon_id") else ""
			if wid != "" and wid != "m1911":
				has_good_weapon = true
				break

		if not has_good_weapon and round_num >= 2:
			new_objective = "Find a better weapon"
			_set_objective(new_objective, _find_nearest_weapon_source())
			return

		# Power off, round 3+
		if not GameManager.power_is_on and round_num >= 3:
			var power_switch := _find_node_in_group("power_switch")
			new_objective = "Turn on the Power"
			_set_objective(new_objective, power_switch)
			return

		# Power on, no perks
		var perks: Array = local_player.get("perks") if local_player.get("perks") else []
		if GameManager.power_is_on and perks.is_empty():
			new_objective = "Buy a Perk"
			_set_objective(new_objective, _find_nearest_perk_machine())
			return

		# Has weapon + perks, no PaP
		if has_good_weapon and not perks.is_empty() and GameManager.power_is_on:
			var pap := _find_node_in_group("pack_a_punch")
			if pap:
				new_objective = "Upgrade at Pack-a-Punch"
				_set_objective(new_objective, pap)
				return

	# High rounds
	if round_num >= 15:
		new_objective = "Hold the line!"
		_set_objective(new_objective, null)
		return

	# Default: survive
	new_objective = "Survive Round %d" % round_num
	_set_objective(new_objective, null)


func _set_objective(text: String, target: Node) -> void:
	if text != current_objective:
		current_objective = text
		current_objective_target = target
		objective_changed.emit(text, target)


func _find_node_in_group(group_name: String) -> Node:
	var nodes := get_tree().get_nodes_in_group(group_name)
	if nodes.is_empty():
		# Also search interactables by name
		var interactables := get_tree().get_nodes_in_group("interactables")
		for node: Node in interactables:
			if group_name.replace("_", "") in node.name.to_lower().replace("_", ""):
				return node
		return null
	return nodes[0]


func _find_nearest_weapon_source() -> Node:
	if not local_player or not is_instance_valid(local_player):
		return null

	var player_pos: Vector3 = local_player.global_position
	var nearest: Node = null
	var nearest_dist := INF

	var interactables := get_tree().get_nodes_in_group("interactables")
	for node: Node in interactables:
		var node_name := node.name.to_lower()
		if "weapon" in node_name or "wall" in node_name or "mystery" in node_name or "box" in node_name:
			var dist := player_pos.distance_to(node.global_position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest = node

	return nearest


func _find_nearest_perk_machine() -> Node:
	if not local_player or not is_instance_valid(local_player):
		return null

	var player_pos: Vector3 = local_player.global_position
	var nearest: Node = null
	var nearest_dist := INF

	var interactables := get_tree().get_nodes_in_group("interactables")
	for node: Node in interactables:
		if node is PerkMachine or "perk" in node.name.to_lower():
			var dist := player_pos.distance_to(node.global_position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest = node

	return nearest


# --- Achievement System ---

func _try_unlock(achievement_name: String) -> void:
	if achievement_name in unlocked_achievements:
		return

	if achievement_name not in ACHIEVEMENTS:
		return

	unlocked_achievements[achievement_name] = true
	var desc: String = ACHIEVEMENTS[achievement_name]["desc"]
	achievement_unlocked.emit(achievement_name, desc)


# --- Reset ---

func reset() -> void:
	current_tier_index = -1
	current_objective = ""
	current_objective_target = null
	session_kills = 0
	session_headshots = 0
	took_damage_this_round = false
	unlocked_achievements.clear()
	local_player = null
	objective_timer = 0.0
