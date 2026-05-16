class_name ResultRuleEngine
extends RefCounted

signal sample_marked(idx: int, level: String, reason: String)

var enabled: bool = true
var rules: Array[Dictionary] = []


func _init() -> void:
	_register_default_rules()


func _register_default_rules() -> void:
	add_rule("空内容", func(s: Dictionary) -> String:
		var content: String = str(s.get("output_first_line", ""))
		if content.strip_edges().is_empty():
			return "content 为空"
		return ""
	)

	add_rule("回复太短", func(s: Dictionary) -> String:
		var chars: int = int(s.get("output_chars", 0))
		if chars > 0 and chars < 10:
			return "回复不足 10 字（%d 字）" % chars
		return ""
	)

	add_rule("语言不一致", func(s: Dictionary) -> String:
		var rl: String = str(s.get("reasoning_language", ""))
		var ol: String = str(s.get("output_language", ""))
		if not rl.is_empty() and not ol.is_empty() and rl != ol:
			return "推理语言（%s）≠ 回复语言（%s）" % [rl, ol]
		return ""
	)

	add_rule("无推理", func(s: Dictionary) -> String:
		var tokens: int = int(s.get("reasoning_tokens", -1))
		if tokens == 0:
			return "reasoning_tokens = 0（无推理过程）"
		return ""
	)


func add_rule(name: String, check: Callable) -> void:
	rules.append({"name": name, "check": check})


func evaluate(stats: Array[Dictionary]) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for i in stats.size():
		var s := stats[i]
		var issues: Array[String] = []
		for rule in rules:
			var reason: String = rule["check"].call(s)
			if not reason.is_empty():
				issues.append(reason)
		var level: String = "normal"
		if not issues.is_empty():
			level = "suspect"
			sample_marked.emit(i, level, "；".join(issues))
		results.append({"index": i, "level": level, "issues": issues})
	return results
