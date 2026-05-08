class_name BatchRunner
extends RefCounted

const APIBuilder = preload("res://scripts/APIBuilder.gd")

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

var _max_concurrency: int = 5
var _parent_node: Node
var _templates_path: String = ""


func setup(parent: Node, api_key: String, templates_path: String, max_concurrency: int = 5) -> void:
	_max_concurrency = max_concurrency
	_parent_node = parent
	_api_key = api_key
	_templates_path = templates_path


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
	frequency_penalty: float = 0.0
) -> void:
	_model = model
	_thinking = thinking
	_effort = effort
	_max_tokens = max_tokens
	_temperature = temperature
	_top_p = top_p
	_frequency_penalty = frequency_penalty
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

	_start_workers()


func _start_workers() -> void:
	var n := mini(_max_concurrency, _total)
	for i in n:
		_start_worker()


func _start_worker() -> void:
	if _queue.is_empty():
		return
	var raw_messages: Array = _queue.pop_front()
	var api_messages := APIBuilder.build_api_messages(raw_messages)
	var body_dict := APIBuilder.build_body_dict(_model, _thinking, _effort, _max_tokens, _temperature, api_messages, _top_p, _frequency_penalty)
	var body_str := JSON.stringify(body_dict, "\t")

	var client := DeepSeekStreamClient.new()
	_parent_node.add_child(client)
	client.api_key = _api_key

	var idx := _total - _queue.size() - _running
	var wd: Dictionary = {
		"client": client,
		"raw_messages": raw_messages,
		"api_messages": api_messages,
		"body_str": body_str,
		"content": "",
		"reasoning": "",
		"response_body": "",
		"usage": {},
		"ok": false,
		"index": idx,
		"start_ms": Time.get_ticks_msec(),
	}

	_running += 1
	client.content_chunk.connect(_on_content_chunk.bind(wd))
	client.reasoning_chunk.connect(_on_reasoning_chunk.bind(wd))
	client.stream_finished.connect(_on_done.bind(wd))
	client.usage_received.connect(_on_usage.bind(wd))
	client.connection_error.connect(_on_error.bind(wd))
	client.start_streaming(body_str)
	_dispatch_progress()


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


func _on_error(msg: String, wd: Dictionary) -> void:
	push_error("Batch worker #%d error: %s" % [wd.index, msg])
	wd.ok = false
	wd.response_body = msg
	_finish(wd)


func _finish(wd: Dictionary) -> void:
	if wd.client:
		wd.client.queue_free()

	_running -= 1

	if wd.ok:
		var title := "batch_%03d" % wd.index
		_save_store.save_experiment(
			title, _model, _thinking, _effort, _max_tokens, _temperature,
			wd.api_messages, wd.raw_messages,
			wd.body_str, wd.response_body, wd.usage, ""
		)
		_stats.append(_calc_stats(wd))
		_done += 1
	else:
		_failed += 1

	_dispatch_progress()

	if _done + _failed >= _total:
		_generate_summary()
		all_done.emit(_done, _failed)
		return

	if not _queue.is_empty():
		_start_worker()


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
	s["reasoning_language"] = APIBuilder.detect_language(wd.reasoning)
	s["output_language"] = APIBuilder.detect_language(wd.content)
	s["reasoning_first_line"] = wd.reasoning.left(80).replace("\n", " ")
	s["output_first_line"] = wd.content.left(80).replace("\n", " ")
	return s


func _generate_summary() -> void:
	var lines: Array[String] = []
	lines.append("# 批量实验汇总\n")
	lines.append("---\n")
	lines.append("\n")
	var now := Time.get_datetime_dict_from_system()
	var created := "%04d-%02d-%02d %02d:%02d:%02d" % [now.year, now.month, now.day, now.hour, now.minute, now.second]
	lines.append("- **生成时间**: %s\n" % created)
	lines.append("- **模型**: %s\n" % _model)
	lines.append("- **思考模式**: %s\n" % _thinking)
	lines.append("- **推理强度**: %s\n" % _effort)
	lines.append("- **max_tokens**: %d\n" % _max_tokens)
	lines.append("- **温度**: %.1f\n" % _temperature)
	lines.append("- **总次数**: %d\n" % _total)
	lines.append("- **成功**: %d\n" % _done)
	lines.append("- **失败**: %d\n" % _failed)
	lines.append("\n")

	lines.append("## 本次使用的 prompt\n\n")
	lines.append("```\n")
	var has_prompt := false
	for m in _prototype_messages:
		var role: String = str(m.get("role", ""))
		var content: String = str(m.get("content", ""))
		var reasoning: String = str(m.get("reasoning", ""))
		if role == "system":
			lines.append("[system]\n%s\n\n" % content)
			has_prompt = true
		elif role == "user":
			lines.append("[user]\n%s\n\n" % content)
			has_prompt = true
		elif role == "assistant" and not content.is_empty():
			lines.append("[assistant]\n%s\n\n" % content)
		elif role == "assistant" and not reasoning.is_empty():
			lines.append("[assistant reasoning]\n%s\n\n" % reasoning)
		elif role == "tool":
			lines.append("[tool]\n%s\n\n" % content)
	if not has_prompt:
		lines.append("（空）\n")
	lines.append("```\n")
	lines.append("\n")

	if _stats.is_empty():
		lines.append("无成功数据。\n")
	else:
		var reasoning_vals: Array[int] = []
		var prompt_vals: Array[int] = []
		var completion_vals: Array[int] = []
		var total_vals: Array[int] = []
		var zh_count: int = 0
		var en_count: int = 0
		for s in _stats:
			var rt: int = int(s.get("reasoning_tokens", 0))
			reasoning_vals.append(rt)
			prompt_vals.append(int(s.get("prompt_tokens", 0)))
			completion_vals.append(int(s.get("completion_tokens", 0)))
			total_vals.append(int(s.get("total_tokens", 0)))
			match s.get("reasoning_language", ""):
				"zh": zh_count += 1
				"en": en_count += 1

		var r_min: int = reasoning_vals.min()
		var r_max: int = reasoning_vals.max()
		var r_sum: int = 0
		for v in reasoning_vals: r_sum += v
		var r_avg: float = float(r_sum) / float(reasoning_vals.size())
		var r_median: float = _median(reasoning_vals)

		lines.append("## 汇总统计\n\n")
		lines.append("| 指标 | 值 |\n")
		lines.append("|:-----|:----|\n")
		lines.append("| reasoning_tokens 最小值 | %d |\n" % r_min)
		lines.append("| reasoning_tokens 最大值 | %d |\n" % r_max)
		lines.append("| reasoning_tokens 平均值 | %.1f |\n" % r_avg)
		lines.append("| reasoning_tokens 中位数 | %.1f |\n" % r_median)
		lines.append("| 波动倍数（max/min） | %.1f |\n" % (float(r_max) / float(max(1, r_min))))
		lines.append("| prompt_tokens 平均值 | %.1f |\n" % (_avg(prompt_vals)))
		lines.append("| completion_tokens 平均值 | %.1f |\n" % (_avg(completion_vals)))
		lines.append("| total_tokens 平均值 | %.1f |\n" % (_avg(total_vals)))
		lines.append("| reasoning 中文占比 | %d / %d (%.1f%%) |\n" % [zh_count, _stats.size(), float(zh_count) / float(_stats.size()) * 100.0])
		lines.append("| reasoning 英文占比 | %d / %d (%.1f%%) |\n" % [en_count, _stats.size(), float(en_count) / float(_stats.size()) * 100.0])
		lines.append("\n")

		var total_duration_ms: int = Time.get_ticks_msec() - _start_ms
		var avg_duration_ms: float = float(total_duration_ms) / float(max(1, _stats.size()))
		var total_tok_sum: int = _sum(total_vals)

		lines.append("## 耗时与速度\n\n")
		lines.append("| 指标 | 值 |\n")
		lines.append("|:-----|:----|\n")
		lines.append("| 总用时 | %.1f 秒 |\n" % (float(total_duration_ms) / 1000.0))
		lines.append("| 平均每轮 | %.1f 秒 |\n" % (avg_duration_ms / 1000.0))
		lines.append("| 总 tokens | %d |\n" % total_tok_sum)
		lines.append("| 平均 token 速度 | %.1f tok/s |\n" % (float(total_tok_sum) / (float(total_duration_ms) / 1000.0) if total_duration_ms > 0 else 0.0))
		lines.append("\n")

		lines.append("## 每轮明细\n\n")
		lines.append("| # | reasoning_tokens | duration | tok/s | reasoning_lang | output_lang | reasoning_chars | output_chars | reply 前80字 |\n")
		lines.append("|:-:|:---------------:|:--------:|:-----:|:--------------:|:-----------:|:---------------:|:------------:|:----|\n")
		for s in _stats:
			var idx: int = int(s.get("index", 0))
			var rt: int = int(s.get("reasoning_tokens", 0))
			var dm: int = int(s.get("duration_ms", 0))
			var tps: float = float(s.get("tokens_per_sec", 0.0))
			var rl: String = str(s.get("reasoning_language", "?"))
			var ol: String = str(s.get("output_language", "?"))
			var rc: int = int(s.get("reasoning_chars", 0))
			var oc: int = int(s.get("output_chars", 0))
			var reply: String = str(s.get("output_first_line", ""))
			lines.append("| %d | %d | %.1fs | %.1f | %s | %s | %d | %d | %s |\n" % [idx, rt, float(dm) / 1000.0, tps, rl, ol, rc, oc, reply])

	lines.append("\n")
	lines.append("---\n")

	var summary_path := _batch_dir.path_join("_summary.md")
	var file := FileAccess.open(summary_path, FileAccess.WRITE)
	if file:
		for line in lines:
			file.store_string(line)
		file.close()

	_dispatch_progress()


func _dispatch_progress() -> void:
	progress_updated.emit(_done, _failed, _total, _running)


func _sum(arr: Array[int]) -> int:
	var total := 0
	for v in arr:
		total += v
	return total


func _avg(arr: Array[int]) -> float:
	if arr.is_empty():
		return 0.0
	return float(_sum(arr)) / float(arr.size())


func _median(arr: Array[int]) -> float:
	if arr.is_empty():
		return 0.0
	var sorted := arr.duplicate()
	sorted.sort()
	var mid := int(sorted.size() * 0.5)
	if sorted.size() % 2 == 0:
		return (sorted[mid - 1] + sorted[mid]) / 2.0
	return float(sorted[mid])
