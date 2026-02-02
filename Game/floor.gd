extends CollisionShape2D

func _ready() -> void:
	self.shape.extents = Vector2(pow(2, 22), self.shape.extents.y)
