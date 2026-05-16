class_name ToolExecutor
extends RefCounted

var workspace_path: String = ""


func list_dir(dir_path: String) -> String:
	var base := workspace_path
	if not base.ends_with("/"):
		base += "/"
	var dpath := dir_path
	if not dpath.begins_with("E:") and not dpath.begins_with("e:") and not dpath.begins_with("C:") and not dpath.begins_with("c:"):
		dpath = base.path_join(dir_path)
	var dir := DirAccess.open(dpath)
	if dir == null:
		return "[目录不存在: %s]" % dir_path
	var result: String = ""
	dir.list_dir_begin()
	var fname := dir.get_next()
	while not fname.is_empty():
		if dir.current_is_dir():
			result += "[DIR]  %s/\n" % fname
		else:
			result += "[FILE] %s\n" % fname
		fname = dir.get_next()
	dir.list_dir_end()
	return result.strip_edges()


func read_file(file_path: String) -> String:
	var fpath := _resolve_path(file_path)
	if fpath.is_empty():
		return "[文件不存在: %s]" % file_path
	if FileAccess.file_exists(fpath):
		return FileAccess.get_file_as_string(fpath)
	return "[文件不存在: %s]" % file_path


func write_file(file_path: String, content: String) -> void:
	var shadow := _shadow_path(file_path)
	var dir_path := shadow.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir_path)
	var file := FileAccess.open(shadow, FileAccess.WRITE)
	if file:
		file.store_string(content)
		file.close()


func scan_key_files(max_return: int) -> Array[String]:
	var result: Array[String] = []
	var priority: Array[String] = []
	var rest: Array[String] = []
	_scan_dir("", priority, rest)
	priority.sort()
	rest.sort()
	for p in priority:
		if result.size() >= max_return:
			break
		result.append(p)
	for r in rest:
		if result.size() >= max_return:
			break
		result.append(r)
	return result


func _resolve_path(file_path: String) -> String:
	var base := workspace_path
	if not base.ends_with("/"):
		base += "/"
	var fpath := file_path
	if not fpath.begins_with("E:") and not fpath.begins_with("e:") and not fpath.begins_with("C:") and not fpath.begins_with("c:"):
		fpath = base.path_join(file_path)
	var shadow := _shadow_path(file_path)
	if FileAccess.file_exists(shadow):
		return shadow
	if FileAccess.file_exists(fpath):
		return fpath
	return ""


func _shadow_path(file_path: String) -> String:
	return ProjectSettings.globalize_path("user://opencode-shadow/").path_join(file_path)


func _scan_dir(rel: String, priority: Array[String], rest: Array[String]) -> void:
	var base := workspace_path
	var dir := DirAccess.open(base.path_join(rel))
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while not fname.is_empty():
		if fname.begins_with("."):
			fname = dir.get_next()
			continue
		var full_rel := rel.path_join(fname) if not rel.is_empty() else fname
		if dir.current_is_dir():
			if fname == "node_modules":
				fname = dir.get_next()
				continue
			_scan_dir(full_rel, priority, rest)
		else:
			if fname.ends_with(".ts") or fname.ends_with(".tsx") or fname.ends_with(".js") or fname.ends_with(".json") or fname.ends_with(".md"):
				if fname.contains("snapshot"):
					rest.append(full_rel)
				elif fname.contains("provider") or fname.contains("index") or fname.contains("main") or fname.contains("core") or fname.contains("schema") or fname.contains("auth"):
					priority.append(full_rel)
				else:
					rest.append(full_rel)
		fname = dir.get_next()
	dir.list_dir_end()
