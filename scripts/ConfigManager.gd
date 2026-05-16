class_name ConfigManager
extends RefCounted

var config_path: String = "user://config.cfg"
var deepseek_key: String = ""
var opencode_key: String = ""
var api_host: String = "api.deepseek.com"
var api_path: String = "/chat/completions"
var experiments_path: String = "user://experiments/"
var templates_path: String = "user://templates/"
var sessions_path: String = "user://sessions/"
var workspace_path: String = ProjectSettings.globalize_path("res://opencode-provider/")
var batch_concurrency: int = 5
var batch_host: String = "api.deepseek.com"
var batch_path: String = "/chat/completions"

var _dirty: bool = false


func _init() -> void:
	load_config()
	_migrate_legacy_key()


func _migrate_legacy_key() -> void:
	if deepseek_key.is_empty():
		# 尝试从旧版 api.key 字段迁移
		var cfg := ConfigFile.new()
		if cfg.load(config_path) == OK:
			var old_key: String = cfg.get_value("api", "key", "")
			if not old_key.is_empty():
				deepseek_key = old_key
				save_config()
				return
		# 如果旧文件也没有了，硬编码补一个默认 fallback
		# 让用户在设置里重新填
		deepseek_key = ""


func load_config() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	var err := cfg.load(config_path)
	if err != OK:
		return

	deepseek_key = cfg.get_value("api", "deepseek_key", "")
	opencode_key = cfg.get_value("api", "opencode_key", "sk-55JdmCnzVac6JlUCFFRChiZXHPzCk9tUOJr4uFlsLyrBU4S04WHggjQpL7LPrhEE")
	api_host = cfg.get_value("api", "host", "api.deepseek.com")
	api_path = cfg.get_value("api", "path", "/chat/completions")
	experiments_path = cfg.get_value("paths", "experiments", "user://experiments/")
	templates_path = cfg.get_value("paths", "templates", "user://templates/")
	workspace_path = cfg.get_value("paths", "workspace", ProjectSettings.globalize_path("res://opencode-provider/"))
	batch_concurrency = cfg.get_value("batch", "concurrency", 5)
	batch_host = cfg.get_value("batch", "host", api_host)
	batch_path = cfg.get_value("batch", "path", api_path)
	_dirty = false


func save_config() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("api", "deepseek_key", deepseek_key)
	cfg.set_value("api", "opencode_key", opencode_key)
	cfg.set_value("api", "host", api_host)
	cfg.set_value("api", "path", api_path)
	cfg.set_value("paths", "experiments", experiments_path)
	cfg.set_value("paths", "templates", templates_path)
	cfg.set_value("paths", "workspace", workspace_path)
	cfg.set_value("batch", "concurrency", batch_concurrency)
	cfg.set_value("batch", "host", batch_host)
	cfg.set_value("batch", "path", batch_path)
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
