class_name APIBuilder
extends RefCounted


static func build_api_messages(messages: Array) -> Array:
	var result: Array = []
	for m in messages:
		var msg: Dictionary = {"role": m.get("role", "user")}
		var content: String = m.get("content", "")
		var reasoning: String = m.get("reasoning", "")

		if msg["role"] == "tool":
			var tc_id: String = m.get("tool_call_id", "")
			if not tc_id.is_empty():
				msg["tool_call_id"] = tc_id
				msg["content"] = content
				if m.has("name"):
					msg["name"] = m["name"]
			else:
				msg["role"] = "user"
				msg["content"] = "[工具返回]\n" + content
			result.append(msg)
			continue

		if msg["role"] == "assistant":
			var tc_data: Array = m.get("tool_calls", [])
			if not tc_data.is_empty():
				msg["tool_calls"] = tc_data
				if not content.is_empty():
					msg["content"] = content
				if not reasoning.is_empty():
					msg["reasoning_content"] = reasoning
				result.append(msg)
				continue

			var carry: bool = m.get("carry_reasoning", false)
			if carry and not reasoning.is_empty():
				msg["reasoning_content"] = reasoning
				if not content.is_empty():
					msg["content"] = content
			elif not reasoning.is_empty():
				if not content.is_empty():
					msg["content"] = reasoning + "\n" + content
				else:
					msg["content"] = reasoning
			elif not content.is_empty():
				msg["content"] = content
			else:
				continue

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
	stream: bool = true,
	tools: Array = []
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
	if not tools.is_empty():
		body["tools"] = tools
	return body


static func build_tools() -> Array:
	return [{
		"type": "function",
		"function": {
			"name": "read",
			"description": "从本地文件系统读取文件或目录。如果路径不存在，则返回错误。\n\n使用说明：\n- filePath 参数必须是绝对路径\n- 默认情况下，此工具从文件开头返回最多 2000 行\n- offset 参数是开始读取的行号（从 1 开始）\n- 要读取后面的内容，使用更大的 offset 重新调用此工具\n- 使用 grep 工具在大文件或长行文件中查找特定内容\n- 如果不确定文件路径是否正确，使用 glob 工具按 glob 模式查找文件名\n- 返回内容中每行以 <行号>: <内容> 格式显示\n- 超过 2000 个字符的行会被截断\n- 当你确定需要读取多个文件时，并行调用此工具\n- 避免频繁小段读取（30 行的块）。如果需要更多上下文，读取更大的范围",
			"parameters": {
				"type": "object",
				"properties": {
					"filePath": {
						"type": "string",
						"description": "要读取的文件路径。必须是绝对路径。"
					}
				},
				"required": ["filePath"]
			}
		}
	}]


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
