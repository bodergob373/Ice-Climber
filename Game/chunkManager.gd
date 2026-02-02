extends Node2D

@export var chunk_size := 90
@export var pixel_size := 12
@export var viewRadius := 3
@export var camera: Node

const UPDATE_INTERVAL = 2.0

var noise := FastNoiseLite.new()
var chunks := {}
var nextUpdate = 0.0

func _ready():
	noise.seed = randi()

func _process(_delta):
	if Time.get_ticks_msec() * 0.001 > nextUpdate:
		nextUpdate = Time.get_ticks_msec() * 0.001 + UPDATE_INTERVAL
		
		var player_chunk = world_to_chunk(camera.global_position)
		
		for y in range(-viewRadius, viewRadius + 1):
			for x in range(-viewRadius, viewRadius + 1):
				var coord = player_chunk + Vector2i(x, y)
				var wx = (coord.x * chunk_size + coord.x + (1 - chunk_size) / 2.0) * pixel_size
				var wy = (coord.y * chunk_size + coord.y + (1 - chunk_size) / 2.0) * pixel_size
				
				if Vector2(camera.global_position.x - wx, camera.global_position.y - wy).length() < viewRadius * chunk_size * pixel_size && !chunks.has(coord):
					create_chunk(coord)

func create_chunk(coord: Vector2i):
	var chunkSprite = Sprite2D.new()
	var image := Image.create(chunk_size, chunk_size, false, Image.FORMAT_RGBA8)
	var texture: ImageTexture
	
	for y in chunk_size:
		for x in chunk_size:
			var wx = (coord.x * chunk_size + x + (1 - chunk_size) / 2.0) * pixel_size
			var wy = (coord.y * chunk_size + y + (1 - chunk_size) / 2.0) * pixel_size
			
			if (wy < 128 * 8):
				var textureFrequency = 2
				var texturing = noise.get_noise_2d(wx * textureFrequency, wy * textureFrequency) * 0.5 + 0.5
				var iceThickness = main.get_noise(wx, wy)
				var rockColor = Color.from_hsv(0, 0, 0.3 - texturing * 0.3)
				var iceColor = Color.from_hsv(0.56, 0.2, 1 - texturing * 0.1)
				var finalColor : Color
				
				if (wy < 0):
					finalColor = rockColor.blend(Color(iceColor.r, iceColor.g, iceColor.b, iceThickness * 0.9 + 0.1))
				else:
					finalColor = rockColor.blend(Color(iceColor.r, iceColor.g, iceColor.b, maxf(main.get_noise(wx, 0) * 128 + 128 - wy, 0) * 0.005))
			
				image.set_pixel(x, y, finalColor)
			
	texture = ImageTexture.create_from_image(image)
	chunkSprite.texture = texture
	chunkSprite.position = Vector2(coord.x * chunk_size * pixel_size, coord.y * chunk_size * pixel_size)
	chunkSprite.scale = Vector2(pixel_size, pixel_size)
	chunkSprite.texture_filter = TextureFilter.TEXTURE_FILTER_NEAREST
	chunkSprite.name = "Chunk_%s_%s" % [coord.x, coord.y]
	add_child(chunkSprite)
	chunks[coord] = chunkSprite
	spawn_ledge(coord)

func world_to_chunk(pos: Vector2) -> Vector2i:
	return Vector2i(
		floor(pos.x / chunk_size / pixel_size),
		floor(pos.y / chunk_size / pixel_size)
	)
	
func spawn_ledge(coord: Vector2i):
	if randf() > 0.5:
		return

	var local_x = randf_range(-chunk_size * pixel_size * 0.25, chunk_size * pixel_size * 0.25)
	var world_x = coord.x * chunk_size * pixel_size + local_x + chunk_size * pixel_size * 0.42

	var local_y = randf_range(-chunk_size * pixel_size * 0.25, chunk_size * pixel_size * 0.25)
	var world_y = coord.y * chunk_size * pixel_size + local_y
	
	if world_y > -320:
		return

	var ledge := get_parent().get_node("Floors").get_node("Ledge").duplicate()
	ledge.global_position = Vector2(world_x, world_y)

	get_parent().get_node("Floors").add_child(ledge)
	
	if randf() > 0.35:
		return
		
	var healthCrate := get_parent().get_node("Crates").get_node("HealthCrate").duplicate()
	healthCrate.global_position = Vector2(world_x, world_y) + Vector2(-420 + randf_range(-200, 200), -122)
	get_parent().get_node("Crates").add_child(healthCrate)
