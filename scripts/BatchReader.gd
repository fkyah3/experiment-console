extends Control
class_name BatchReader

signal back_requested

var _batch_dir: String = ""
var _round_files: Array[String] = []
var _selected_idx: int = -1
var _summary_data: Dictionary = {}
var _summary_rows: Array[Dictionary] = []
var _experiments_dir: String = "user://experiments/"


func set_experiments_dir(path: String) -> void:
	_experiments_dir = path


@onready var dir_label: Label = %DirLabel
@onready var refresh_btn: Button = %RefreshBtn
@onready var back_btn: Button = %BackBtn
@onready var batch_select: OptionButton = %BatchSelect
@onready var params_label: Label = %ParamsLabel
@onready var stats_label: Label = %StatsLabel
@onready var round_list: ItemList = %RoundList
@onready var prompt_view: TextEdit = %PromptView
@onready var reasoning_view: TextEdit = %ReasoningView
@onready var content_view: TextEdit = %ContentView
@onready var round_title: Label = %RoundTitle
@onready var debug_label: Label = %DebugLabel
@onready var round_detail_label: Label = %RoundDetailLabel
@onready var prev_btn: Button = %PrevBtn
@onready var next_btn: Button = %NextBtn


func _ready() -> void:
	refresh_btn.pressed.connect(_refresh_batch_list)
	back_btn.pressed.connect(func(): back_requested.emit())
	batch_select.item_selected.connect(_on_batch_selected)
	round_list.item_selected.connect(_on_round_list_selected)
	prev_btn.pressed.connect(_on_prev)
	next_btn.pressed.connect(_on_next)
	_refresh_batch_list()


func _refresh_batch_list() -> void:
	batch_select.clear()
	batch_select.add_item("— 选择批次目录 —")
	batch_select.selected = 0

	var all_entries: Array[String] = []
	var seen: Dictionary = {}

	for base in [_experiments_dir]:
		var dir := DirAccess.open(base)
		if dir == null:
			continue
		dir.list_dir_begin()
		var fname := dir.get_next()
		while not fname.is_empty():
			if fname.begins_with("."):
				fname = dir.get_next()
				continue
			if dir.current_is_dir() and not seen.has(fname):
				all_entries.append(base.path_join(fname))
				seen[fname] = true
			fname = dir.get_next()
		dir.list_dir_end()

	all_entries.sort()

	if all_entries.is_empty():
		dir_label.text = "未找到批次目录"
		return

	dir_label.text = "找到 %d 个批次" % all_entries.size()
	for entry_path in all_entries:
		var short := entry_path.get_file()
		batch_select.add_item(short)
		batch_select.set_item_metadata(batch_select.item_count - 1, entry_path)


func _on_batch_selected(idx: int) -> void:
	if idx <= 0:
		return
	_batch_dir = batch_select.get_item_metadata(idx)
	var dir_name := batch_select.get_item_text(idx)
	dir_label.text = dir_name
	debug_label.text = ""
	_load_summary()
	_load_round_files()


func _load_summary() -> void:
	var summary_path := _batch_dir.path_join("_summary.md")
	var content := FileAccess.get_file_as_string(summary_path)
	if content.is_empty():
		debug_label.text = "未找到 _summary.md: " + summary_path
		params_label.text = ""
		stats_label.text = ""
		prompt_view.text = ""
		reasoning_view.text = ""
		content_view.text = ""
		round_detail_label.text = ""
		round_title.text = "选择一轮查看"
		round_list.clear()
		return

	var lines := content.split("\n")
	_summary_data = {}
	_summary_rows.clear()

	var in_detail_table := false
	var in_stats_table := false
	var in_time_table := false
	var header_skipped := false

	for line in lines:
		if line.begins_with("- **") and line.contains("**:"):
			var key_end := line.find("**:")
			var key := line.substr(4, key_end - 4)
			var val := line.substr(key_end + 3).strip_edges()
			_summary_data[key] = val

		if line.begins_with("## 汇总统计"):
			in_stats_table = true
			in_detail_table = false
			in_time_table = false
			header_skipped = false
			continue

		if line.begins_with("## 每轮明细"):
			in_detail_table = true
			in_stats_table = false
			in_time_table = false
			header_skipped = false
			continue

		if line.begins_with("## 耗时与速度"):
			in_time_table = true
			in_stats_table = false
			in_detail_table = false
			header_skipped = false
			continue

		if line.begins_with("## "):
			in_detail_table = false
			in_stats_table = false
			in_time_table = false
			continue

		if in_stats_table and line.begins_with("|"):
			if not header_skipped:
				header_skipped = true
				continue
			var cells := _parse_cells(line)
			if cells.size() >= 2:
				_summary_data[cells[0]] = cells[1]

		if in_time_table and line.begins_with("|"):
			if not header_skipped:
				header_skipped = true
				continue
			var cells := _parse_cells(line)
			if cells.size() >= 2:
				_summary_data[cells[0]] = cells[1]

		if in_detail_table and line.begins_with("|"):
			if line.contains(":-:"):
				header_skipped = true
				continue
			if not header_skipped:
				header_skipped = true
				continue
			var cells := _parse_cells(line)
			if cells.size() < 7:
				continue
			var row: Dictionary = {}
			row["index"] = cells[0]
			row["reasoning_tokens"] = cells[1]
			if cells[2].contains("s"):
				row["duration"] = cells[2]
				row["tokens_per_sec"] = cells[3]
				row["reasoning_lang"] = cells[4]
				row["output_lang"] = cells[5]
				row["reasoning_chars"] = cells[6]
				row["output_chars"] = cells[7]
				row["first_line"] = cells[8] if cells.size() > 8 else ""
			else:
				row["reasoning_lang"] = cells[2]
				row["output_lang"] = cells[3]
				row["reasoning_chars"] = cells[4]
				row["output_chars"] = cells[5]
				row["first_line"] = cells[6] if cells.size() > 6 else ""
			_summary_rows.append(row)

	_update_display()


func _parse_cells(line: String) -> Array[String]:
	var result: Array[String] = []
	var parts := line.split("|")
	for p in parts:
		var trimmed := p.strip_edges()
		if not trimmed.is_empty():
			result.append(trimmed)
	return result


func _update_display() -> void:
	var d := _summary_data
	params_label.text = ""
	for key in ["模型", "思考模式", "推理强度", "max_tokens", "温度"]:
		var v: String = d.get(key, "")
		if not v.is_empty():
			params_label.text += "%s: %s\n" % [key, v]
	params_label.text += "总计: %s  成功: %s  失败: %s" % [d.get("总次数", "?"), d.get("成功", "?"), d.get("失败", "?")]
	_update_stats_view()
	_populate_round_list()


func _update_stats_view() -> void:
	var d := _summary_data
	stats_label.text = ""
	var labels := {
		"reasoning_tokens 最小值": "rt最小值",
		"reasoning_tokens 最大值": "rt最大值",
		"reasoning_tokens 平均值": "rt平均值",
		"reasoning_tokens 中位数": "rt中位数",
		"波动倍数（max/min）": "波动倍数",
		"prompt_tokens 平均值": "prompt_avg",
		"completion_tokens 平均值": "completion_avg",
		"total_tokens 平均值": "total_avg",
	}
	for key in labels:
		var v: String = d.get(key, "")
		if not v.is_empty():
			stats_label.text += "%s: %s\n" % [labels[key], v]
	var zh: String = d.get("reasoning 中文占比", "")
	var en: String = d.get("reasoning 英文占比", "")
	if not zh.is_empty():
		stats_label.text += "中文占比: %s\n" % zh
	if not en.is_empty():
		stats_label.text += "英文占比: %s" % en

	var hs: String = ""
	var time_keys := ["总用时", "平均每轮", "总 tokens", "平均 token 速度"]
	for k in time_keys:
		var v: String = d.get(k, "")
		if not v.is_empty():
			hs += "%s: %s  " % [k, v]
	if not hs.is_empty():
		stats_label.text += "\n\n耗时速度:\n" + hs
	debug_label.text = "总指标数: %d | 有时间数据: %s" % [_summary_data.size(), "否" if hs.is_empty() else "是"]
	if not hs.is_empty():
		debug_label.text += " | 首: " + hs.left(60)


func _populate_round_list() -> void:
	round_list.clear()
	for i in _summary_rows.size():
		var row := _summary_rows[i]
		var idx_str: String = str(row.get("index", "?"))
		var rt: String = str(row.get("reasoning_tokens", "?"))
		var first: String = str(row.get("first_line", ""))
		var label: String = "#%s  rt:%s  %s" % [idx_str, rt, first.left(30)]
		round_list.add_item(label)

	debug_label.text = " | _summary_rows: %d" % _summary_rows.size()


func _load_round_files() -> void:
	_round_files.clear()
	var dir := DirAccess.open(_batch_dir)
	if dir == null:
		debug_label.text += " | 无法打开批次目录"
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while not fname.is_empty():
		if fname.ends_with(".md") and fname != "_summary.md":
			_round_files.append(_batch_dir.path_join(fname))
		fname = dir.get_next()
	dir.list_dir_end()
	_round_files.sort()

	if not _summary_rows.is_empty():
		round_list.select(0)
		_select_round(0)


func _on_round_list_selected(idx: int) -> void:
	if idx < 0 or idx >= _summary_rows.size():
		return
	_select_round(idx)


func _on_prev() -> void:
	if _selected_idx > 0:
		_select_round(_selected_idx - 1)


func _on_next() -> void:
	if _selected_idx < _summary_rows.size() - 1:
		_select_round(_selected_idx + 1)


func _select_round(idx: int) -> void:
	_selected_idx = idx
	round_list.select(idx)
	_update_nav_buttons()
	var row := _summary_rows[idx]
	var round_idx_str: String = row.get("index", "1")
	var dur: String = str(row.get("duration", ""))
	var tps: String = str(row.get("tokens_per_sec", ""))
	var suffix: String = ""
	if not dur.is_empty():
		suffix += " | %s" % dur
	if not tps.is_empty():
		suffix += " | %s tok/s" % tps
	round_title.text = "第 %s 轮（%d / %d）%s" % [round_idx_str, idx + 1, _summary_rows.size(), suffix]
	_load_round_file(idx)


func _update_nav_buttons() -> void:
	prev_btn.disabled = _selected_idx <= 0
	next_btn.disabled = _selected_idx >= _summary_rows.size() - 1


func _load_round_file(idx: int) -> void:
	if idx >= _round_files.size():
		reasoning_view.text = ""
		content_view.text = ""
		debug_label.text += " | 无文件#%d" % idx
		round_detail_label.text = ""
		return
	var fpath := _round_files[idx]
	var content := FileAccess.get_file_as_string(fpath)
	if content.is_empty():
		debug_label.text = "文件为空: " + fpath.get_file()
		reasoning_view.text = ""
		content_view.text = ""
		round_detail_label.text = ""
		return

	var raw_msgs: Array = _extract_json_section(content, "messages（原始积木，reasoning 与 content 分离）")

	var prompt_text: String = ""
	for m in raw_msgs:
		var role: String = str(m.get("role", ""))
		var msg_content: String = str(m.get("content", ""))
		var msg_reasoning: String = str(m.get("reasoning", ""))
		if role == "system":
			prompt_text += "[system]\n" + msg_content + "\n\n"
		elif role == "user":
			prompt_text += "[user]\n" + msg_content + "\n\n"
		elif role == "assistant" and not msg_content.is_empty():
			prompt_text += "[assistant]\n" + msg_content + "\n\n"
		elif role == "assistant" and not msg_reasoning.is_empty():
			prompt_text += "[assistant reasoning]\n" + msg_reasoning + "\n\n"
		elif role == "tool":
			prompt_text += "[tool]\n" + msg_content + "\n\n"

	prompt_view.text = prompt_text.strip_edges()

	var reasoning_content: String = ""
	var content_text: String = ""

	var resp_json = _extract_json_section(content, "response")
	if resp_json.size() > 0:
		var resp_dict: Dictionary = resp_json[0] if resp_json[0] is Dictionary else {}
		var choices: Array = resp_dict.get("choices", [])
		if not choices.is_empty():
			var msg: Dictionary = choices[0].get("message", {})
			reasoning_content = str(msg.get("reasoning_content", ""))
			content_text = str(msg.get("content", ""))

	var stats_json = _extract_json_section(content, "stats")
	if stats_json.size() > 0:
		var s: Dictionary = stats_json[0] if stats_json[0] is Dictionary else {}
		var rt: int = int(s.get("reasoning_tokens", 0))
		var rc: int = int(s.get("reasoning_chars", 0))
		if rt > 0 or rc > 0:
			reasoning_content += "\n\n--- token: %d | chars: %d ---" % [rt, rc]

	reasoning_view.text = reasoning_content
	content_view.text = content_text

	_update_round_detail(content)


func _update_round_detail(content: String) -> void:
	var detail: String = ""

	var lines := content.split("\n")
	var in_header := false
	var created_at: String = ""
	for line in lines:
		if line.strip_edges() == "---":
			in_header = not in_header
			continue
		if in_header and line.begins_with("created_at:"):
			created_at = line.substr("created_at:".length()).strip_edges().replace("\"", "")
			break
	if not created_at.is_empty():
		detail += "时间: %s" % created_at

	if _selected_idx >= 0 and _selected_idx < _summary_rows.size():
		var row := _summary_rows[_selected_idx]
		debug_label.text = "row键: %s | dur=%s tps=%s" % [str(row.keys()), str(row.get("duration", "?")), str(row.get("tokens_per_sec", "?"))]
		var dur: String = str(row.get("duration", ""))
		if not dur.is_empty():
			if not detail.is_empty():
				detail += "\n"
			detail += "用时: %s" % dur
		var tps: String = row.get("tokens_per_sec", "")
		if not tps.is_empty():
			detail += " | tok/s: %s" % tps

	var stats_json = _extract_json_section(content, "stats")
	if stats_json.size() > 0:
		var s: Dictionary = stats_json[0] if stats_json[0] is Dictionary else {}
		var keys := ["prompt_tokens", "completion_tokens", "total_tokens", "reasoning_tokens", "output_chars", "reasoning_chars"]
		var labels := ["prompt", "completion", "total", "rt", "输出字符", "思考字符"]
		var vals: Array[String] = []
		for i in keys.size():
			if s.has(keys[i]):
				vals.append("%s: %s" % [labels[i], str(s[keys[i]])])
		if not vals.is_empty():
			if not detail.is_empty():
				detail += "\n"
			for v in vals:
				detail += v + "\n"

	round_detail_label.text = detail


func _extract_json_section(content: String, section_name: String) -> Array:
	var marker := "## " + section_name
	var start := content.find(marker)
	if start == -1:
		return []

	# 兼容 Windows \r\n 和 Unix \n 换行
	var json_start := content.find("```json", start)
	if json_start == -1:
		return []
	
	# 跳过 ```json 和后面的换行符（\r\n 或 \n）
	json_start += len("```json")
	while json_start < content.length() and (content[json_start] == '\r' or content[json_start] == '\n' or content[json_start] == ' '):
		json_start += 1

	var json_end := content.find("\n```", json_start)
	if json_end == -1:
		json_end = content.find("\r```", json_start)
		if json_end == -1:
			return []

	var json_str := content.substr(json_start, json_end - json_start)
	var parsed = JSON.parse_string(json_str)
	if parsed is Array:
		return parsed
	if parsed is Dictionary:
		return [parsed]
	return []
