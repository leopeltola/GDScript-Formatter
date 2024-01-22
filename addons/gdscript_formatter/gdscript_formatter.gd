@tool
extends EditorPlugin

var _preference: Resource
var _shortcut: Shortcut
var _has_format_tool_item: bool = false
var _install_task_id: int = -1
var _connection_list: Array[Resource] = []


func _init() -> void:
	var shortcur_res_file := (get_script() as Resource).resource_path.get_base_dir().path_join(
		"format_shortcut.tres"
	)
	if FileAccess.file_exists(shortcur_res_file):
		_shortcut = load(shortcur_res_file)
	if not is_instance_valid(_shortcut):
		var default_shortcut := InputEventKey.new()
		default_shortcut.echo = false
		default_shortcut.pressed = true
		default_shortcut.keycode = KEY_F
		default_shortcut.shift_pressed = true
		default_shortcut.alt_pressed = true

		_shortcut = Shortcut.new()
		_shortcut.events.push_back(default_shortcut)
		ResourceSaver.save(_shortcut, shortcur_res_file)

	_shortcut.changed.connect(update_shortcut)

	var preference_res_file = shortcur_res_file.get_base_dir().path_join("format_preference.tres")
	if FileAccess.file_exists(preference_res_file):
		_preference = load(preference_res_file)
	if not is_instance_valid(_preference):
		_preference = Resource.new()
		var script = GDScript.new()
		script.source_code = """@tool
extends Resource
## How many characters per line to allow.
@export var line_length:=100
## If trueWill skip safety checks.
@export var fast_but_unsafe:=false
"""
		_preference.set_script(script)
		ResourceSaver.save(_preference, preference_res_file)


func _enter_tree() -> void:
	if not _has_command("gdformat"):
		print_rich(
			'[color=yellow]GDScript Formatter: the command "gdformat" can\'t be found in your envrionment.[/color]'
		)
		_add_format_tool_item()
	if not _has_command("pip"):
		print_rich(
			'[color=yellow]Installs gdtoolkit is required "pip".\n\t Please install it and ensure it can be found inyour envrionment.[/color]'
		)
		return
	EditorInterface.get_command_palette().add_command(
		"Format GDScript",
		"GDScript Formatter/Format GDScript",
		Callable(self, "format_script"),
		_shortcut.get_as_text()
	)
	add_tool_menu_item("GDScriptFormatter: Install/Update gdtoolkit", install_or_update_gdtoolkit)
	update_shortcut()


func _exit_tree() -> void:
	(
		EditorInterface
		. get_command_palette()
		. remove_command(
			"GDScript Formatter/Format GDScript",
		)
	)
	remove_tool_menu_item("GDScriptFormatter: Install/Update gdtoolkit")
	if _has_format_tool_item:
		remove_tool_menu_item("GDScriptFormatter: Format script")


func _shortcut_input(event: InputEvent) -> void:
	if _shortcut.matches_event(event) and event.is_pressed() and not event.is_echo():
		if format_script():
			get_tree().root.set_input_as_handled()


func format_script() -> bool:
	if not EditorInterface.get_script_editor().is_visible_in_tree():
		return false
	var current_script = EditorInterface.get_script_editor().get_current_script()
	if not is_instance_valid(current_script) or not current_script is GDScript:
		return false
	var text_edit: CodeEdit = (
		EditorInterface.get_script_editor().get_current_editor().get_base_editor()
	)
	var line := text_edit.get_caret_line()
	var colume := text_edit.get_caret_column()

	text_edit.set_search_flags(1)
	const tmp_file = "res://addons/gdscript_formatter/.tmp.gd"
	var f = FileAccess.open(tmp_file, FileAccess.WRITE)
	if not is_instance_valid(f):
		printerr("GDScript Formatter Error: can't create tmp file.")
		return false
	f.store_string(text_edit.text)
	f.close()

	var output := []
	var args := [
		ProjectSettings.globalize_path(tmp_file), "--line-length=%d" % _preference.line_length
	]
	if _preference.fast_but_unsafe:
		args.push_back("--fast")
	var err = OS.execute("gdformat", args, output)

	if err == OK:
		f = FileAccess.open(tmp_file, FileAccess.READ)
		text_edit.text = f.get_as_text()
		f.close()
		text_edit.set_caret_line(line)
		text_edit.set_caret_column(colume)
		text_edit.center_viewport_to_caret()
		DirAccess.remove_absolute(tmp_file)
		return true
	else:
		printerr("Format GDScript failed: ", current_script.resource_path)
		DirAccess.remove_absolute(tmp_file)
		return false


func install_or_update_gdtoolkit() -> void:
	if _install_task_id >= 0:
		print_rich("Already installing or updating gdformat, please be patient.")
		return
	if not _has_command("pip"):
		printerr(
			"Install GDScript Formatter Failed: pip is required, please ensure it can be found in your environment."
		)
		return
	_install_task_id = WorkerThreadPool.add_task(
		_install_or_update_gdtoolkit, true, "Install or update gdtoolkit."
	)
	while _install_task_id >= 0:
		if not WorkerThreadPool.is_task_completed(_install_task_id):
			await get_tree().process_frame
		else:
			_install_task_id = -1


func update_shortcut() -> void:
	for obj in _connection_list:
		obj.changed.disconnect(update_shortcut)

	_connection_list.clear()

	for event: InputEvent in _shortcut.events:
		if is_instance_valid(event):
			event.changed.connect(update_shortcut)
			_connection_list.push_back(event)

	(
		EditorInterface
		. get_command_palette()
		. remove_command(
			"GDScript Formatter/Format GDScript",
		)
	)

	EditorInterface.get_command_palette().add_command(
		"Format GDScript",
		"GDScript Formatter/Format GDScript",
		Callable(self, "format_script"),
		_shortcut.get_as_text()
	)


func _install_or_update_gdtoolkit():
	var has_gdformat = _has_command("gdformat")
	if has_gdformat:
		print("-- Begin update gdtoolkit.")
	else:
		print("-- Begin install gdtoolkit.")
	var output := []
	var err := OS.execute("pip3", ["install", "gdtoolkit"], output)
	if err == OK:
		if has_gdformat:
			print("-- Update gdtoolkit successfully.")
		else:
			print("-- Install gdtoolkit successfully.")
		if not _has_format_tool_item:
			_add_format_tool_item()
	else:
		if has_gdformat:
			printerr("-- Update gdtoolkit failed, exit code: ", err)
		else:
			printerr("-- Install gdtoolkit failed, exit code: ", err)
		printerr("\tPlease check below for more details.")
		print("\n".join(output))


func _add_format_tool_item() -> void:
	add_tool_menu_item("GDScriptFormatter: Format script", format_script)
	_has_format_tool_item = true


func _has_command(command: String) -> bool:
	var output := []
	var err := OS.execute(command, ["--version"], output)
	return err == OK
