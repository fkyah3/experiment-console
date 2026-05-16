class_name APIBuilder
extends RefCounted


static func build_api_messages(messages: Array) -> Array:
	var result: Array = []
	for m in messages:
		var msg: Dictionary = {"role": m.get("role", "user")}
		var raw_content = m.get("content")
		var content: String = "" if raw_content == null else str(raw_content)
		var raw_reasoning = m.get("reasoning")
		var reasoning: String = "" if raw_reasoning == null else str(raw_reasoning)

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

			if not reasoning.is_empty():
				msg["reasoning_content"] = reasoning
			if not content.is_empty():
				msg["content"] = content
			if reasoning.is_empty() and content.is_empty():
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
	tools: Array = [],
	provider: String = "deepseek"
) -> Dictionary:
	var body := {
		"model": model,
		"messages": msg_list,
		"stream": stream,
	}
	if thinking == "思考模式":
		body["thinking"] = {"type": "enabled"}
		if effort != "不传":
			body["reasoning_effort"] = effort
	elif thinking == "无思考模式":
		if provider == "deepseek":
			body["thinking"] = {"type": "disabled"}
		body["top_p"] = top_p
		body["frequency_penalty"] = frequency_penalty
	body["max_tokens"] = max_tokens
	body["temperature"] = temperature
	if not tools.is_empty():
		body["tools"] = tools
		body["tool_choice"] = "auto"
	return body


static func build_tools() -> Array:
	return [{
		"type": "function",
		"function": {
			"name": "list_dir",
			"description": "列出工作区目录中的文件和子目录。用于探索项目结构，找到需要读取的文件。",
			"parameters": {
				"type": "object",
				"properties": {
					"dirPath": {
						"type": "string",
						"description": "要列出的目录路径，相对于工作区根目录。默认 \".\"（根目录）。"
					}
				}
			}
		}
	}, {
		"type": "function",
		"function": {
			"name": "read",
			"description": "读取工作区中的文件内容。先使用 list_dir 找到文件路径，再用此工具读取。",
			"parameters": {
				"type": "object",
				"properties": {
					"filePath": {
						"type": "string",
						"description": "要读取的文件路径，相对于工作区根目录。"
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
