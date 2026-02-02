extends Node

var noise := FastNoiseLite.new()
var scale = 0.15

func _ready():
	noise.seed = randi_range(10000, 99999)
	
func get_noise(x: float, y: float) -> float:
	var layer1 = noise.get_noise_2d(x * scale, y * scale) + 0.6
	var layer2 = clamp(noise.get_noise_2d(x * scale * 0.1, y * scale * 2) * 0.8 + 0.4, 0, 1) * 0.6
	
	return clamp(layer1 + layer2, 0, 1)
