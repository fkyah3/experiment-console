class_name ExperimentModel
extends RefCounted

signal messages_changed
signal message_updated(idx: int)

var messages: Array = []:
	get: return messages
var size: int:
	get: return messages.size()


func clear() -> void:
	messages.clear()
	messages_changed.emit()


func add(role: String, subtype: String = "content") -> int:
	var block := {"role": role, "content": "", "reasoning": "", "tool_calls": [], "carry_reasoning": role == "assistant"}
	if subtype == "reasoning":
		block["reasoning"] = "在此输入思考过程..."
	elif role == "tool":
		block["tool_call_id"] = ""
		block["name"] = ""
	messages.append(block)
	messages_changed.emit()
	return messages.size() - 1


func append(data: Dictionary) -> void:
	messages.append(data)
	messages_changed.emit()


func remove_at(idx: int) -> void:
	if idx < 0 or idx >= messages.size():
		return
	messages.remove_at(idx)
	messages_changed.emit()


func move(idx: int, dir: int) -> void:
	var target := idx + dir
	if target < 0 or target >= messages.size():
		return
	var temp: Dictionary = messages[idx]
	messages[idx] = messages[target]
	messages[target] = temp
	messages_changed.emit()


func get_msg(idx: int) -> Dictionary:
	if idx < 0 or idx >= messages.size():
		return {}
	return messages[idx]


func update_content(idx: int, text: String) -> void:
	if idx < 0 or idx >= messages.size():
		return
	messages[idx]["content"] = text
	message_updated.emit(idx)


func update_reasoning(idx: int, text: String) -> void:
	if idx < 0 or idx >= messages.size():
		return
	messages[idx]["reasoning"] = text
	message_updated.emit(idx)


func duplicate_all() -> Array:
	return messages.duplicate(true)


func duplicate_messages() -> Array:
	var copies: Array = []
	for m in messages:
		copies.append(m.duplicate(true))
	return copies


func from_array(arr: Array) -> void:
	messages = arr.duplicate(true)
	messages_changed.emit()


func insert_template(template_msgs: Array) -> void:
	for m in template_msgs:
		messages.append(m.duplicate(true))
	messages_changed.emit()
