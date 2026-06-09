extends Node

func _ready():
	print("Starting local Go server...")
	
	# Запуск собранного бинарника Go сервера
	# На Mac/Linux используем ./server/server
	var exe_path = ProjectSettings.globalize_path("res://../server/tmp/main")
	
	# Запускаем как отдельный процесс
	var pid = OS.create_process(exe_path, [])
	if pid == -1:
		print("Failed to start local Go server! Is it built?")
	else:
		print("Go server started with PID: ", pid)
	
	# Ждем 1 секунду, чтобы сервер успел открыть TCP порт
	await get_tree().create_timer(1.0).timeout
	
	print("Adding GameClient node...")
	var client = ClassDB.instantiate("GameClient")
	add_child(client)
	
	print("Adding HUD...")
	var hud_script = load("res://hud.gd")
	if hud_script:
		var hud = hud_script.new()
		hud.name = "HUD"
		add_child(hud)
	else:
		print("Failed to load hud.gd!")

func _exit_tree():
	# TODO: kill the server process when Godot closes
	pass
