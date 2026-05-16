class_name SummaryGenerator
extends RefCounted

const _APIBuilder = preload("res://scripts/APIBuilder.gd")


static func generate(
	config: Dictionary,
	stats: Array[Dictionary],
	model: String,
	thinking: String,
	effort: String,
	max_tokens: int,
	temperature: float,
	tc_max_rounds: int,
	total: int,
	done: int,
	failed: int,
	prototype_messages: Array,
	batch_dir: String,
	quality_report: String = ""
) -> void:
	var lines: Array[String] = []
	lines.append("# 批量实验汇总\n")
	lines.append("---\n")
	lines.append("\n")
	var now := Time.get_datetime_dict_from_system()
	var created := "%04d-%02d-%02d %02d:%02d:%02d" % [now.year, now.month, now.day, now.hour, now.minute, now.second]
	lines.append("- **生成时间**: %s\n" % created)
	lines.append("- **模型**: %s\n" % model)
	lines.append("- **思考模式**: %s\n" % thinking)
	lines.append("- **推理强度**: %s\n" % effort)
	lines.append("- **max_tokens**: %d\n" % max_tokens)
	lines.append("- **温度**: %.1f\n" % temperature)
	lines.append("- **工具调用上限**: %d\n" % tc_max_rounds)
	lines.append("- **总次数**: %d\n" % total)
	lines.append("- **成功**: %d\n" % done)
	lines.append("- **失败**: %d\n" % failed)
	lines.append("\n")

	lines.append("## 本次使用的 prompt\n\n")
	lines.append("```\n")
	var has_prompt := false
	for m in prototype_messages:
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

	if stats.is_empty():
		lines.append("无成功数据。\n")
	else:
		var reasoning_vals: Array[int] = []
		var prompt_vals: Array[int] = []
		var completion_vals: Array[int] = []
		var total_vals: Array[int] = []
		var tool_rounds_vals: Array[int] = []
		var zh_count: int = 0
		var en_count: int = 0
		for s in stats:
			var rt: int = int(s.get("reasoning_tokens", 0))
			reasoning_vals.append(rt)
			prompt_vals.append(int(s.get("prompt_tokens", 0)))
			completion_vals.append(int(s.get("completion_tokens", 0)))
			total_vals.append(int(s.get("total_tokens", 0)))
			tool_rounds_vals.append(int(s.get("tool_rounds", 0)))
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
		lines.append("| reasoning 中文占比 | %d / %d (%.1f%%) |\n" % [zh_count, stats.size(), float(zh_count) / float(stats.size()) * 100.0])
		lines.append("| reasoning 英文占比 | %d / %d (%.1f%%) |\n" % [en_count, stats.size(), float(en_count) / float(stats.size()) * 100.0])
		lines.append("| 工具调用轮数 平均值 | %.1f |\n" % (_avg(tool_rounds_vals)))
		lines.append("\n")

		var total_duration_ms: int = config.get("total_duration_ms", 0)
		var avg_duration_ms: float = float(total_duration_ms) / float(max(1, stats.size()))
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
		var MAX_ROWS: int = 100
		var total_stats := stats.size()
		var displayed := mini(total_stats, MAX_ROWS)
		var omitted := total_stats - displayed
		lines.append("| # | reasoning_tokens | tool_rounds | duration | tok/s | reasoning_lang | output_lang | reasoning_chars | output_chars | reply 前80字 |\n")
		lines.append("|:-:|:---------------:|:-----------:|:--------:|:-----:|:--------------:|:-----------:|:---------------:|:------------:|:----|\n")
		for i in displayed:
			var s := stats[i]
			var idx: int = int(s.get("index", 0))
			var rt: int = int(s.get("reasoning_tokens", 0))
			var tool_rounds_val: int = int(s.get("tool_rounds", 0))
			var dm: int = int(s.get("duration_ms", 0))
			var tps: float = float(s.get("tokens_per_sec", 0.0))
			var rl: String = str(s.get("reasoning_language", "?"))
			var ol: String = str(s.get("output_language", "?"))
			var rc: int = int(s.get("reasoning_chars", 0))
			var oc: int = int(s.get("output_chars", 0))
			var reply: String = str(s.get("output_first_line", ""))
			lines.append("| %d | %d | %d | %.1fs | %.1f | %s | %s | %d | %d | %s |\n" % [idx, rt, tool_rounds_val, float(dm) / 1000.0, tps, rl, ol, rc, oc, reply])

		if omitted > 0:
			lines.append("| ... | ... | ... | ... | ... | ... | ... | ... | ... | （省略 %d 行） |\n" % omitted)

	lines.append("\n")

	if not quality_report.is_empty():
		lines.append(quality_report)
		lines.append("\n")

	lines.append("---\n")

	var summary_path := batch_dir.path_join("_summary.md")
	var file := FileAccess.open(summary_path, FileAccess.WRITE)
	if file:
		for line in lines:
			file.store_string(line)
		file.close()


static func _sum(arr: Array[int]) -> int:
	var total := 0
	for v in arr:
		total += v
	return total


static func _avg(arr: Array[int]) -> float:
	if arr.is_empty():
		return 0.0
	return float(_sum(arr)) / float(arr.size())


static func _median(arr: Array[int]) -> float:
	if arr.is_empty():
		return 0.0
	var sorted := arr.duplicate()
	sorted.sort()
	var mid := int(sorted.size() * 0.5)
	if sorted.size() % 2 == 0:
		return (sorted[mid - 1] + sorted[mid]) / 2.0
	return float(sorted[mid])
