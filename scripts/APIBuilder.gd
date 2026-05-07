class_name APIBuilder
extends RefCounted


static func build_api_messages(messages: Array) -> Array:
	var result: Array = []
	for m in messages:
		var msg: Dictionary = {"role": m.get("role", "user")}
		var content: String = m.get("content", "")
		var reasoning: String = m.get("reasoning", "")

		if msg["role"] == "assistant":
			if not reasoning.is_empty():
				if not content.is_empty():
					msg["content"] = reasoning + "\n" + content
				else:
					msg["reasoning_content"] = reasoning
					msg["content"] = null

		if not content.is_empty() and not msg.has("content"):
			msg["content"] = content

		result.append(msg)
	return result


static func build_body_dict(
	model: String,
	thinking: String,
	effort: String,
	max_tokens: int,
	temperature: float,
	msg_list: Array,
	top_p: float = 1.0,
	frequency_penalty: float = 0.0,
	stream: bool = true
) -> Dictionary:
	var body := {
		"model": model,
		"messages": msg_list,
		"stream": stream,
	}
	if thinking == "官方预设":
		body["thinking"] = {"type": "enabled"}
		if effort != "不传":
			body["reasoning_effort"] = effort
	elif thinking == "自定义":
		body["thinking"] = {"type": "disabled"}
		body["top_p"] = top_p
		body["frequency_penalty"] = frequency_penalty
	body["max_tokens"] = max_tokens
	body["temperature"] = temperature
	return body


static func build_response_body(content: String, reasoning: String, indent: String = "\t") -> String:
	return JSON.stringify({
		"choices": [{
			"index": 0,
			"message": {
				"role": "assistant",
				"content": content,
				"reasoning_content": reasoning
			}
		}]
	}, indent)


static func detect_language(text: String) -> String:
	if text.is_empty():
		return "empty"
	var chinese_count := 0
	var total := 0
	for c in text:
		var unicode := c.unicode_at(0)
		if unicode >= 0x4E00 and unicode <= 0x9FFF:
			chinese_count += 1
		if unicode >= 0x0020:
			total += 1
	if total == 0:
		return "unknown"
	var ratio := float(chinese_count) / float(total)
	if ratio > 0.1:
		return "zh"
	return "en"
