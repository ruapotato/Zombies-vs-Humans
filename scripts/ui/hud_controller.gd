extends Control
## HUD controller - manages all HUD elements

@onready var round_label: Label = $TopLeft/RoundLabel
@onready var tier_label: Label = $TopLeft/TierLabel
@onready var tier_progress: ProgressBar = $TopLeft/TierProgress
@onready var zombies_label: Label = $TopLeft/ZombiesLabel
@onready var fps_label: Label = $TopLeft/FPSLabel
@onready var power_up_container: HBoxContainer = $TopRight/PowerUpContainer
@onready var perks_container: HBoxContainer = $BottomLeft/PerksContainer
@onready var points_label: Label = $BottomRight/PointsLabel
@onready var weapon_name: Label = $BottomRight/WeaponInfo/WeaponName
@onready var ammo_label: Label = $BottomRight/WeaponInfo/AmmoLabel
@onready var interaction_prompt: Label = $Center/InteractionPrompt
@onready var announcement_label: Label = $AnnouncementLabel
@onready var damage_overlay: ColorRect = $DamageOverlay
@onready var downed_overlay: ColorRect = $DownedOverlay
@onready var bleedout_timer_label: Label = $DownedOverlay/BleedoutTimer
@onready var minimap: Control = $Minimap
@onready var objective_icon: Label = $ObjectiveTracker/ObjectiveIcon
@onready var objective_text: Label = $ObjectiveTracker/ObjectiveText
@onready var achievement_popup: PanelContainer = $AchievementPopup
@onready var achievement_title: Label = $AchievementPopup/AchievementVBox/AchievementTitle
@onready var achievement_desc: Label = $AchievementPopup/AchievementVBox/AchievementDesc

var local_player: Node = null
var active_power_up_icons: Dictionary = {}

# Achievement popup queue
var achievement_queue: Array[Dictionary] = []
var is_showing_achievement: bool = false

# Perk icon colors
const PERK_COLORS: Dictionary = {
	"juggernog": Color(1, 0.3, 0.3),
	"speed_cola": Color(0.3, 1, 0.3),
	"double_tap": Color(1, 1, 0.3),
	"quick_revive": Color(0.3, 0.7, 1),
	"stamin_up": Color(1, 0.8, 0.3),
	"phd_flopper": Color(0.6, 0.3, 1),
	"deadshot": Color(0.3, 0.3, 0.3),
	"mule_kick": Color(0.5, 1, 0.5),
	"spring_heels": Color(0.3, 1, 1)
}


func _ready() -> void:
	# Connect to game signals
	GameManager.round_started.connect(_on_round_started)
	GameManager.round_ended.connect(_on_round_ended)
	GameManager.power_up_collected.connect(_on_power_up_collected)

	# Connect to progression signals
	var pm := get_node_or_null("/root/ProgressionManager")
	if pm:
		pm.objective_changed.connect(_on_objective_changed)
		pm.tier_changed.connect(_on_tier_changed)
		pm.achievement_unlocked.connect(_on_achievement_unlocked)

	# Find local player when spawned
	_find_local_player()


func _process(_delta: float) -> void:
	# Always update FPS
	if fps_label:
		fps_label.text = "FPS: %d" % Engine.get_frames_per_second()

	# Always update global game state (doesn't need player)
	_update_zombies_count()
	_update_active_power_ups()

	if not local_player:
		_find_local_player()
		return

	_update_interaction_prompt()
	_update_downed_state()


func _find_local_player() -> void:
	var players_node := get_tree().current_scene.get_node_or_null("Players")
	if not players_node:
		return

	var local_id := multiplayer.get_unique_id()

	for player in players_node.get_children():
		if player.player_id == local_id:
			local_player = player
			_connect_player_signals()
			_update_all()
			# Pass player to minimap
			if minimap and minimap.has_method("set_local_player"):
				minimap.set_local_player(local_player)
			break


func _connect_player_signals() -> void:
	if not local_player:
		return

	local_player.health_changed.connect(_on_health_changed)
	local_player.points_changed.connect(_on_points_changed)
	local_player.weapon_changed.connect(_on_weapon_changed)
	local_player.perk_acquired.connect(_on_perk_acquired)
	local_player.perk_lost.connect(_on_perk_lost)
	local_player.downed.connect(_on_player_downed)
	local_player.revived.connect(_on_player_revived)

	# Connect damage intensity signal for CoD-style red screen
	if local_player.has_signal("damage_intensity_changed"):
		local_player.damage_intensity_changed.connect(_on_damage_intensity_changed)

	# Connect weapon ammo signal
	var weapon: Node = local_player.get_current_weapon()
	if weapon:
		weapon.ammo_changed.connect(_on_ammo_changed)


func _update_all() -> void:
	if not local_player:
		return

	_on_health_changed(local_player.health, local_player.max_health)
	_on_points_changed(local_player.points)
	_on_weapon_changed(local_player.get_current_weapon())
	_update_perks()


func _on_round_started(round_number: int) -> void:
	round_label.text = "Round %d" % round_number
	_show_announcement("ROUND %d" % round_number, Color.WHITE)


func _on_round_ended(round_number: int) -> void:
	_show_announcement("ROUND %d COMPLETE" % round_number, Color.GREEN)


func _on_health_changed(_new_health: int, _max_health: int) -> void:
	# Health bar removed - using CoD-style red screen instead
	pass


func _on_damage_intensity_changed(intensity: float) -> void:
	# Update red screen overlay - intensity 0-1 maps to alpha 0-0.6
	if damage_overlay:
		damage_overlay.color.a = intensity * 0.6


func _on_points_changed(new_points: int) -> void:
	points_label.text = str(new_points)

	# Flash effect
	var tween := create_tween()
	tween.tween_property(points_label, "modulate", Color.YELLOW, 0.1)
	tween.tween_property(points_label, "modulate", Color.WHITE, 0.2)


func _on_weapon_changed(weapon: Node) -> void:
	if not weapon:
		weapon_name.text = "No Weapon"
		ammo_label.text = "- / -"
		return

	weapon_name.text = weapon.display_name

	# Connect ammo signal if not already connected
	if not weapon.ammo_changed.is_connected(_on_ammo_changed):
		weapon.ammo_changed.connect(_on_ammo_changed)
	_on_ammo_changed(weapon.current_ammo, weapon.reserve_ammo)


func _on_ammo_changed(current_ammo: int, reserve_ammo: int) -> void:
	ammo_label.text = "%d / %d" % [current_ammo, reserve_ammo]

	# Color based on ammo
	if current_ammo == 0:
		ammo_label.modulate = Color.RED
	elif current_ammo <= 5:
		ammo_label.modulate = Color.YELLOW
	else:
		ammo_label.modulate = Color.WHITE


func _on_perk_acquired(perk_name: String) -> void:
	_update_perks()
	_show_announcement(_get_perk_display_name(perk_name), PERK_COLORS.get(perk_name, Color.WHITE))


func _on_perk_lost(perk_name: String) -> void:
	_update_perks()


func _update_perks() -> void:
	# Clear existing
	for child in perks_container.get_children():
		child.queue_free()

	if not local_player:
		return

	# Add perk icons
	for perk_name in local_player.perks:
		var icon := _create_perk_icon(perk_name)
		perks_container.add_child(icon)


func _create_perk_icon(perk_name: String) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(40, 40)

	var color_rect := ColorRect.new()
	color_rect.color = PERK_COLORS.get(perk_name, Color.WHITE)
	color_rect.custom_minimum_size = Vector2(40, 40)
	panel.add_child(color_rect)

	var label := Label.new()
	label.text = perk_name.substr(0, 1).to_upper()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(label)

	return panel


func _get_perk_display_name(perk_name: String) -> String:
	var names := {
		"juggernog": "JUGGERNOG",
		"speed_cola": "SPEED COLA",
		"double_tap": "DOUBLE TAP",
		"quick_revive": "QUICK REVIVE",
		"stamin_up": "STAMIN-UP",
		"phd_flopper": "PHD FLOPPER",
		"deadshot": "DEADSHOT",
		"mule_kick": "MULE KICK",
		"spring_heels": "SPRING HEELS"
	}
	return names.get(perk_name, perk_name.to_upper())


func _on_power_up_collected(power_up_type: String, _player_id: int) -> void:
	var names := {
		"max_ammo": "MAX AMMO!",
		"insta_kill": "INSTA-KILL!",
		"double_points": "DOUBLE POINTS!",
		"nuke": "NUKE!",
		"carpenter": "CARPENTER!",
		"fire_sale": "FIRE SALE!"
	}

	var colors := {
		"max_ammo": Color.GREEN,
		"insta_kill": Color.WHITE,
		"double_points": Color.YELLOW,
		"nuke": Color.ORANGE,
		"carpenter": Color(0.6, 0.4, 0.2),
		"fire_sale": Color.RED
	}

	_show_announcement(names.get(power_up_type, power_up_type.to_upper()), colors.get(power_up_type, Color.WHITE))


func _update_active_power_ups() -> void:
	# Update power-up indicator icons
	var active_types := ["insta_kill", "double_points", "fire_sale"]

	for power_up_type in active_types:
		var is_active := GameManager.is_power_up_active(power_up_type)

		if is_active and power_up_type not in active_power_up_icons:
			var icon := _create_power_up_icon(power_up_type)
			power_up_container.add_child(icon)
			active_power_up_icons[power_up_type] = icon

		elif not is_active and power_up_type in active_power_up_icons:
			active_power_up_icons[power_up_type].queue_free()
			active_power_up_icons.erase(power_up_type)


func _create_power_up_icon(power_up_type: String) -> Control:
	var label := Label.new()

	match power_up_type:
		"insta_kill":
			label.text = "INSTA-KILL"
			label.modulate = Color.WHITE
		"double_points":
			label.text = "2X POINTS"
			label.modulate = Color.YELLOW
		"fire_sale":
			label.text = "FIRE SALE"
			label.modulate = Color.RED

	# Pulsing animation - loop for power-up duration
	var tween := label.create_tween()
	tween.set_loops(30)  # 30 loops = 30 seconds, matches power-up duration
	tween.tween_property(label, "modulate:a", 0.5, 0.5)
	tween.tween_property(label, "modulate:a", 1.0, 0.5)

	return label


func _update_interaction_prompt() -> void:
	if not local_player:
		interaction_prompt.text = ""
		return

	# Check for revive prompt first
	if local_player.has_method("get_nearby_downed_player"):
		var downed_player: Node = local_player.get_nearby_downed_player()
		if downed_player:
			var downed_name: String = downed_player.player_name if downed_player.player_name else "Player"
			if local_player._reviving_target == downed_player:
				var progress := int(downed_player.revive_progress / downed_player.REVIVE_TIME * 100)
				interaction_prompt.text = "Reviving %s... %d%%" % [downed_name, progress]
			else:
				interaction_prompt.text = "Hold [F] to Revive %s" % downed_name
			return

	var interaction_ray: RayCast3D = local_player.get_node_or_null("CameraMount/Camera3D/InteractionRay")
	if not interaction_ray or not interaction_ray.is_colliding():
		interaction_prompt.text = ""
		return

	var collider := interaction_ray.get_collider()
	if collider and collider.has_method("get_prompt"):
		interaction_prompt.text = collider.get_prompt(local_player)
	elif collider and collider.get_parent() and collider.get_parent().has_method("get_prompt"):
		interaction_prompt.text = collider.get_parent().get_prompt(local_player)
	else:
		interaction_prompt.text = ""


func _update_zombies_count() -> void:
	# Get active zombie count from the scene
	var active_count := 0
	var zombies_node := get_tree().current_scene.get_node_or_null("Zombies")
	if zombies_node:
		active_count = zombies_node.get_child_count()

	zombies_label.text = "Zombies: %d  Active: %d" % [GameManager.zombies_remaining, active_count]


func _update_downed_state() -> void:
	if not local_player:
		downed_overlay.visible = false
		return

	downed_overlay.visible = local_player.is_downed

	if local_player.is_downed:
		bleedout_timer_label.text = str(int(local_player.bleedout_timer))


func _on_player_downed() -> void:
	downed_overlay.visible = true


func _on_player_revived() -> void:
	downed_overlay.visible = false


func _show_announcement(text: String, color: Color = Color.WHITE) -> void:
	announcement_label.text = text
	announcement_label.modulate = color
	announcement_label.visible = true

	var tween := create_tween()
	tween.tween_property(announcement_label, "modulate:a", 1.0, 0.2)
	tween.tween_interval(2.0)
	tween.tween_property(announcement_label, "modulate:a", 0.0, 0.5)
	tween.tween_callback(func(): announcement_label.visible = false)


# --- Progression UI Handlers ---

func _on_objective_changed(text: String, target: Node) -> void:
	if objective_text:
		objective_text.text = text
		# Pulse effect on change
		if text != "":
			var tween := create_tween()
			tween.tween_property(objective_text, "modulate:a", 0.4, 0.1)
			tween.tween_property(objective_text, "modulate:a", 1.0, 0.3)
	# Forward target to minimap
	if minimap and minimap.has_method("set_objective_target"):
		minimap.set_objective_target(target)


func _on_tier_changed(tier_name: String, tier_color: Color) -> void:
	if tier_label:
		tier_label.text = tier_name
		tier_label.add_theme_color_override("font_color", tier_color)

	# Dramatic announcement
	_show_announcement(tier_name, tier_color)

	# Scale-up animation on round label
	if round_label:
		var tween := create_tween()
		tween.tween_property(round_label, "scale", Vector2(1.3, 1.3), 0.2)
		tween.tween_property(round_label, "scale", Vector2(1.0, 1.0), 0.3)

	# Update tier progress
	_update_tier_progress()


func _update_tier_progress() -> void:
	var pm := get_node_or_null("/root/ProgressionManager")
	if pm and tier_progress:
		tier_progress.value = pm.get_tier_progress()


func _on_achievement_unlocked(achievement_name: String, description: String) -> void:
	achievement_queue.append({"name": achievement_name, "desc": description})
	if not is_showing_achievement:
		_show_next_achievement()


func _show_next_achievement() -> void:
	if achievement_queue.is_empty():
		is_showing_achievement = false
		return

	is_showing_achievement = true
	var ach: Dictionary = achievement_queue.pop_front()

	achievement_title.text = ach["name"]
	achievement_desc.text = ach["desc"]

	# Slide in from right
	achievement_popup.visible = true
	achievement_popup.modulate.a = 0.0
	var start_offset := achievement_popup.position.x
	achievement_popup.position.x = start_offset + 300

	var tween := create_tween()
	tween.tween_property(achievement_popup, "position:x", start_offset, 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.parallel().tween_property(achievement_popup, "modulate:a", 1.0, 0.3)
	tween.tween_interval(3.0)
	tween.tween_property(achievement_popup, "position:x", start_offset + 300, 0.3).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(achievement_popup, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func():
		achievement_popup.visible = false
		achievement_popup.position.x = start_offset
		_show_next_achievement()
	)
