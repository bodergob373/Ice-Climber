extends Node

@onready var http = $HTTPRequest
const PIXELS_PER_FOOT = 40
const UPPER_ARM_LENGTH = 42
const LOWER_ARM_LENGTH = 42
const CRATE_CHECK_INTERVAL := 0.5
const CRATE_PICKUP_RADIUS := 160.0
var started := false
var stamina := 1.0
var health := 1.0
var healthBarValue := 1.0
var selectedhand
var maxHeight := 0
var state := "Upright"
var framenumber = 0
var lastPosY = 0
var fallStartY = 0
var mousePosWhenAnchor := Vector2()
var rootPosWhenAnchor := Vector2()
var armMousePos
var anchoredHand
var handInfo := {Left = {Hand = null, ShoulderMarker = null, CenterMarker = null, TipMarker = null}, Right = {Hand = null, ShoulderMarker = null, CenterMarker = null, TipMarker = null}}
var crate_check_timer := 0.0

var characterRigidBodies = []
var character
var characterRoot
var characterStartingY

func _on_request_completed(_result, response_code, _headers, body):
	if response_code == 200:
		print("Score submitted successfully")
	else:
		print("Failed to submit score:", response_code, body.get_string_from_utf8())
	get_tree().reload_current_scene()

func get_shape2Ds(shape_node):
	var shapes = []
	
	if shape_node is CollisionShape2D:
		shapes.append(shape_node.shape)
	elif shape_node is CollisionPolygon2D or shape_node is Polygon2D:
		var points: PackedVector2Array = shape_node.polygon
		var convex_polys = Geometry2D.decompose_polygon_in_convex(points)
		
		for poly in convex_polys:
			var shape = ConvexPolygonShape2D.new()
			
			shape.points = poly
			shapes.append(shape)
	
	return shapes

func teleport_rigidbody(target_global_pos: Vector2, body, target_rot) -> void:
	var rid = body.get_rid()
	var new_transform = Transform2D(target_rot, target_global_pos)
	
	PhysicsServer2D.body_set_state(
		rid,
		PhysicsServer2D.BODY_STATE_TRANSFORM,
		new_transform
	)
	
	PhysicsServer2D.body_set_state(rid, PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY, Vector2.ZERO)
	PhysicsServer2D.body_set_state(rid, PhysicsServer2D.BODY_STATE_ANGULAR_VELOCITY, 0.0)
	
func shapecast_distance(shape, startingPos, targetOffset):
	var distance = null
	
	for shapeData in get_shape2Ds(shape):
		var query = PhysicsShapeQueryParameters2D.new()
		
		query.shape = shapeData
		query.transform = Transform2D(0, startingPos)
		query.motion = targetOffset
		query.exclude = characterRigidBodies
		query.collide_with_bodies = true

		var result = shape.get_world_2d().direct_space_state.cast_motion(query)
		
		if result:
			if distance:
				distance = min(result[0], distance)
			else:
				distance = result[0]
	if distance:
		return distance
	return 0
	
func submit_score(username: String, score: int):
	var url = "https://firestore.googleapis.com/v1/projects/ice-climber-678f7/databases/(default)/documents/scores"

	var body = {
		"fields": {
			"username": { "stringValue": username },
			"score": { "integerValue": score }
		}
	}

	var headers = ["Content-Type: application/json"]
	http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	
func spawn_particle_burst(
	template,
	parent,
	position: Vector2,
	base_color: Color,
	color_variations: int,
	hue_range: float,
	saturation_range: float,
	value_range: float
):
	if color_variations <= 0:
		return

	var base_amount = template.amount
	var amount_per = round(max(0, base_amount * 1.0 / color_variations))

	for i in range(color_variations):
		var p = template.duplicate()
		var lifetime = p.lifetime
		
		parent.add_child(p)
		p.global_position = position
		p.amount = amount_per
		p.color = Color.from_hsv(base_color.h + randf_range(-hue_range, hue_range), base_color.s + randf_range(-saturation_range, saturation_range), base_color.v + randf_range(-value_range, value_range), base_color.a)
		p.emitting = true
		
		get_tree().create_timer(lifetime).timeout.connect(func():
			if is_instance_valid(p):
				p.queue_free()
		)

func start_button_press():
	started = true
	get_node("UI").get_node("MenuScreen").visible = false
	get_node("UI").get_node("InfoScreen").visible = true
	
func submit_button_press():
	if started:
		var username = get_node("UI").get_node("DeathScreen").get_node("Menu").get_node("RecordInput").text

		submit_score(username, maxHeight)
	
func is_touching_static(shape):
	var touching
	
	if shape is RigidBody2D:
		touching = shape.get_colliding_bodies()
	elif shape is Area2D:
		touching = shape.get_overlapping_bodies()
	
	if touching:
		for body in touching:
			if body is StaticBody2D:
				return true
		return false
		
func character_grounded():
	return is_touching_static(characterRoot.get_node("FloorDetector"))
	
func check_for_crate_pickups():
	var crates_node = get_node_or_null("Crates")
	if not crates_node:
		return
		
	var crates_to_remove: Array = []
	
	for crate in crates_node.get_children():
		if not is_instance_valid(crate):
			continue
			
		var distance = characterRoot.global_position.distance_to(crate.global_position)
		
		if distance <= CRATE_PICKUP_RADIUS && health < 0.99:
			health = clamp(health + 0.5, 0.0, 1.0)
			crates_to_remove.append(crate)
	
	for crate in crates_to_remove:
		if is_instance_valid(crate):
			crate.queue_free()
	
func drop_character():
	if started:
		if !character_grounded() || state == "Dead":
			if state != "Dead":
				state = "Falling"
			
			fallStartY = characterRoot.global_position.y
			characterRoot.lock_rotation = false
			characterRoot.mass = 0.1
			selectedhand = null
			characterRoot.apply_torque_impulse(10000 * sign(randf() - 0.5))
			anchoredHand = null
			characterRoot.freeze = false
			
			for hand in handInfo:
				handInfo[hand].Hand.freeze = false
				handInfo[hand].Hand.lock_rotation = false
		
func character_fell():
	if started:
		var fallDistance = characterRoot.global_position.y - fallStartY
		var damage = max(max(fallDistance, 0) * 0.0008 - 0.2, 0)
		
		health = clamp(health - damage, 0.0, 1.0)
		state = "Getting_Up"
		characterRoot.lock_rotation = true
		characterRoot.mass = 100.0
		
func character_died():
	if started && state != "Dead":
		state = "Dead"
		drop_character()
		get_node("UI").get_node("DeathScreen").get_node("Blur").material.set_shader_parameter("blur_amount", 0.0)
		get_node("UI").get_node("DeathScreen").get_node("Blur").material.set_shader_parameter("mix_amount", 0.0)
		get_node("UI").get_node("DeathScreen").visible = true
		get_node("UI").get_node("DeathScreen").get_node("Menu").visible = false
		await get_tree().create_timer(1.6).timeout
		get_node("UI").get_node("InfoScreen").visible = false
		get_node("UI").get_node("DeathScreen").get_node("Menu").visible = true
		get_node("UI").get_node("DeathScreen").get_node("Menu").get_node("RecordLabel").text = "Reached " + str(maxHeight) + " ft"
		get_node("UI").get_node("DeathScreen").get_node("Menu").get_node("RecordInput").text = "Record #" + str(randi_range(10000, 99999))
	
func switch_hand(handName):
	if started:
		if anchoredHand != handName && state == "Upright":
			selectedhand = handName
			armMousePos = null
		
			if anchoredHand:
				characterRoot.freeze = true
			else:
				characterRoot.freeze = false
			
func anchor_hand():
	if started:
		var baseColor = Color.from_hsv(0.56, 0.2, 1)
		var iceThickness = main.get_noise(handInfo[selectedhand].TipMarker.global_position.x, handInfo[selectedhand].TipMarker.global_position.y)
						
		if randf() < iceThickness * 1.2 + 0.2:
			characterRoot.freeze = false
			anchoredHand = selectedhand
			armMousePos = null
			mousePosWhenAnchor = get_viewport().get_mouse_position()
			rootPosWhenAnchor = characterRoot.global_position
			spawn_particle_burst(get_node("AnchorParticles"), handInfo[selectedhand].Hand, handInfo[selectedhand].Hand.get_node("PickTip").global_position, baseColor, 4, 0.0, 0.05, 0.1)
		
			for hand in handInfo:
				if hand == selectedhand:
					handInfo[hand].Hand.freeze = true
					handInfo[hand].Hand.lock_rotation = true
				else:
					handInfo[hand].Hand.freeze = false
					handInfo[hand].Hand.lock_rotation = false
		else:
			spawn_particle_burst(get_node("SlipParticles"), handInfo[selectedhand].Hand, handInfo[selectedhand].Hand.get_node("PickTip").global_position, baseColor, 4, 0.0, 0.05, 0.1)
			drop_character()

func _unhandled_input(_event):
	if Input.is_action_just_pressed("mouse_left"):
		if selectedhand && handInfo[selectedhand] && anchoredHand != selectedhand:
			anchor_hand()
	elif Input.is_action_just_pressed("quit"):
		character_died()
	elif Input.is_action_just_pressed("switch_left_hand"):
		switch_hand("Left")
	elif Input.is_action_just_pressed("switch_right_hand"):
		switch_hand("Right")

func _ready():
	http.request_completed.connect(_on_request_completed)
	character = self.get_node("Climber")
	characterRoot = character.get_node("UpperBody")
	handInfo.Left.Hand = character.get_node("HandL")
	handInfo.Right.Hand = character.get_node("HandR")
	handInfo.Left.ShoulderMarker = characterRoot.get_node("ShoulderL")
	handInfo.Right.ShoulderMarker = characterRoot.get_node("ShoulderR")
	handInfo.Left.CenterMarker = handInfo.Left.Hand.get_node("HandCenter")
	handInfo.Right.CenterMarker = handInfo.Right.Hand.get_node("HandCenter")
	handInfo.Left.TipMarker = handInfo.Left.Hand.get_node("PickTip")
	handInfo.Right.TipMarker = handInfo.Right.Hand.get_node("PickTip")
	characterStartingY = character.get_node("UpperBody").global_position.y
	characterRoot.mass = 100.0
	get_node("UI").get_node("MenuScreen").get_node("PlayButton").connect("pressed", start_button_press)
	get_node("UI").get_node("InfoScreen").get_node("QuitButton").connect("pressed", character_died)
	get_node("UI").get_node("DeathScreen").get_node("Menu").get_node("SubmitButton").connect("pressed", submit_button_press)
	
	for child in character.get_children():
		if child is RigidBody2D:
			characterRigidBodies.append(child)
			child.contact_monitor = true
			child.max_contacts_reported = 8
	
func _process(delta: float) -> void:
	if state == "Dead":
		get_node("UI").get_node("DeathScreen").get_node("Blur").material.set_shader_parameter("blur_amount", lerp(get_node("UI").get_node("DeathScreen").get_node("Blur").material.get_shader_parameter("blur_amount"), 4.0, delta * 0.6))
		get_node("UI").get_node("DeathScreen").get_node("Blur").material.set_shader_parameter("mix_amount", lerp(get_node("UI").get_node("DeathScreen").get_node("Blur").material.get_shader_parameter("mix_amount"), 0.6, delta * 0.6))
	if started:
		var height = roundi(max((-characterRoot.global_position.y + characterStartingY) / PIXELS_PER_FOOT, 0))
		
		framenumber += 1
		crate_check_timer += delta
		
		if state != "Dead" && crate_check_timer >= CRATE_CHECK_INTERVAL:
			crate_check_timer = 0.0
			check_for_crate_pickups()
			
		if state == "Getting_Up":
			if abs(characterRoot.rotation) > 0.01:
				if framenumber % 2 == 0:
					characterRoot.rotation = characterRoot.rotation - min(abs(characterRoot.rotation) * delta * 8, abs(characterRoot.rotation)) * sign(characterRoot.rotation)
			else:
				state = "Upright"
				
		if (health <= 0 || lastPosY - characterRoot.global_position.y > delta * 1000000) && state != "Dead":
			character_died()
			
		if state != "Dead":
			if state == "Falling":
				fallStartY = min(fallStartY, characterRoot.global_position.y)
				
				for child in character.get_children():
					if child is RigidBody2D:
						if is_touching_static(child):
							character_fell()
							break
			
			if state == "Upright":
				if selectedhand:
					if anchoredHand != selectedhand:
						var target = handInfo[selectedhand].ShoulderMarker.get_local_mouse_position()
						var local = target / max(target.length(), 0.01) * clamp(target.length(), abs(UPPER_ARM_LENGTH - LOWER_ARM_LENGTH), UPPER_ARM_LENGTH + LOWER_ARM_LENGTH)
						
						if !armMousePos:
							armMousePos = handInfo[selectedhand].CenterMarker.global_position - handInfo[selectedhand].ShoulderMarker.global_position
							
						armMousePos = lerp(armMousePos, local, delta * 12)
						var limited = armMousePos * shapecast_distance(handInfo[selectedhand].Hand.get_node("HandCollider"), handInfo[selectedhand].ShoulderMarker.global_position + handInfo[selectedhand].Hand.get_node("HandCollider").position, armMousePos)
						
						teleport_rigidbody(handInfo[selectedhand].ShoulderMarker.global_position - handInfo[selectedhand].CenterMarker.position + limited, handInfo[selectedhand].Hand, 0)
					else:
						var target = rootPosWhenAnchor + (mousePosWhenAnchor - get_viewport().get_mouse_position()) * 1.8 + handInfo[selectedhand].ShoulderMarker.position - handInfo[selectedhand].CenterMarker.global_position
						var local = target / max(target.length(), 0.01) * clamp(target.length(), abs(UPPER_ARM_LENGTH - LOWER_ARM_LENGTH), UPPER_ARM_LENGTH + LOWER_ARM_LENGTH) - rootPosWhenAnchor - handInfo[selectedhand].ShoulderMarker.position + handInfo[selectedhand].CenterMarker.global_position
						
						if !armMousePos:
							armMousePos = Vector2()
						
						#armMousePos = lerp(armMousePos, local, delta * 8)
						#var limited = armMousePos * shapecast_distance(characterRoot.get_node("BodyCollider"), rootPosWhenAnchor + characterRoot.get_node("BodyCollider").position, armMousePos)
						#var d = rootPosWhenAnchor + armMousePos - characterRoot.get_node("BodyCollider").global_position
						#var limited = d * shapecast_distance(characterRoot.get_node("BodyCollider"), characterRoot.get_node("BodyCollider").global_position, d)
						#var limitedX = armMousePos.x * shapecast_distance(characterRoot.get_node("BodyCollider"), rootPosWhenAnchor + characterRoot.get_node("BodyCollider").position, Vector2(armMousePos.x, 0))
						#var limitedY = armMousePos.y * shapecast_distance(characterRoot.get_node("BodyCollider"), rootPosWhenAnchor + characterRoot.get_node("BodyCollider").position + Vector2(0, limitedX), Vector2(0, armMousePos.y))
						var poos = Vector2(rootPosWhenAnchor.x, rootPosWhenAnchor.y * 0.2 + characterRoot.get_node("BodyCollider").global_position.y * 0.8)
						var d = rootPosWhenAnchor + local - poos
						var limited = poos + d * shapecast_distance(characterRoot.get_node("BodyCollider"), poos, d) - rootPosWhenAnchor
						armMousePos = lerp(armMousePos, limited, delta * 4)
						
						teleport_rigidbody(rootPosWhenAnchor + armMousePos, characterRoot, 0)
						
				if character_grounded():
					stamina = clamp(stamina + delta * 0.25, 0, 1)
				else:
					stamina = clamp(stamina - delta * 0.03, 0, 1)
				
					if stamina == 0 || !anchoredHand:
						drop_character()
				
			if anchoredHand:
				maxHeight = max(maxHeight, height)
			
		healthBarValue = lerp(healthBarValue, health, delta * 8)
		get_node("UI").get_node("InfoScreen").get_node("StaminaBar").get_node("ValueBar").value = stamina * 100
		get_node("UI").get_node("InfoScreen").get_node("HealthBar").get_node("ValueBar").value = healthBarValue * 100
		get_node("UI").get_node("InfoScreen").get_node("HeightLabel").text = str(height) + " ft"
		lastPosY = characterRoot.global_position.y
