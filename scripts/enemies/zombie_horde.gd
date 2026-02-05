extends Node
class_name ZombieHorde
## Centralized controller for all zombies - much more efficient than individual AI scripts
## Processes zombies in batches and handles pathfinding, targeting, and movement centrally

signal zombie_died(zombie: Node3D, killer_id: int, is_headshot: bool)

# Processing configuration
const PATH_UPDATE_BATCH := 20  # How many path updates per frame
const TARGET_UPDATE_INTERVAL := 0.5  # How often to recalculate targets
const SYNC_BATCH_SIZE := 25  # How many zombies to sync per frame

# LOD distances - aggressive culling for performance
const LOD_PHYSICS_DIST := 20.0  # Use physics within this range
const LOD_FAR_DIST := 50.0  # Direct teleport beyond this
const MAX_PHYSICS_ZOMBIES := 100  # Only do physics for this many
const MAX_ANIMATED_ZOMBIES := 400  # Billboard animation is very cheap

var physics_this_frame: int = 0  # Counter for physics limit
var animated_this_frame: int = 0  # Counter for animation limit

# References
var zombies_container: Node3D
var game_controller: Node3D

# Zombie tracking
var all_zombies: Array[Node3D] = []
var zombie_data: Dictionary = {}  # zombie -> {target, path_timer, sync_timer, etc}

# Batch processing state
var path_batch_index: int = 0
var sync_batch_index: int = 0
var target_update_timer: float = 0.0

# Cached player data (updated once per frame)
var cached_players: Array[Node3D] = []
var cached_player_positions: Array[Vector3] = []
var cached_player_forward: Vector3 = Vector3.FORWARD  # Camera direction for culling
var cached_camera: Camera3D = null


func _ready() -> void:
	# Only server runs horde AI
	if not multiplayer.is_server():
		set_physics_process(false)


func initialize(container: Node3D, controller: Node3D) -> void:
	zombies_container = container
	game_controller = controller

	# Connect to container child signals
	zombies_container.child_entered_tree.connect(_on_zombie_added)
	zombies_container.child_exiting_tree.connect(_on_zombie_removed)

	# Register existing zombies
	for child in zombies_container.get_children():
		_on_zombie_added(child)


func _on_zombie_added(node: Node) -> void:
	if not node is CharacterBody3D:
		return

	var zombie := node as Node3D
	all_zombies.append(zombie)

	# Assign initial target immediately if we have players
	var initial_target: Node3D = null
	if cached_players.size() > 0:
		initial_target = cached_players[randi() % cached_players.size()]

	# Initialize zombie data with staggered timers
	zombie_data[zombie] = {
		"target": initial_target,
		"path_timer": randf() * 0.5,  # Staggered path updates
		"sync_timer": randf() * 0.15,  # Staggered network sync
		"stuck_timer": 0.0,
		"last_pos": zombie.global_position,
	}

	# Disable the zombie's own physics processing - horde controls it now
	if zombie.has_method("set_horde_controlled"):
		zombie.set_horde_controlled(true)

	# Set to chasing state immediately
	zombie.set("state", 2)  # CHASING


func _on_zombie_removed(node: Node) -> void:
	if node in all_zombies:
		all_zombies.erase(node)
		zombie_data.erase(node)


func _physics_process(delta: float) -> void:
	if all_zombies.is_empty():
		return

	# Cache player data once per frame
	_update_player_cache()

	# Update targets periodically (not every frame)
	target_update_timer -= delta
	if target_update_timer <= 0:
		target_update_timer = TARGET_UPDATE_INTERVAL
		_update_all_targets()

	# Process zombies in batches for pathfinding
	_process_path_batch(delta)

	# Process ALL zombies for movement (this is fast)
	_process_all_movement(delta)

	# Batch sync to clients
	_process_sync_batch()


func _update_player_cache() -> void:
	cached_players.clear()
	cached_player_positions.clear()

	# Get camera for frustum culling
	cached_camera = get_viewport().get_camera_3d()
	if cached_camera:
		cached_player_forward = -cached_camera.global_transform.basis.z

	if not game_controller:
		# Fallback: find players in tree
		var players_node := get_tree().current_scene.get_node_or_null("Players")
		if players_node:
			for player in players_node.get_children():
				cached_players.append(player)
				cached_player_positions.append(player.global_position)
		return

	var players_node := game_controller.get_node_or_null("Players")
	if not players_node:
		return

	for player in players_node.get_children():
		# Accept any player, check validity later
		cached_players.append(player)
		cached_player_positions.append(player.global_position)


func _update_all_targets() -> void:
	if cached_players.is_empty():
		return

	for zombie in all_zombies:
		if not is_instance_valid(zombie):
			continue

		var data: Dictionary = zombie_data.get(zombie, {})
		if data.is_empty():
			continue

		# Find nearest player
		var zombie_pos := zombie.global_position
		var nearest_player: Node3D = null
		var nearest_dist := INF

		for i in cached_players.size():
			var dist := zombie_pos.distance_squared_to(cached_player_positions[i])
			if dist < nearest_dist:
				nearest_dist = dist
				nearest_player = cached_players[i]

		data["target"] = nearest_player


func _process_path_batch(delta: float) -> void:
	if all_zombies.is_empty():
		return

	# Process a batch of zombies for path updates
	var batch_end := mini(path_batch_index + PATH_UPDATE_BATCH, all_zombies.size())
	var processed := 0

	for i in range(path_batch_index, batch_end):
		var zombie := all_zombies[i]
		if not is_instance_valid(zombie):
			continue

		var data: Dictionary = zombie_data.get(zombie, {})
		if data.is_empty():
			continue

		var target: Node3D = data.get("target")
		if not target or not is_instance_valid(target):
			continue

		# Skip path updates for far zombies - they use direct movement anyway
		var dist_sq := zombie.global_position.distance_squared_to(target.global_position)
		if dist_sq > LOD_PHYSICS_DIST * LOD_PHYSICS_DIST:
			continue

		# Update path timer
		data["path_timer"] -= delta * PATH_UPDATE_BATCH

		if data["path_timer"] <= 0:
			data["path_timer"] = 0.4 + randf() * 0.3  # 0.4-0.7 second updates

			var nav_agent: NavigationAgent3D = zombie.get_node_or_null("NavigationAgent3D")
			if nav_agent:
				nav_agent.target_position = target.global_position
				processed += 1

				# Limit actual nav updates per frame
				if processed >= 10:
					break

	# Advance batch index
	path_batch_index = batch_end
	if path_batch_index >= all_zombies.size():
		path_batch_index = 0


func _process_all_movement(delta: float) -> void:
	physics_this_frame = 0
	animated_this_frame = 0

	# Quick assign targets if none assigned yet
	for zombie in all_zombies:
		if not is_instance_valid(zombie):
			continue

		# Ensure zombie has data entry
		if zombie not in zombie_data:
			zombie_data[zombie] = {
				"target": null,
				"path_timer": randf() * 0.5,
				"sync_timer": randf() * 0.15,
				"stuck_timer": 0.0,
				"last_pos": zombie.global_position,
			}

		var data: Dictionary = zombie_data[zombie]
		if cached_players.size() > 0:
			if not data.get("target") or not is_instance_valid(data.get("target")):
				data["target"] = cached_players[0]

	for zombie in all_zombies:
		if not is_instance_valid(zombie):
			continue

		# Skip dead/dying zombies, but NOT spawning (they transition quickly)
		var state: int = zombie.get("state") if "state" in zombie else 0
		if state >= 4:  # DYING or DEAD only
			continue

		var data: Dictionary = zombie_data.get(zombie, {})
		if data.is_empty():
			continue

		var target: Node3D = data.get("target")
		if not target or not is_instance_valid(target):
			# Try to get any player as fallback
			if cached_players.size() > 0:
				target = cached_players[0]
				data["target"] = target
			else:
				continue

		# Calculate distance to target for LOD
		var dist_sq := zombie.global_position.distance_squared_to(target.global_position)

		# Handle attacking state - check for players or barriers
		var players_in_range: Array = zombie.get("players_in_attack_range") if "players_in_attack_range" in zombie else []
		var barriers_in_range: Array = zombie.get("barriers_in_attack_range") if "barriers_in_attack_range" in zombie else []

		var has_barrier_target := false
		for barrier in barriers_in_range:
			if is_instance_valid(barrier) and barrier.has_method("is_broken"):
				if not barrier.is_broken():
					has_barrier_target = true
					break

		if not players_in_range.is_empty() or has_barrier_target:
			zombie.set("state", 3)  # ATTACKING
			_process_attack(zombie, delta)
			continue

		zombie.set("state", 2)  # CHASING

		# Get direction to target (zero Y before normalizing!)
		var direction := target.global_position - zombie.global_position
		direction.y = 0
		if direction.length_squared() > 0.01:
			direction = direction.normalized()
		else:
			continue  # Already at target
		var speed: float = zombie.get("speed") if "speed" in zombie else 3.0

		# Check if zombie is visible to camera
		var is_visible := _is_zombie_visible(zombie)

		# If not visible, just teleport toward player (cheapest)
		if not is_visible:
			var new_pos := zombie.global_position + direction * speed * delta
			new_pos.y = target.global_position.y  # Match target's Y (ground level)
			zombie.global_position = new_pos
			_set_zombie_visible(zombie, false)
			_stop_zombie_animation(zombie)
			continue

		# All visible zombies stay visible
		_set_zombie_visible(zombie, true)

		# Set velocity for animation
		zombie.velocity.x = direction.x * speed
		zombie.velocity.z = direction.z * speed

		# Determine what processing to use
		var use_physics := dist_sq < LOD_PHYSICS_DIST * LOD_PHYSICS_DIST and physics_this_frame < MAX_PHYSICS_ZOMBIES
		var use_animation := animated_this_frame < MAX_ANIMATED_ZOMBIES

		# Movement based on distance and limits
		if dist_sq > LOD_FAR_DIST * LOD_FAR_DIST:
			# VERY FAR: Direct teleport, faster
			var new_pos := zombie.global_position + direction * speed * delta * 1.3
			new_pos.y = target.global_position.y  # Match target's Y
			zombie.global_position = new_pos
			zombie.rotation.y = atan2(-direction.x, -direction.z)

		elif use_physics:
			# NEAR with physics
			var nav_agent: NavigationAgent3D = zombie.get_node_or_null("NavigationAgent3D")
			if nav_agent and not nav_agent.is_navigation_finished():
				var next_pos := nav_agent.get_next_path_position()
				var nav_dir := next_pos - zombie.global_position
				nav_dir.y = 0
				if nav_dir.length_squared() > 0.01:
					direction = nav_dir.normalized()

			zombie.velocity.x = lerpf(zombie.velocity.x, direction.x * speed, 0.2)
			zombie.velocity.z = lerpf(zombie.velocity.z, direction.z * speed, 0.2)
			if not zombie.is_on_floor():
				zombie.velocity.y -= 20.0 * delta

			zombie.move_and_slide()
			physics_this_frame += 1

		else:
			# FAR or over limit: Just teleport
			var new_pos := zombie.global_position + direction * speed * delta
			# Simple gravity: if above ground, fall toward target Y
			if new_pos.y > target.global_position.y + 0.5:
				new_pos.y -= 10.0 * delta  # Fall speed
			zombie.global_position = new_pos

		# Billboards don't need rotation (they face camera automatically)
		# But we still set it for non-billboard zombies
		if not zombie.get_node_or_null("Sprite3D"):
			zombie.rotation.y = atan2(-direction.x, -direction.z)

		# Animate if under limit (billboard animation is very cheap)
		if use_animation:
			_update_zombie_animation(zombie)
			animated_this_frame += 1


func _process_attack(zombie: Node3D, delta: float) -> void:
	# Let the zombie handle its own attack logic (it's simple)
	if zombie.has_method("_attack_target"):
		zombie._attack_target(delta)

	# Apply gravity even while attacking
	if not zombie.is_on_floor():
		zombie.velocity.y -= 20.0 * delta
	zombie.move_and_slide()


func _update_zombie_animation(zombie: Node3D) -> void:
	# Use the zombie's own animation update method
	if zombie.has_method("update_animation_from_velocity"):
		zombie.update_animation_from_velocity()


func _stop_zombie_animation(zombie: Node3D) -> void:
	# Stop animation player to save CPU
	if zombie.has_method("stop_animation"):
		zombie.stop_animation()


func _set_zombie_visible(zombie: Node3D, vis: bool) -> void:
	# For billboard zombies
	var sprite: Sprite3D = zombie.get_node_or_null("Sprite3D")
	if sprite:
		if sprite.visible != vis:
			sprite.visible = vis
		return

	# For mesh-based zombies
	var model: Node3D = zombie.get_node_or_null("Model")
	if model and model.visible != vis:
		model.visible = vis


func _is_zombie_visible(zombie: Node3D) -> bool:
	# Quick check: is zombie roughly in front of camera?
	if not cached_camera or cached_player_positions.is_empty():
		return true  # Default to visible if no camera

	var cam_pos := cached_camera.global_position
	var to_zombie := zombie.global_position - cam_pos

	# If zombie is very close, always visible (prevents popping)
	if to_zombie.length_squared() < 100.0:  # Within 10 units
		return true

	var dot := to_zombie.normalized().dot(cached_player_forward)

	# Only hide zombies that are clearly behind the camera
	# dot < -0.5 means more than 120 degrees away from view direction
	return dot > -0.5


# Called by zombies when they die
func on_zombie_died(zombie: Node3D, killer_id: int, is_headshot: bool) -> void:
	zombie_died.emit(zombie, killer_id, is_headshot)


func get_zombie_count() -> int:
	return all_zombies.size()


func _process_sync_batch() -> void:
	if all_zombies.is_empty():
		return

	# Sync a batch of zombies each frame
	var batch_end := mini(sync_batch_index + SYNC_BATCH_SIZE, all_zombies.size())

	for i in range(sync_batch_index, batch_end):
		var zombie := all_zombies[i]
		if not is_instance_valid(zombie):
			continue

		# Call the zombie's sync RPC
		if zombie.has_method("_sync_state"):
			zombie.rpc("_sync_state", zombie.global_position, zombie.rotation.y, zombie.velocity, int(zombie.state))

	# Advance batch index
	sync_batch_index = batch_end
	if sync_batch_index >= all_zombies.size():
		sync_batch_index = 0
