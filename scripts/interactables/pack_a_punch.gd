extends Interactable
class_name PackAPunch
## Pack-a-Punch machine - upgrades weapons

const UPGRADE_COST := 5000
const UPGRADE_TIME := 5.0
const GRAB_TIME := 10.0

enum PaPState { IDLE, UPGRADING, READY }

var pap_state: PaPState = PaPState.IDLE
var upgrading_weapon: Node = null
var upgraded_weapon_id: String = ""
var waiting_player: Node = null

@onready var upgrade_timer: Timer = $UpgradeTimer
@onready var grab_timer: Timer = $GrabTimer
@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var label: Label3D = $Label3D


func _ready() -> void:
	super._ready()

	cost = UPGRADE_COST
	requires_power = true
	one_time_use = false
	interaction_prompt = "Pack-a-Punch"


func interact(player: Node) -> bool:
	match pap_state:
		PaPState.IDLE:
			return _start_upgrade(player)

		PaPState.READY:
			if waiting_player == player:
				return _grab_weapon(player)

		_:
			return false

	return false


func _start_upgrade(player: Node) -> bool:
	if not is_usable:
		AudioManager.play_sound_ui("denied")
		return false

	if not player.can_afford(cost):
		AudioManager.play_sound_ui("denied")
		return false

	var current_weapon: Node = player.get_current_weapon()
	if not current_weapon:
		return false

	# Check if weapon is already pack-a-punched
	if current_weapon.is_pack_a_punched:
		AudioManager.play_sound_ui("denied")
		return false

	player.spend_points(cost)
	waiting_player = player

	# Take the weapon
	upgrading_weapon = current_weapon
	upgraded_weapon_id = current_weapon.weapon_id

	# Remove from player temporarily
	player.weapons.erase(current_weapon)
	current_weapon.visible = false

	pap_state = PaPState.UPGRADING

	AudioManager.play_sound_3d("pack_a_punch_start", global_position)

	upgrade_timer.wait_time = UPGRADE_TIME
	upgrade_timer.start()

	# Animation effect
	_play_upgrade_animation()

	return true


func _play_upgrade_animation() -> void:
	# Pulse effect on the machine
	var tween := create_tween()
	tween.set_loops(int(UPGRADE_TIME / 0.5))
	tween.tween_property(mesh, "scale", Vector3(1.1, 1.1, 1.1), 0.25)
	tween.tween_property(mesh, "scale", Vector3(1.0, 1.0, 1.0), 0.25)


func _on_upgrade_timer_timeout() -> void:
	pap_state = PaPState.READY

	# Upgrade the weapon
	if upgrading_weapon:
		upgrading_weapon.pack_a_punch()

	AudioManager.play_sound_3d("pack_a_punch_done", global_position)

	# Start grab timer
	grab_timer.wait_time = GRAB_TIME
	grab_timer.start()


func _grab_weapon(player: Node) -> bool:
	if not upgrading_weapon:
		return false

	grab_timer.stop()

	# Give weapon back to player
	player.weapons.append(upgrading_weapon)
	upgrading_weapon.visible = true
	upgrading_weapon.owner_player = player

	AudioManager.play_sound_ui("purchase")

	_reset()
	return true


func _on_grab_timer_timeout() -> void:
	# Player didn't grab in time, weapon is lost
	if upgrading_weapon:
		upgrading_weapon.queue_free()

	_reset()


func _reset() -> void:
	pap_state = PaPState.IDLE
	upgrading_weapon = null
	upgraded_weapon_id = ""
	waiting_player = null


func get_prompt(player: Node) -> String:
	if not is_usable:
		return "Requires Power"

	match pap_state:
		PaPState.IDLE:
			var current_weapon: Node = player.get_current_weapon()
			if not current_weapon:
				return "No weapon equipped"

			if current_weapon.is_pack_a_punched:
				return "Already upgraded"

			if player.can_afford(cost):
				return "Upgrade %s [Cost: %d]" % [current_weapon.display_name, cost]
			else:
				return "Upgrade %s [Cost: %d] (Need more points)" % [current_weapon.display_name, cost]

		PaPState.UPGRADING:
			return "Upgrading..."

		PaPState.READY:
			if waiting_player == player:
				var weapon_name: String = upgrading_weapon.display_name if upgrading_weapon else "weapon"
				return "Take %s" % weapon_name
			else:
				return ""

	return ""
