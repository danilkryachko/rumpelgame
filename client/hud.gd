extends CanvasLayer

var selected_block: int = 1
var block_names = {
	1: "Stone",
	2: "Dirt",
	3: "Wood",
	4: "Leaves"
}
var labels = []

func _ready():
	# Crosshair (Прицел)
	var crosshair = ColorRect.new()
	crosshair.custom_minimum_size = Vector2(4, 4)
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.color = Color(1, 1, 1, 0.8)
	add_child(crosshair)
	
	# Хотбар
	var hbox = HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hbox.set_offset(SIDE_BOTTOM, -20)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	
	for i in range(1, 5):
		var panel = PanelContainer.new()
		panel.custom_minimum_size = Vector2(100, 60)
		
		var label = Label.new()
		label.text = str(i) + ": " + block_names[i]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		
		panel.add_child(label)
		hbox.add_child(panel)
		labels.append(panel)
		
	add_child(hbox)
	update_ui()

func _input(event):
	if event is InputEventKey and event.pressed:
		if event.keycode >= KEY_1 and event.keycode <= KEY_4:
			selected_block = event.keycode - KEY_0
			update_ui()

func update_ui():
	for i in range(labels.size()):
		var panel = labels[i]
		if i + 1 == selected_block:
			panel.modulate = Color(1, 1, 0) # Желтый цвет для выбранного
		else:
			panel.modulate = Color(1, 1, 1)

func get_selected_block() -> int:
	return selected_block
