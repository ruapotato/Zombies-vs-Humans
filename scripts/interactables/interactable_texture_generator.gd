extends Node
class_name InteractableTextureGenerator
## Generates procedural pixel art textures for interactables

static var texture_cache: Dictionary = {}


static func get_perk_texture(perk_name: String) -> ImageTexture:
	var key := "perk_" + perk_name
	if key in texture_cache:
		return texture_cache[key]

	var tex := _generate_perk_machine(perk_name)
	texture_cache[key] = tex
	return tex


static func get_mystery_box_texture() -> ImageTexture:
	if "mystery_box" in texture_cache:
		return texture_cache["mystery_box"]

	var tex := _generate_mystery_box()
	texture_cache["mystery_box"] = tex
	return tex


static func get_weapon_chalk_texture(weapon_name: String) -> ImageTexture:
	var key := "weapon_" + weapon_name
	if key in texture_cache:
		return texture_cache[key]

	var tex := _generate_weapon_chalk(weapon_name)
	texture_cache[key] = tex
	return tex


static func _generate_perk_machine(perk_name: String) -> ImageTexture:
	var img := Image.create(48, 80, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Perk colors
	var colors := {
		"juggernog": Color(0.9, 0.2, 0.2),
		"speed_cola": Color(0.2, 0.9, 0.3),
		"double_tap": Color(0.9, 0.9, 0.2),
		"quick_revive": Color(0.2, 0.6, 0.9),
		"stamin_up": Color(0.9, 0.7, 0.2),
		"phd_flopper": Color(0.6, 0.2, 0.9),
		"deadshot": Color(0.4, 0.4, 0.4),
		"mule_kick": Color(0.4, 0.9, 0.4),
	}

	var main_color: Color = colors.get(perk_name, Color(0.5, 0.5, 0.9))
	var dark := main_color.darkened(0.4)
	var light := main_color.lightened(0.3)
	var metal := Color(0.4, 0.4, 0.45)

	# Machine body
	for y in range(10, 75):
		for x in range(8, 40):
			if x == 8 or x == 39 or y == 10 or y == 74:
				_safe_pixel(img, x, y, dark)
			elif x < 12 or x > 35:
				_safe_pixel(img, x, y, metal)
			else:
				_safe_pixel(img, x, y, main_color)

	# Glowing top light
	for y in range(4, 10):
		for x in range(16, 32):
			var dist := abs(x - 24) + abs(y - 7)
			if dist < 10:
				_safe_pixel(img, x, y, light if dist < 6 else main_color)

	# Perk logo area (darker rectangle)
	for y in range(20, 45):
		for x in range(14, 34):
			_safe_pixel(img, x, y, dark)

	# Simple perk symbol
	_draw_perk_symbol(img, perk_name, 24, 32, light)

	# Bottle slot
	for y in range(50, 65):
		for x in range(18, 30):
			if y == 50 or y == 64 or x == 18 or x == 29:
				_safe_pixel(img, x, y, metal)
			else:
				_safe_pixel(img, x, y, Color(0.1, 0.1, 0.1))

	# Coin slot
	for y in range(55, 60):
		for x in range(32, 36):
			_safe_pixel(img, x, y, Color(0.2, 0.2, 0.2))

	return ImageTexture.create_from_image(img)


static func _draw_perk_symbol(img: Image, perk_name: String, cx: int, cy: int, color: Color) -> void:
	match perk_name:
		"juggernog":
			# Fist/power symbol
			for y in range(-6, 7):
				for x in range(-4, 5):
					if abs(x) + abs(y) < 8:
						_safe_pixel(img, cx + x, cy + y, color)
		"speed_cola":
			# Lightning bolt
			_safe_pixel(img, cx, cy - 6, color)
			for i in range(5):
				_safe_pixel(img, cx - i, cy - 5 + i, color)
			for i in range(5):
				_safe_pixel(img, cx - 2 + i, cy + i, color)
		"double_tap":
			# Two bullets
			for y in range(-5, 6):
				_safe_pixel(img, cx - 3, cy + y, color)
				_safe_pixel(img, cx + 3, cy + y, color)
		"quick_revive":
			# Heart/cross
			_draw_circle_small(img, cx, cy, 5, color)
			for i in range(-3, 4):
				_safe_pixel(img, cx + i, cy, color)
				_safe_pixel(img, cx, cy + i, color)
		_:
			# Generic star
			for i in range(-4, 5):
				_safe_pixel(img, cx + i, cy, color)
				_safe_pixel(img, cx, cy + i, color)
				_safe_pixel(img, cx + i, cy + i, color)
				_safe_pixel(img, cx + i, cy - i, color)


static func _generate_mystery_box() -> ImageTexture:
	var img := Image.create(64, 48, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var wood := Color(0.4, 0.25, 0.15)
	var wood_dark := Color(0.3, 0.18, 0.1)
	var gold := Color(0.9, 0.75, 0.3)
	var glow := Color(0.3, 0.8, 1.0)

	# Box body
	for y in range(15, 45):
		for x in range(5, 59):
			if x == 5 or x == 58 or y == 15 or y == 44:
				_safe_pixel(img, x, y, wood_dark)
			elif (x + y) % 8 < 2:
				_safe_pixel(img, x, y, wood_dark)
			else:
				_safe_pixel(img, x, y, wood)

	# Lid (slightly open, glowing)
	for y in range(8, 16):
		for x in range(4, 60):
			var lift := int((1.0 - abs(x - 32) / 28.0) * 4)
			if y == 8 - lift or y == 15 or x == 4 or x == 59:
				_safe_pixel(img, x, y - lift, wood_dark)
			else:
				_safe_pixel(img, x, y - lift, wood)

	# Glow from inside
	for y in range(10, 18):
		for x in range(15, 49):
			var intensity := 1.0 - abs(x - 32) / 20.0
			if intensity > 0:
				_safe_pixel(img, x, y, Color(glow.r, glow.g, glow.b, intensity * 0.7))

	# Question marks
	_draw_question_mark(img, 20, 30, gold)
	_draw_question_mark(img, 32, 30, gold)
	_draw_question_mark(img, 44, 30, gold)

	# Gold trim
	for x in range(5, 59):
		_safe_pixel(img, x, 16, gold)
		_safe_pixel(img, x, 43, gold)
	for y in range(16, 44):
		_safe_pixel(img, 6, y, gold)
		_safe_pixel(img, 57, y, gold)

	return ImageTexture.create_from_image(img)


static func _draw_question_mark(img: Image, cx: int, cy: int, color: Color) -> void:
	# Top curve
	for x in range(-3, 4):
		_safe_pixel(img, cx + x, cy - 6, color)
	_safe_pixel(img, cx + 3, cy - 5, color)
	_safe_pixel(img, cx + 3, cy - 4, color)
	for x in range(-1, 4):
		_safe_pixel(img, cx + x, cy - 3, color)
	_safe_pixel(img, cx, cy - 2, color)
	_safe_pixel(img, cx, cy - 1, color)
	# Dot
	_safe_pixel(img, cx, cy + 2, color)
	_safe_pixel(img, cx, cy + 3, color)


static func _generate_weapon_chalk(weapon_name: String) -> ImageTexture:
	var img := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var chalk := Color(0.85, 0.85, 0.8, 0.9)
	var chalk_dim := Color(0.7, 0.7, 0.65, 0.6)

	# Simple gun outline (chalk drawing style)
	# Stock
	for y in range(12, 20):
		for x in range(5, 15):
			if randi() % 3 != 0:
				_safe_pixel(img, x, y, chalk if randi() % 2 == 0 else chalk_dim)

	# Body
	for y in range(14, 18):
		for x in range(15, 50):
			if randi() % 4 != 0:
				_safe_pixel(img, x, y, chalk if randi() % 2 == 0 else chalk_dim)

	# Barrel
	for y in range(15, 17):
		for x in range(50, 60):
			if randi() % 3 != 0:
				_safe_pixel(img, x, y, chalk)

	# Grip
	for y in range(18, 26):
		for x in range(28, 35):
			if randi() % 3 != 0:
				_safe_pixel(img, x, y, chalk if randi() % 2 == 0 else chalk_dim)

	# Magazine (for SMGs/ARs)
	if "smg" in weapon_name or "rifle" in weapon_name or "ak" in weapon_name:
		for y in range(18, 28):
			for x in range(22, 28):
				if randi() % 3 != 0:
					_safe_pixel(img, x, y, chalk_dim)

	return ImageTexture.create_from_image(img)


static func _draw_circle_small(img: Image, cx: int, cy: int, radius: int, color: Color) -> void:
	for y in range(cy - radius, cy + radius + 1):
		for x in range(cx - radius, cx + radius + 1):
			var dist := sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy))
			if dist <= radius and dist > radius - 2:
				_safe_pixel(img, x, y, color)


static func _safe_pixel(img: Image, x: int, y: int, color: Color) -> void:
	if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
		# Blend if alpha
		if color.a < 1.0:
			var existing := img.get_pixel(x, y)
			color = existing.blend(color)
		img.set_pixel(x, y, color)
