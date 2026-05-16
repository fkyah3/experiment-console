class_name BrickWidget
extends RefCounted

signal edit_requested(idx: int)
signal move_requested(idx: int, direction: int)
signal delete_requested(idx: int)

var container: VBoxContainer
var preview_label: Label
var _data: Dictionary
var _idx: int


func build(idx: int, data: Dictionary) -> VBoxContainer:
	_idx = idx
	_data = data
	container = VBoxContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	var index_label := Label.new()
	index_label.text = str(idx)
	index_label.custom_minimum_size.x = 24
	header.add_child(index_label)

	var role_label := Label.new()
	role_label.text = data.get("role", "?")
	role_label.custom_minimum_size.x = 100
	role_label.add_theme_color_override("font_color", _role_color(data.get("role", "")))
	header.add_child(role_label)

	var preview: String = data.get("content", "")
	var has_reasoning: bool = data.has("reasoning") and not String(data.get("reasoning", "")).is_empty()
	if preview.is_empty():
		if has_reasoning:
			preview = "🧠[%d] %s" % [data["reasoning"].length(), data["reasoning"].left(50)]
	else:
		preview = preview.left(50)
	preview = preview.replace("\n", " ")
	preview_label = Label.new()
	preview_label.text = preview
	preview_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(preview_label)

	if has_reasoning:
		var rtag := Label.new()
		rtag.text = "🧠" + str(data["reasoning"].length())
		rtag.add_theme_color_override("font_color", Color(0.8, 0.6, 0.2))
		rtag.custom_minimum_size.x = 60
		header.add_child(rtag)

	if data.get("role", "") == "assistant":
		var carry_cb := CheckBox.new()
		carry_cb.text = "携带"
		carry_cb.button_pressed = data.get("carry_reasoning", true)
		carry_cb.toggled.connect(func(on: bool): data["carry_reasoning"] = on)
		header.add_child(carry_cb)

	var expand_btn := Button.new()
	expand_btn.text = "▼"
	expand_btn.custom_minimum_size.x = 24
	expand_btn.toggle_mode = true
	header.add_child(expand_btn)

	var edit_btn := Button.new()
	edit_btn.text = "✏"
	edit_btn.custom_minimum_size.x = 24
	edit_btn.pressed.connect(func(): edit_requested.emit(idx))
	header.add_child(edit_btn)

	var up_btn := Button.new()
	up_btn.text = "↑"
	up_btn.custom_minimum_size.x = 22
	up_btn.pressed.connect(func(): move_requested.emit(idx, -1))
	header.add_child(up_btn)

	var down_btn := Button.new()
	down_btn.text = "↓"
	down_btn.custom_minimum_size.x = 22
	down_btn.pressed.connect(func(): move_requested.emit(idx, 1))
	header.add_child(down_btn)

	var del_btn := Button.new()
	del_btn.text = "✕"
	del_btn.custom_minimum_size.x = 22
	del_btn.pressed.connect(func(): delete_requested.emit(idx))
	header.add_child(del_btn)

	container.add_child(header)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.visible = false

	if has_reasoning:
		var rlbl := Label.new()
		rlbl.text = "━━━ reasoning_content（原始思考过程）━━━"
		rlbl.add_theme_color_override("font_color", Color(0.8, 0.6, 0.2))
		body.add_child(rlbl)
		var raw_reasoning: String = str(data.get("reasoning", ""))
		if raw_reasoning.length() > 50000:
			var truncated := raw_reasoning.left(5000) + "\n\n...（共 %d 字，已截断）" % raw_reasoning.length()
			var rte := TextEdit.new()
			rte.text = truncated
			rte.custom_minimum_size.y = 120
			rte.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			rte.size_flags_vertical = Control.SIZE_EXPAND_FILL
			rte.editable = false
			body.add_child(rte)
		else:
			var rte := TextEdit.new()
			rte.text = raw_reasoning
			rte.custom_minimum_size.y = 120
			rte.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			rte.size_flags_vertical = Control.SIZE_EXPAND_FILL
			rte.text_changed.connect(func(): data["reasoning"] = rte.text)
			body.add_child(rte)

	if data.has("content") and not data.get("content", "").is_empty():
		var clbl := Label.new()
		clbl.text = "━━━ content（最终回答）━━━"
		clbl.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
		body.add_child(clbl)
		var raw_content: String = str(data.get("content", ""))
		if raw_content.length() > 50000:
			var truncated := raw_content.left(5000) + "\n\n...（共 %d 字，已截断，可在报告中查看全文）" % raw_content.length()
			var cte := TextEdit.new()
			cte.text = truncated
			cte.custom_minimum_size.y = 120
			cte.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cte.size_flags_vertical = Control.SIZE_EXPAND_FILL
			cte.editable = false
			body.add_child(cte)
		else:
			var cte := TextEdit.new()
			cte.text = raw_content
			cte.custom_minimum_size.y = 120
			cte.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cte.size_flags_vertical = Control.SIZE_EXPAND_FILL
			cte.text_changed.connect(func(): data["content"] = cte.text)
			body.add_child(cte)

	expand_btn.toggled.connect(func(on: bool):
		body.visible = on
		expand_btn.text = "▲" if on else "▼"
	)

	container.add_child(body)
	return container


func update_preview() -> void:
	if _data == null or preview_label == null:
		return
	var preview: String = _data.get("content", "")
	if _data.has("reasoning") and not _data.get("reasoning", "").is_empty():
		preview = "🧠[%d] %s" % [_data["reasoning"].length(), _data["reasoning"]]
	preview = preview.left(50).replace("\n", " ")
	preview_label.text = preview


func _role_color(role: String) -> Color:
	match role:
		"system": return Color(0.6, 0.4, 1.0)
		"user": return Color(0.4, 0.8, 1.0)
		"assistant": return Color(0.4, 1.0, 0.6)
		"tool": return Color(1.0, 0.8, 0.3)
		_: return Color(1.0, 1.0, 1.0)
