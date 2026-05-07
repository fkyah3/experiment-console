class_name ConfigManager
extends RefCounted

var config_path: String = "user://config.cfg"
var api_key: String = ""
var experiments_path: String = "user://experiments/"
var templates_path: String = "user://templates/"
var sessions_path: String = "user://sessions/"

var _dirty: bool = false


func _init() -> void:
	load_config()


func load_config() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(config_path)
	if err != OK:
		return

	api_key = cfg.get_value("api", "key", "")
	experiments_path = cfg.get_value("paths", "experiments", "user://experiments/")
	templates_path = cfg.get_value("paths", "templates", "user://templates/")
	_dirty = false


func save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("api", "key", api_key)
	cfg.set_value("paths", "experiments", experiments_path)
	cfg.set_value("paths", "templates", templates_path)
	cfg.save(config_path)
	_dirty = false
	_make_dirs()


func open_in_explorer(path: String) -> void:
	var abs_path := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(abs_path)
	OS.shell_open(abs_path)


func _make_dirs() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(experiments_path))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(templates_path))
