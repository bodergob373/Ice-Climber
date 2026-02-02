extends Control

# Called when the node enters the scene tree for the first time.
func _ready():
	get_node("DeathScreen").get_node("Menu").get_node("RecordInput").text_submitted.connect(func(_text):
		get_node("DeathScreen").get_node("Menu").get_node("RecordInput").release_focus())

func _input(event: InputEvent):
	if not event is InputEventMouseButton:
		return
	if not event.button_index == MOUSE_BUTTON_LEFT:
		return
	if not event.pressed:
		return
		
	var click_pos = event.global_position
	
	if not get_global_rect().has_point(click_pos):
		if has_focus():
			release_focus()
			unedit()
