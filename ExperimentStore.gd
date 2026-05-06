class_name ExperimentStore
extends RefCounted

var _experiments_dir: String = "user://experiments/"
var _templates_dir: String = "user://templates/"


func _init(experiments_path: String = "user://experiments/", templates_path: String = "user://templates/") -> void:
	_experiments_dir = experiments_path
	_templates_dir = templates_path
	DirAccess.make_dir_recursive_absolute(_experiments_dir)
	DirAccess.make_dir_recursive_absolute(_templates_dir)


func save_experiment(
	title: String,
	model: String,
	thinking: String,
	effort: String,
	max_tokens: int,
	temperature: float,
	messages: Array,
	raw_messages: Array,
	request_body: String,
	response_body: String,
	usage: Dictionary,
	notes: String
) -> String:
	var now := Time.get_datetime_dict_from_system()
	var ts := "%04d%02d%02d_%02d%02d" % [now.year, now.month, now.day, now.hour, now.minute]

	var safe_title := _sanitize_filename(title)
	safe_title = safe_title.left(20)
	if safe_title.is_empty():
		safe_title = "untitled"

	var fname := "%s_%s.md" % [ts, safe_title]
	var fpath := _experiments_dir.path_join(fname)

	if FileAccess.file_exists(fpath):
		var n := 1
		while FileAccess.file_exists(_experiments_dir.path_join("%s_%s_%d.md" % [ts, safe_title, n])):
			n += 1
		fname = "%s_%s_%d.md" % [ts, safe_title, n]
		fpath = _experiments_dir.path_join(fname)

	var created := "%04d-%02d-%02dT%02d:%02d:%02d+08:00" % [now.year, now.month, now.day, now.hour, now.minute, now.second]

	var file := FileAccess.open(fpath, FileAccess.WRITE)
	if file == null:
		push_error("ExperimentStore: 无法创建文件 " + fpath)
		return ""

	file.store_string("---\n")
	file.store_string("type: \"experiment\"\n")
	file.store_string("created_at: \"%s\"\n" % created)
	file.store_string("title: \"%s\"\n" % title)
	file.store_string("model: \"%s\"\n" % model)
	file.store_string("thinking: \"%s\"\n" % thinking)
	file.store_string("effort: \"%s\"\n" % effort)
	file.store_string("max_tokens: %d\n" % max_tokens)
	file.store_string("temperature: %.1f\n" % temperature)
	file.store_string("---\n\n")

	file.store_string("## messages（原始积木，reasoning 与 content 分离）\n\n")
	file.store_string("```json\n")
	file.store_string(JSON.stringify(raw_messages, "\t"))
	file.store_string("\n```\n\n")

	file.store_string("## messages（API 格式，发送到服务器的实际内容）\n\n")
	file.store_string("```json\n")
	file.store_string(JSON.stringify(messages, "\t"))
	file.store_string("\n```\n\n")

	file.store_string("## request\n\n")
	file.store_string("```json\n")
	file.store_string(request_body)
	file.store_string("\n```\n\n")

	file.store_string("## response\n\n")
	file.store_string("```json\n")
	file.store_string(response_body)
	file.store_string("\n```\n\n")

	if not usage.is_empty():
		file.store_string("## usage\n\n")
		file.store_string("```json\n")
		file.store_string(JSON.stringify(usage, "\t"))
		file.store_string("\n```\n\n")

	if not notes.is_empty():
		file.store_string("## notes\n\n")
		file.store_string(notes)
		file.store_string("\n")

	file.close()
	return fpath


func list_experiments() -> Array[Dictionary]:
	var dir := DirAccess.open(_experiments_dir)
	if dir == null:
		return []

	var result: Array[Dictionary] = []
	dir.list_dir_begin()
	var fname := dir.get_next()
	while not fname.is_empty():
		if fname.ends_with(".md"):
			var meta := _read_frontmatter(_experiments_dir.path_join(fname))
			if not meta.is_empty():
				result.append(meta)
		fname = dir.get_next()
	dir.list_dir_end()

	result.sort_custom(func(a: Dictionary, b: Dictionary) -> int:
		var at: String = a.get("created_at", "")
		var bt: String = b.get("created_at", "")
		return bt.naturalcasecmp_to(at)
	)
	return result


func save_template(name: String, model: String, thinking: String, effort: String, max_tokens: int, messages: Array) -> void:
	var fname := _sanitize_filename(name) + ".json"
	if fname.is_empty():
		fname = "untitled.json"
	var fpath := _templates_dir.path_join(fname)
	var data := {
		"name": name,
		"model": model,
		"thinking": thinking,
		"effort": effort,
		"max_tokens": max_tokens,
		"messages": messages,
	}
	var file := FileAccess.open(fpath, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()


func list_templates() -> Array[Dictionary]:
	var dir := DirAccess.open(_templates_dir)
	if dir == null:
		return []
	var result: Array[Dictionary] = []
	dir.list_dir_begin()
	var fname := dir.get_next()
	while not fname.is_empty():
		if fname.ends_with(".json"):
			var fpath := _templates_dir.path_join(fname)
			var content := FileAccess.get_file_as_string(fpath)
			if not content.is_empty():
				var parsed = JSON.parse_string(content) as Dictionary
				if parsed != null:
					parsed["path"] = fpath
					result.append(parsed)
		fname = dir.get_next()
	dir.list_dir_end()
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> int:
		return a.get("name", "").naturalcasecmp_to(b.get("name", ""))
	)
	return result


func load_template(name: String) -> Dictionary:
	for t in list_templates():
		if t.get("name", "") == name:
			return t
	return {}


func delete_template(name: String) -> void:
	for t in list_templates():
		if t.get("name", "") == name:
			var fpath: String = t.get("path", "")
			if not fpath.is_empty():
				DirAccess.remove_absolute(fpath)
			return


func seed_builtin_templates() -> void:
	if not list_templates().is_empty():
		return
	# 中文锚定测试
	save_template("中文锚定测试", "deepseek-v4-flash", "enabled", "high", 4096, [
		{"role": "system", "content": "你是一个中文助手，请始终用中文思考和回复。代码、路径、工具名保持原文。"},
		{"role": "user", "content": "请用中文回答，什么是递归？"},
	])
	# 前置条件测试
	save_template("前置条件测试", "deepseek-v4-flash", "enabled", "high", 4096, [
		{"role": "user", "content": "我表妹叫我奶奶什么？"},
	])
	save_template("自定义（空）", "deepseek-v4-flash", "enabled", "high", 4096, [])


func _read_frontmatter(fpath: String) -> Dictionary:
	var content := FileAccess.get_file_as_string(fpath)
	if content.is_empty():
		return {}

	var meta: Dictionary = {}
	meta["path"] = fpath

	if content.begins_with("---"):
		var end_idx := content.find("---\n", 3)
		if end_idx == -1:
			end_idx = content.find("---\r\n", 3)
		if end_idx != -1:
			var fm_str := content.substr(3, end_idx - 3).strip_edges()
			for line in fm_str.split("\n"):
				line = line.strip_edges()
				if line.is_empty():
					continue
				var colon := line.find(":")
				if colon != -1:
					var key := line.substr(0, colon).strip_edges()
					var val := line.substr(colon + 1).strip_edges().strip_escapes().trim_prefix('"').trim_suffix('"')
					meta[key] = val

	return meta


func _sanitize_filename(text: String) -> String:
	var illegal := [":", "\\", "/", "*", "?", "\"", "<", ">", "|"]
	var result := text
	for c in illegal:
		result = result.replace(c, "")
	result = result.replace(" ", "_")
	return result.strip_edges()
