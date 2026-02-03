extends Node
## AudioManager - Sound effects and music singleton
## Handles all audio playback with pooling and spatial audio support

const MAX_SFX_PLAYERS := 32
const MAX_MUSIC_PLAYERS := 2
const MAX_UI_PLAYERS := 8

var sfx_pool: Array[AudioStreamPlayer3D] = []
var music_players: Array[AudioStreamPlayer] = []
var ui_pool: Array[AudioStreamPlayer] = []

var sfx_index := 0
var ui_index := 0

var master_volume := 1.0
var music_volume := 0.7
var sfx_volume := 1.0
var ui_volume := 0.8

# Sound effect paths
var sounds: Dictionary = {
	# Weapons
	"pistol_fire": "res://assets/sounds/weapons/pistol_fire.ogg",
	"rifle_fire": "res://assets/sounds/weapons/rifle_fire.ogg",
	"shotgun_fire": "res://assets/sounds/weapons/shotgun_fire.ogg",
	"smg_fire": "res://assets/sounds/weapons/smg_fire.ogg",
	"lmg_fire": "res://assets/sounds/weapons/lmg_fire.ogg",
	"sniper_fire": "res://assets/sounds/weapons/sniper_fire.ogg",
	"raygun_fire": "res://assets/sounds/weapons/raygun_fire.ogg",
	"thundergun_fire": "res://assets/sounds/weapons/thundergun_fire.ogg",
	"reload": "res://assets/sounds/weapons/reload.ogg",
	"empty_clip": "res://assets/sounds/weapons/empty_clip.ogg",
	"weapon_switch": "res://assets/sounds/weapons/weapon_switch.ogg",

	# Player
	"player_hurt": "res://assets/sounds/player/hurt.ogg",
	"player_down": "res://assets/sounds/player/down.ogg",
	"player_revive": "res://assets/sounds/player/revive.ogg",
	"player_revived": "res://assets/sounds/player/revived.ogg",
	"footstep": "res://assets/sounds/player/footstep.ogg",
	"jump": "res://assets/sounds/player/jump.ogg",
	"land": "res://assets/sounds/player/land.ogg",

	# Zombies
	"zombie_spawn": "res://assets/sounds/enemies/spawn.ogg",
	"zombie_attack": "res://assets/sounds/enemies/attack.ogg",
	"zombie_hurt": "res://assets/sounds/enemies/hurt.ogg",
	"zombie_death": "res://assets/sounds/enemies/death.ogg",
	"zombie_growl": "res://assets/sounds/enemies/growl.ogg",
	"tyrant_roar": "res://assets/sounds/enemies/tyrant_roar.ogg",

	# Interactables
	"door_open": "res://assets/sounds/interactables/door_open.ogg",
	"barrier_break": "res://assets/sounds/interactables/barrier_break.ogg",
	"barrier_repair": "res://assets/sounds/interactables/barrier_repair.ogg",
	"purchase": "res://assets/sounds/interactables/purchase.ogg",
	"denied": "res://assets/sounds/interactables/denied.ogg",
	"mystery_box_open": "res://assets/sounds/interactables/mystery_box_open.ogg",
	"mystery_box_weapon": "res://assets/sounds/interactables/mystery_box_weapon.ogg",
	"mystery_box_close": "res://assets/sounds/interactables/mystery_box_close.ogg",
	"mystery_box_move": "res://assets/sounds/interactables/mystery_box_move.ogg",
	"perk_machine_jingle": "res://assets/sounds/interactables/perk_jingle.ogg",
	"perk_drink": "res://assets/sounds/interactables/perk_drink.ogg",
	"pack_a_punch_start": "res://assets/sounds/interactables/pap_start.ogg",
	"pack_a_punch_done": "res://assets/sounds/interactables/pap_done.ogg",
	"power_switch": "res://assets/sounds/interactables/power_switch.ogg",

	# Power-ups
	"powerup_spawn": "res://assets/sounds/powerups/spawn.ogg",
	"max_ammo": "res://assets/sounds/powerups/max_ammo.ogg",
	"insta_kill": "res://assets/sounds/powerups/insta_kill.ogg",
	"double_points": "res://assets/sounds/powerups/double_points.ogg",
	"nuke": "res://assets/sounds/powerups/nuke.ogg",
	"carpenter": "res://assets/sounds/powerups/carpenter.ogg",
	"fire_sale": "res://assets/sounds/powerups/fire_sale.ogg",

	# UI
	"ui_hover": "res://assets/sounds/ui/hover.ogg",
	"ui_click": "res://assets/sounds/ui/click.ogg",
	"ui_back": "res://assets/sounds/ui/back.ogg",
	"round_start": "res://assets/sounds/ui/round_start.ogg",
	"round_end": "res://assets/sounds/ui/round_end.ogg",
	"game_over": "res://assets/sounds/ui/game_over.ogg",
	"points_gain": "res://assets/sounds/ui/points_gain.ogg"
}

# Music tracks
var music_tracks: Dictionary = {
	"menu": "res://assets/music/menu.ogg",
	"lobby": "res://assets/music/lobby.ogg",
	"gameplay": "res://assets/music/gameplay.ogg",
	"intense": "res://assets/music/intense.ogg",
	"game_over": "res://assets/music/game_over.ogg"
}

var current_music_track: String = ""

# Preloaded sounds cache
var sound_cache: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_audio_pools()
	_preload_common_sounds()


func _create_audio_pools() -> void:
	# Create 3D SFX pool
	for i in range(MAX_SFX_PLAYERS):
		var player := AudioStreamPlayer3D.new()
		player.bus = "SFX"
		player.max_distance = 50.0
		player.unit_size = 5.0
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(player)
		sfx_pool.append(player)

	# Create music players
	for i in range(MAX_MUSIC_PLAYERS):
		var player := AudioStreamPlayer.new()
		player.bus = "Music"
		add_child(player)
		music_players.append(player)

	# Create UI SFX pool
	for i in range(MAX_UI_PLAYERS):
		var player := AudioStreamPlayer.new()
		player.bus = "UI"
		add_child(player)
		ui_pool.append(player)


func _preload_common_sounds() -> void:
	# Preload frequently used sounds
	var common_sounds := [
		"pistol_fire", "rifle_fire", "shotgun_fire",
		"reload", "empty_clip", "weapon_switch",
		"zombie_hurt", "zombie_death", "zombie_attack",
		"purchase", "denied", "footstep"
	]

	for sound_name in common_sounds:
		if sound_name in sounds:
			var path: String = sounds[sound_name]
			if ResourceLoader.exists(path):
				sound_cache[sound_name] = load(path)


func _get_sound(sound_name: String) -> AudioStream:
	if sound_name in sound_cache:
		return sound_cache[sound_name]

	if sound_name in sounds:
		var path: String = sounds[sound_name]
		if ResourceLoader.exists(path):
			var stream := load(path)
			sound_cache[sound_name] = stream
			return stream

	push_warning("Sound not found: %s" % sound_name)
	return null


func play_sound_3d(sound_name: String, position: Vector3, volume_db: float = 0.0, pitch_scale: float = 1.0) -> AudioStreamPlayer3D:
	var stream := _get_sound(sound_name)
	if not stream:
		return null

	var player := _get_next_sfx_player()
	player.stream = stream
	player.global_position = position
	player.volume_db = volume_db + linear_to_db(sfx_volume * master_volume)
	player.pitch_scale = pitch_scale
	player.play()

	return player


func _get_next_sfx_player() -> AudioStreamPlayer3D:
	# Find a free player or use round-robin
	for i in range(MAX_SFX_PLAYERS):
		var idx := (sfx_index + i) % MAX_SFX_PLAYERS
		if not sfx_pool[idx].playing:
			sfx_index = (idx + 1) % MAX_SFX_PLAYERS
			return sfx_pool[idx]

	# All players busy, use round-robin
	var player := sfx_pool[sfx_index]
	sfx_index = (sfx_index + 1) % MAX_SFX_PLAYERS
	return player


func play_sound_ui(sound_name: String, volume_db: float = 0.0, pitch_scale: float = 1.0) -> AudioStreamPlayer:
	var stream := _get_sound(sound_name)
	if not stream:
		return null

	var player := _get_next_ui_player()
	player.stream = stream
	player.volume_db = volume_db + linear_to_db(ui_volume * master_volume)
	player.pitch_scale = pitch_scale
	player.play()

	return player


func _get_next_ui_player() -> AudioStreamPlayer:
	for i in range(MAX_UI_PLAYERS):
		var idx := (ui_index + i) % MAX_UI_PLAYERS
		if not ui_pool[idx].playing:
			ui_index = (idx + 1) % MAX_UI_PLAYERS
			return ui_pool[idx]

	var player := ui_pool[ui_index]
	ui_index = (ui_index + 1) % MAX_UI_PLAYERS
	return player


func play_music(track_name: String, fade_duration: float = 1.0) -> void:
	if track_name == current_music_track:
		return

	if track_name not in music_tracks:
		push_warning("Music track not found: %s" % track_name)
		return

	var path: String = music_tracks[track_name]
	if not ResourceLoader.exists(path):
		push_warning("Music file not found: %s" % path)
		return

	var stream := load(path)
	current_music_track = track_name

	# Crossfade between music players
	var current_player := music_players[0] if music_players[0].playing else null
	var new_player := music_players[1] if music_players[0].playing else music_players[0]

	new_player.stream = stream
	new_player.volume_db = linear_to_db(0.001)  # Start silent
	new_player.play()

	# Fade in new, fade out old
	var tween := create_tween()
	tween.set_parallel(true)

	var target_volume := linear_to_db(music_volume * master_volume)
	tween.tween_property(new_player, "volume_db", target_volume, fade_duration)

	if current_player:
		tween.tween_property(current_player, "volume_db", linear_to_db(0.001), fade_duration)
		tween.chain().tween_callback(current_player.stop)


func stop_music(fade_duration: float = 1.0) -> void:
	current_music_track = ""

	for player in music_players:
		if player.playing:
			var tween := create_tween()
			tween.tween_property(player, "volume_db", linear_to_db(0.001), fade_duration)
			tween.tween_callback(player.stop)


func set_master_volume(volume: float) -> void:
	master_volume = clamp(volume, 0.0, 1.0)
	_update_music_volume()


func set_music_volume(volume: float) -> void:
	music_volume = clamp(volume, 0.0, 1.0)
	_update_music_volume()


func set_sfx_volume(volume: float) -> void:
	sfx_volume = clamp(volume, 0.0, 1.0)


func set_ui_volume(volume: float) -> void:
	ui_volume = clamp(volume, 0.0, 1.0)


func _update_music_volume() -> void:
	var target_volume := linear_to_db(music_volume * master_volume)
	for player in music_players:
		if player.playing:
			player.volume_db = target_volume


# Announcer voice lines
func play_announcer(line: String) -> void:
	play_sound_ui(line, 3.0)  # Announcer is louder


# Play randomized sound variation
func play_sound_3d_random(base_name: String, position: Vector3, variations: int = 3, volume_db: float = 0.0) -> AudioStreamPlayer3D:
	var variation := randi() % variations + 1
	var sound_name := "%s_%d" % [base_name, variation]

	# Fall back to base name if variation doesn't exist
	if sound_name not in sounds:
		sound_name = base_name

	return play_sound_3d(sound_name, position, volume_db, randf_range(0.95, 1.05))
