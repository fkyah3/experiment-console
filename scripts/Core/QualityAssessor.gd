class_name QualityAssessor
extends RefCounted

signal sample_evaluated(idx: int, result: Dictionary)
signal finished(report_md: String)

enum SampleStrategy { TOP, RANDOM, ALL }

var enabled: bool = false
var strategy: int = SampleStrategy.RANDOM
var sample_count: int = 5

var api_key: String = ""
var api_host: String = "api.deepseek.com"
var api_path: String = "/chat/completions"
var model: String = "deepseek-v4-flash"
var parent_node: Node


func sample_from_stats(stats: Array[Dictionary]) -> Array[int]:
	var indices: Array[int] = []
	if strategy == SampleStrategy.ALL:
		for i in stats.size():
			indices.append(i)
	elif strategy == SampleStrategy.TOP:
		for i in mini(sample_count, stats.size()):
			indices.append(i)
	elif strategy == SampleStrategy.RANDOM:
		var pool: Array[int] = []
		for i in stats.size():
			pool.append(i)
		pool.shuffle()
		for i in mini(sample_count, pool.size()):
			indices.append(pool[i])
	return indices


func assess_batch(stats: Array[Dictionary], _results_dir: String) -> void:
	if not enabled or stats.is_empty():
		var empty := ""
		finished.emit(empty)
		return

	var sample_indices := sample_from_stats(stats)
	var evaluations: Array[Dictionary] = []
	var done_count := 0

	for idx in sample_indices:
		_evaluate_one(idx, stats, func(result: Dictionary):
			result["index"] = idx
			evaluations.append(result)
			if evaluations.size() >= sample_indices.size():
				var report := _build_report(evaluations, sample_indices.size(), stats.size())
				finished.emit(report)
		)


func _evaluate_one(idx: int, stats: Array, callback: Callable) -> void:
	if parent_node == null:
		callback.call({"score": 0, "issues": ["评估器未连接"], "language": "unknown", "suggestion": ""})
		return

	var sample: Dictionary = stats[idx] if idx < stats.size() else {}
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
		"model": model,
		"messages": [{"role": "user", "content": prompt_text}],
		"stream": false,
		"max_tokens": 200,
		"temperature": 0.0,
		"thinking": {"type": "disabled"},
	}

	var http := HTTPRequest.new()
	parent_node.add_child(http)

	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key,
	])

	var url := "https://" + api_host + api_path

	var err := http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		http.queue_free()
		callback.call({"score": 0, "issues": ["HTTP 请求失败: " + str(err)], "language": "unknown", "suggestion": ""})
		return

	var response: Array = await http.request_completed
	http.queue_free()

	if response[0] != HTTPRequest.RESULT_SUCCESS:
		callback.call({"score": 0, "issues": ["HTTP 失败"], "language": "unknown", "suggestion": ""})
		return

	var raw: String = response[3].get_string_from_utf8().strip_edges()
	var parsed = JSON.parse_string(raw)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		callback.call({"score": 0, "issues": ["JSON 解析失败"], "language": "unknown", "suggestion": ""})
		return

	var choices = parsed.get("choices")
	if choices == null or typeof(choices) != TYPE_ARRAY or choices.is_empty():
		callback.call({"score": 0, "issues": ["无 choices"], "language": "unknown", "suggestion": ""})
		return

	var msg: Dictionary = choices[0].get("message", {})
	var text: String = msg.get("content", "").strip_edges()
	if text.is_empty():
		callback.call({"score": 0, "issues": ["评估响应为空"], "language": "unknown", "suggestion": ""})
		return

	var result = JSON.parse_string(text)
	if result == null or typeof(result) != TYPE_DICTIONARY:
		callback.call({"score": 0, "issues": ["评估 JSON 解析失败"], "language": "unknown", "suggestion": ""})
		return

	callback.call(result)


func _build_report(evaluations: Array[Dictionary], sampled: int, total: int) -> String:
	var lines: Array[String] = []
	lines.append("## 质量评估（采样 %d/%d）\n\n" % [sampled, total])
	lines.append("| # | 评分 | 语言 | 问题 |\n")
	lines.append("|:-:|:----:|:-----|:-----|\n")

	var sum_score: float = 0.0
	var lang_counts: Dictionary = {}
	lang_counts["zh"] = 0
	lang_counts["en"] = 0
	lang_counts["mixed"] = 0
	lang_counts["unknown"] = 0

	for ev in evaluations:
		var idx: int = int(ev.get("index", 0))
		var score: int = int(ev.get("score", 0))
		var lang: String = str(ev.get("language", "unknown"))
		var issues: Array = ev.get("issues", [])
		var issues_str: String = ""
		if issues.is_empty():
			issues_str = "无异常"
		else:
			var parts: Array[String] = []
			for iss in issues:
				parts.append(str(iss))
			issues_str = "；".join(parts)

		sum_score += score
		if lang_counts.has(lang):
			lang_counts[lang] += 1
		else:
			lang_counts[lang] = 1

		lines.append("| %d | %d/10 | %s | %s |\n" % [idx, score, lang, issues_str])

	lines.append("\n")
	var avg_score: float = sum_score / float(max(1, evaluations.size()))
	lines.append("**平均评分：** %.1f/10\n" % avg_score)
	lines.append("\n")
	lines.append("**语言分布：**")
	var lang_parts: Array[String] = []
	for k in ["zh", "en", "mixed", "unknown"]:
		if lang_counts.has(k) and lang_counts[k] > 0:
			lang_parts.append("%s %d" % [k, lang_counts[k]])
	lines.append("  ".join(lang_parts))
	lines.append("\n\n")

	lines.append("评估模型：%s\n" % model)
	lines.append("\n")

	return "".join(lines)
