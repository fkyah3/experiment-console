class_name BatchRunner
extends RefCounted

const _APIBuilder = preload("res://scripts/APIBuilder.gd")
const _ResultRuleEngine = preload("res://scripts/Core/ResultRuleEngine.gd")
const _QualityAssessor = preload("res://scripts/Core/QualityAssessor.gd")
const _SummaryGenerator = preload("res://scripts/Core/SummaryGenerator.gd")
const _FingerprintRecorder = preload("res://scripts/Core/FingerprintRecorder.gd")

signal progress_updated(done: int, failed: int, total: int, running: int)
signal all_done(success: int, failed: int)

var _queue: Array = []
var _running: int = 0
var _done: int = 0
var _failed: int = 0
var _total: int = 0
var _stats: Array[Dictionary] = []
var _prototype_messages: Array = []
var _start_ms: int = 0
var _batch_dir: String = ""
var _save_store: ExperimentStore
var _api_key: String = ""

var _model: String = ""
var _effort: String = ""
var _thinking: String = ""
var _max_tokens: int = 4096
var _temperature: float = 0.0
var _top_p: float = 1.0
var _frequency_penalty: float = 0.0
var _workspace_path: String = ""
var _tc_max_rounds: int = 50
var _explore_separate: bool = false
var _bare_mode: bool = false
var _batch_host: String = "api.deepseek.com"
var _batch_path: String = "/chat/completions"
var _use_rule_engine: bool = true
var _use_quality_assess: bool = false
var _assess_samples: int = 5
var _provider: String = "deepseek"

var _max_concurrency: int = 5
var _parent_node: Node


func setup(parent: Node, api_key: String) -> void:
	_parent_node = parent
	_api_key = api_key


func start(
	count: int,
	batch_name: String,
	prototype_messages: Array,
	experiments_path: String,
	templates_path: String,
	model: String,
	thinking: String,
	effort: String,
	max_tokens: int,
	temperature: float,
	top_p: float = 1.0,
	frequency_penalty: float = 0.0,
	workspace_path: String = "",
	tc_max_rounds: int = 50,
	concurrency: int = 5,
	explore_separate: bool = false,
	bare_mode: bool = false,
	host: String = "",
	path: String = "",
	rule_engine: bool = true,
	quality_assess: bool = false,
	assess_samples: int = 5,
	provider: String = "deepseek"
) -> void:
	_model = model
	_thinking = thinking
	_effort = effort
	_max_tokens = max_tokens
	_temperature = temperature
	_top_p = top_p
	_frequency_penalty = frequency_penalty
	_workspace_path = workspace_path
	_tc_max_rounds = tc_max_rounds
	_explore_separate = explore_separate
	_bare_mode = bare_mode
	_batch_host = host if host != "" else _batch_host
	_batch_path = path if path != "" else _batch_path
	_use_rule_engine = rule_engine
	_use_quality_assess = quality_assess
	_assess_samples = assess_samples
	_provider = provider
	_total = count
	_done = 0
	_failed = 0
	_running = 0
	_stats.clear()
	_prototype_messages = prototype_messages.duplicate(true)
	_start_ms = Time.get_ticks_msec()

	var now := Time.get_datetime_dict_from_system()
	var dir_name := "batch_%04d%02d%02d_%02d%02d" % [now.year, now.month, now.day, now.hour, now.minute]
	if not batch_name.is_empty():
		dir_name += "_" + batch_name.left(60)
	_batch_dir = experiments_path.path_join(dir_name)
	_save_store = ExperimentStore.new(_batch_dir, templates_path)

	_queue.clear()
	for i in count:
		_queue.append(prototype_messages.duplicate(true))

	_max_concurrency = concurrency
	_start_workers()


func _start_workers() -> void:
	var n := mini(_max_concurrency, _total)
	for i in n:
		_launch_worker()


func _launch_worker() -> void:
	if _queue.is_empty():
		return
	var raw_messages: Array = _queue.pop_front()
	var idx := _total - _queue.size() - _running

	var worker_msgs: Array
	if _explore_separate and not _workspace_path.is_empty():
		# 探索分离模式：本地扫描→读文件→组装假 user 消息→单轮 API
		var file_paths := _scan_key_files(_workspace_path, 20)
		var file_contents := ""
		var count := 0
		for fpath in file_paths:
			if count >= 5:
				break
			var raw := _read_tool_file(fpath)
			var truncated := raw
			if raw.length() > 10000:
				truncated = raw.left(10000) + "\n...（共 %d 字，已截断）" % raw.length()
			file_contents += "\n--- 文件: %s ---\n%s" % [fpath, truncated]
			count += 1

		var original: String = ""
		if raw_messages.size() >= 2:
			original = str(raw_messages[1].get("content", ""))
		var combined := "以下是工程层根据目录结构读取的关键文件内容：\n%s\n\n请基于以上文件内容，%s" % [file_contents, original]
		worker_msgs = [raw_messages[0].duplicate(true), {"role": "user", "content": combined}]
	else:
		worker_msgs = raw_messages.duplicate(true)

	var wd := {
		"client": null,
		"messages": worker_msgs,
		"raw_messages": raw_messages,
		"content": "",
		"reasoning": "",
		"usage": {},
		"response_body": "",
		"ok": false,
		"index": idx,
		"round": _tc_max_rounds if _explore_separate else 0,
	}

	_running += 1
	_send_worker(wd)
	_dispatch_progress()


func _send_worker(wd: Dictionary) -> void:
	var tools: Array = []
	if not _bare_mode and wd.round < _tc_max_rounds:
		tools = APIBuilder.build_tools()

	var api_messages := APIBuilder.build_api_messages(wd.messages)

	if _thinking == "思考模式":
		for msg in api_messages:
			if msg.get("role") == "assistant" and not msg.has("reasoning_content"):
				msg["reasoning_content"] = "(reasoning omitted)"

	wd.api_messages = api_messages
	var body_dict := APIBuilder.build_body_dict(_model, _thinking, _effort, _max_tokens, _temperature, api_messages, _top_p, _frequency_penalty, true, tools, _provider)
	wd.body_str = JSON.stringify(body_dict, "\t")

	wd.content = ""
	wd.reasoning = ""
	wd.usage = {}

	if wd.client:
		wd.client.queue_free()

	var client := DeepSeekStreamClient.new()
	_parent_node.add_child(client)
	client.api_key = _api_key
	client.api_host = _batch_host
	client.api_path = _batch_path
	wd.client = client

	client.content_chunk.connect(_on_content_chunk.bind(wd))
	client.reasoning_chunk.connect(_on_reasoning_chunk.bind(wd))
	client.stream_finished.connect(_on_done.bind(wd))
	client.tool_calls_done.connect(_on_tool_calls_done.bind(wd))
	client.usage_received.connect(_on_usage.bind(wd))
	client.connection_error.connect(_on_error.bind(wd))
	client.start_streaming(wd.body_str)


func _on_content_chunk(text: String, wd: Dictionary) -> void:
	wd.content += text


func _on_reasoning_chunk(text: String, wd: Dictionary) -> void:
	wd.reasoning += text


func _on_usage(usage: Dictionary, wd: Dictionary) -> void:
	wd.usage = usage


func _on_done(wd: Dictionary) -> void:
	wd.response_body = APIBuilder.build_response_body(wd.content, wd.reasoning)
	wd.ok = true
	_finish(wd)


func _on_tool_calls_done(tool_calls: Array, wd: Dictionary) -> void:
	if wd.client:
		wd.client.queue_free()
		wd.client = null

	wd.round += 1
	if wd.round >= _tc_max_rounds:
		_on_error("工具调用已达上限", wd)
		return

	# ① 先把 AI 的回复作为 assistant 消息写入 wd.messages
	var tc_for_api: Array = []
	for tc in tool_calls:
		tc_for_api.append({
			"id": tc.get("id", ""),
			"type": "function",
			"function": {
				"name": tc.get("name", ""),
				"arguments": tc.get("arguments", "")
			}
		})

	wd.messages.append({
		"role": "assistant",
		"content": wd.content,
		"reasoning": wd.reasoning,
		"tool_calls": tc_for_api
	})

	# ② 再追加 tool 执行结果
	for tc in tool_calls:
		var content := _execute_tool(tc.get("name", ""), tc.get("arguments", "{}"))
		wd.messages.append({
			"role": "tool",
			"tool_call_id": tc.get("id", ""),
			"name": tc.get("name", ""),
			"content": content
		})

	_send_worker(wd)


func _execute_tool(name: String, args_str: String) -> String:
	var args := JSON.parse_string(args_str) as Dictionary
	match name:
		"list_dir":
			var dir_path: String = "."
			if args != null:
				dir_path = args.get("dirPath", ".")
			return _list_dir(dir_path)
		"read":
			var file_path: String = ""
			if args != null:
				file_path = args.get("filePath", "")
			return _read_tool_file(file_path)
		_:
			return "[未知工具: %s]" % name


func _read_tool_file(filePath: String) -> String:
	var shadow := _shadow_path(filePath)
	if FileAccess.file_exists(shadow):
		return FileAccess.get_file_as_string(shadow)
	var base := _workspace_path
	if not base.ends_with("/"):
		base += "/"
	var fpath := filePath
	if not fpath.begins_with("E:/") and not fpath.begins_with("e:/") and not fpath.begins_with("C:/") and not fpath.begins_with("c:/"):
		fpath = base.path_join(filePath)
	if FileAccess.file_exists(fpath):
		return FileAccess.get_file_as_string(fpath)
	return "[文件不存在: %s]" % filePath


func _list_dir(dirPath: String) -> String:
	var base := _workspace_path
	if not base.ends_with("/"):
		base += "/"
	var dpath := dirPath
	if not dpath.begins_with("E:/") and not dpath.begins_with("e:/") and not dpath.begins_with("C:/") and not dpath.begins_with("c:/"):
		dpath = base.path_join(dirPath)
	var dir := DirAccess.open(dpath)
	if dir == null:
		return "[目录不存在: %s]" % dirPath
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


func _on_error(msg: String, wd: Dictionary) -> void:
	if wd.client:
		wd.client.queue_free()
		wd.client = null
	push_error("Batch worker #%d error: %s" % [wd.index, msg])
	wd.ok = false
	wd.response_body = msg
	_finish(wd)


func _scan_key_files(base_dir: String, max_return: int) -> Array[String]:
	var result: Array[String] = []
	var priority: Array[String] = []
	var rest: Array[String] = []
	_scan_dir(base_dir, "", priority, rest)
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


func _scan_dir(base: String, rel: String, priority: Array[String], rest: Array[String]) -> void:
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
			_scan_dir(base, full_rel, priority, rest)
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


func _shadow_path(filePath: String) -> String:
	return ProjectSettings.globalize_path("user://opencode-shadow/").path_join(filePath)


func _finish(wd: Dictionary) -> void:
	_running -= 1

	if wd.client:
		wd.client.queue_free()
		wd.client = null

	if wd.ok:
		var title := "batch_%03d" % wd.index
		_save_store.save_experiment(
			title, _model, _thinking, _effort, _max_tokens, _temperature,
			wd.api_messages, wd.messages,
			wd.body_str, wd.response_body, wd.usage, ""
		)
		_FingerprintRecorder.save_meta(_batch_dir, wd.index, wd.usage)
		_stats.append(_calc_stats(wd))
		_done += 1
	else:
		_failed += 1

	_dispatch_progress()

	if _done + _failed >= _total:
		_generate_and_save_summary()
		return

	if not _queue.is_empty():
		_launch_worker()


func _generate_and_save_summary() -> void:
	var config := {
		"total_duration_ms": Time.get_ticks_msec() - _start_ms
	}

	# 规则引擎
	var quality_report: String = ""
	if _use_rule_engine:
		var engine := _ResultRuleEngine.new()
		var marks := engine.evaluate(_stats)
		var suspect_count := 0
		for m in marks:
			if m["level"] != "normal":
				suspect_count += 1
		# 规则结果内联到报告
		if suspect_count > 0:
			quality_report += "## 规则引擎结果\n\n"
			quality_report += "可疑样本：%d / %d\n\n" % [suspect_count, _stats.size()]

	# 质量评估（可选）
	if _use_quality_assess and not _stats.is_empty():
		var assessor := _QualityAssessor.new()
		assessor.enabled = true
		assessor.sample_count = _assess_samples
		assessor.api_key = _api_key
		assessor.api_host = _batch_host
		assessor.api_path = _batch_path
		assessor.parent_node = _parent_node
		# 因为 assess 是异步的，我们在 _generate_summary 外部处理
		# 简化：同步调用每个样本
		var report := await _run_quality_assessment_sync(assessor)
		if not report.is_empty():
			quality_report += report

	_SummaryGenerator.generate(
		config, _stats,
		_model, _thinking, _effort, _max_tokens, _temperature,
		_tc_max_rounds, _total, _done, _failed,
		_prototype_messages, _batch_dir,
		quality_report
	)
	all_done.emit(_done, _failed)


func _run_quality_assessment_sync(assessor) -> String:
	# 给每个样本补充 user_msg 字段
	var enhanced: Array[Dictionary] = []
	for i in _stats.size():
		var s := _stats[i].duplicate()
		if i < _prototype_messages.size():
			for m in _prototype_messages:
				if m.get("role", "") == "user":
					s["user_msg"] = str(m.get("content", ""))
					break
			if not s.has("user_msg"):
				s["user_msg"] = ""
		else:
			s["user_msg"] = ""
		enhanced.append(s)

	_stats = enhanced

	var indices: Array[int] = assessor.sample_from_stats(_stats)
	var evaluations: Array[Dictionary] = []

	for idx in indices:
		var sample := _stats[idx]
		var user_msg: String = str(sample.get("user_msg", ""))
		var content: String = str(sample.get("output_first_line", ""))
		var reasoning: String = str(sample.get("reasoning_first_line", ""))

		var prompt_text := "用户消息：" + user_msg.left(2000) + "\n\n"
		prompt_text += "AI 回复（content）：" + content.left(2000) + "\n\n"
		prompt_text += "AI 推理（reasoning）：" + reasoning.left(500) + "\n\n"
		prompt_text += """请评估以上 AI 回复的质量。只输出 JSON，格式：
{
  "score": 0-10,
  "issues": ["问题描述"],
  "language": "zh|en|mixed",
  "suggestion": "改进建议"
}"""

		var body := {
			"model": "deepseek-v4-flash",
			"messages": [{"role": "user", "content": prompt_text}],
			"stream": false,
			"max_tokens": 200,
			"temperature": 0.0,
			"thinking": {"type": "disabled"},
		}

		var http := HTTPRequest.new()
		_parent_node.add_child(http)

		var headers := PackedStringArray([
			"Content-Type: application/json",
			"Authorization: Bearer " + _api_key,
		])
		var url := "https://" + _batch_host + _batch_path
		var err := http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
		if err != OK:
			http.queue_free()
			evaluations.append({"index": idx, "score": 0, "issues": ["请求失败"], "language": "unknown", "suggestion": ""})
			continue

		var response: Array = await http.request_completed
		http.queue_free()

		var result: Dictionary = {"score": 0, "issues": ["评估失败"], "language": "unknown", "suggestion": ""}
		if response[0] == HTTPRequest.RESULT_SUCCESS:
			var raw: String = response[3].get_string_from_utf8().strip_edges()
			var parsed = JSON.parse_string(raw)
			if parsed != null and typeof(parsed) == TYPE_DICTIONARY:
				var choices = parsed.get("choices")
				if choices != null and typeof(choices) == TYPE_ARRAY and not choices.is_empty():
					var msg: Dictionary = choices[0].get("message", {})
					var text: String = msg.get("content", "").strip_edges()
					if not text.is_empty():
						var parsed_result = JSON.parse_string(text)
						if parsed_result != null and typeof(parsed_result) == TYPE_DICTIONARY:
							result = parsed_result

		result["index"] = idx
		evaluations.append(result)

	# 构建报告
	if evaluations.is_empty():
		return ""

	var lines: Array[String] = []
	lines.append("## 质量评估（采样 %d/%d）\n\n" % [indices.size(), _stats.size()])
	lines.append("| # | 评分 | 语言 | 问题 |\n")
	lines.append("|:-:|:----:|:-----|:-----|\n")

	var sum_score: float = 0.0
	var lang_counts: Dictionary = {"zh": 0, "en": 0, "mixed": 0, "unknown": 0}

	for ev in evaluations:
		var e_idx: int = int(ev.get("index", 0))
		var score: int = int(ev.get("score", 0))
		var lang: String = str(ev.get("language", "unknown"))
		var issues: Array = ev.get("issues", [])
		var issues_str: String = "无异常" if issues.is_empty() else "；".join(issues)

		sum_score += score
		if lang_counts.has(lang):
			lang_counts[lang] += 1

		lines.append("| %d | %d/10 | %s | %s |\n" % [e_idx, score, lang, issues_str])

	lines.append("\n")
	var avg_score: float = sum_score / float(max(1, evaluations.size()))
	lines.append("**平均评分：** %.1f/10\n" % avg_score)
	lines.append("\n")

	return "".join(lines)


func _calc_stats(wd: Dictionary) -> Dictionary:
	var s: Dictionary = {}
	s["index"] = wd.index
	s["ok"] = true
	var duration_ms: int = Time.get_ticks_msec() - int(wd.get("start_ms", 0))
	s["duration_ms"] = duration_ms
	s["duration_s"] = float(duration_ms) / 1000.0
	if not wd.usage.is_empty():
		s["reasoning_tokens"] = wd.usage.get("completion_tokens_details", {}).get("reasoning_tokens", 0)
		s["prompt_tokens"] = wd.usage.get("prompt_tokens", 0)
		s["completion_tokens"] = wd.usage.get("completion_tokens", 0)
		s["total_tokens"] = wd.usage.get("total_tokens", 0)
		var total_tok: int = int(s["total_tokens"])
		if duration_ms > 0:
			s["tokens_per_sec"] = float(total_tok) / (float(duration_ms) / 1000.0)
	s["reasoning_chars"] = wd.reasoning.length()
	s["output_chars"] = wd.content.length()
	s["tool_rounds"] = wd.round
	if _explore_separate and wd.round >= _tc_max_rounds:
		s["tool_rounds"] = 0
	s["reasoning_language"] = APIBuilder.detect_language(wd.reasoning)
	s["output_language"] = APIBuilder.detect_language(wd.content)
	s["reasoning_first_line"] = wd.reasoning.left(80).replace("\n", " ")
	s["output_first_line"] = wd.content.left(80).replace("\n", " ")
	return s


func _dispatch_progress() -> void:
	progress_updated.emit(_done, _failed, _total, _running)
