extends Control
class_name ExperimentPanel

signal experiment_saved(path: String)

var api_key: String = ""

var _config: ConfigManager
var _store: ExperimentStore
var _deepseek: DeepSeekStreamClient
var _messages: Array = []
var _message_widgets: Array = []
var _accumulated_content: String = ""
var _accumulated_reasoning: String = ""
var _last_response_body: String = ""
var _last_usage: Dictionary = {}

var _model: String = "deepseek-v4-flash"
var _thinking: String = "enabled"
var _effort: String = "high"
var _max_tokens: int = 4096

@onready var params_model: OptionButton = %ParamsModel
@onready var params_thinking: OptionButton = %ParamsThinking
@onready var params_effort: OptionButton = %ParamsEffort
@onready var params_max_tokens: SpinBox = %ParamsMaxTokens
@onready var params_title: LineEdit = %ParamsTitle

@onready var msg_list: VBoxContainer = %MsgList
@onready var msg_scroll: ScrollContainer = %MsgScroll
@onready var msg_count: Label = %MsgCount
@onready var add_btn: MenuButton = %AddBtn

@onready var send_btn: Button = %SendBtn
@onready var save_btn: Button = %SaveBtn
@onready var clear_btn: Button = %ClearBtn
@onready var view_req_btn: Button = %ViewReqBtn
@onready var template_btn: MenuButton = %TemplateBtn
@onready var settings_btn: Button = %SettingsBtn

@onready var log_request: TextEdit = %LogRequest
@onready var log_response: TextEdit = %LogResponse
@onready var log_usage: Label = %LogUsage
@onready var req_tab: Button = %ReqTab
@onready var res_tab: Button = %ResTab

@onready var notes_input: TextEdit = %NotesInput
@onready var status_label: Label = %StatusBar


func _ready() -> void:
	_config = ConfigManager.new()
	api_key = _config.api_key
	_store = ExperimentStore.new(_config.experiments_path, _config.templates_path)
	_build_dynamic()


func _build_dynamic() -> void:
	_build_settings_menu()
	params_model.add_item("deepseek-v4-flash")
	params_model.add_item("deepseek-v4-pro")
	params_model.select(0)
	params_model.item_selected.connect(func(idx: int): _model = params_model.get_item_text(idx))

	params_thinking.add_item("enabled")
	params_thinking.add_item("disabled")
	params_thinking.select(0)
	params_thinking.item_selected.connect(func(idx: int): _thinking = params_thinking.get_item_text(idx))

	params_effort.add_item("high")
	params_effort.add_item("max")
	params_effort.add_item("不传")
	params_effort.select(0)
	params_effort.item_selected.connect(func(idx: int): _effort = params_effort.get_item_text(idx))

	params_max_tokens.min_value = 256
	params_max_tokens.max_value = 384000
	params_max_tokens.step = 256
	params_max_tokens.value = _max_tokens
	params_max_tokens.value_changed.connect(func(v: float): _max_tokens = int(v))

	_params_add()
	_populate_add_btn()
	_connect_signals()
	_store.seed_builtin_templates()
	req_tab.toggled.connect(_on_tab_toggled.bind("req"))
	res_tab.toggled.connect(_on_tab_toggled.bind("res"))


func _params_add() -> void:
	var hbox: HBoxContainer = get_node_or_null("VBox/ParamsPanel/ParamsHBox")
	if hbox == null:
		return
	var labels := ["模型", "思考模式", "推理强度", "max_tokens", "实验标题"]
	for i in labels.size():
		var lbl := Label.new()
		lbl.text = labels[i]
		hbox.add_child(lbl)
		hbox.move_child(lbl, i * 2)


func _populate_add_btn() -> void:
	var popup := add_btn.get_popup()
	popup.add_item("system")
	popup.add_item("user")
	popup.add_item("assistant (content)")
	popup.add_item("assistant (reasoning)")
	popup.add_item("assistant (tool_calls)")
	popup.add_item("tool")
	popup.id_pressed.connect(_on_add_block)


func _connect_signals() -> void:
	send_btn.pressed.connect(_on_send)
	save_btn.pressed.connect(_on_save)
	clear_btn.pressed.connect(_on_clear)
	view_req_btn.pressed.connect(_show_request_body)
	settings_btn.pressed.connect(_open_settings)
	_populate_template_menu()


func _build_settings_menu() -> void:
	pass


func _populate_template_menu() -> void:
	var popup := template_btn.get_popup()
	popup.clear()
	var templates := _store.list_templates()
	for t in templates:
		var tname: String = t.get("name", "")
		popup.add_item(tname)
	if popup.item_count > 0:
		popup.add_separator("")
	popup.add_item("💾 保存当前为模板")
	popup.id_pressed.connect(_on_template_selected)


func _on_template_selected(id: int) -> void:
	var popup := template_btn.get_popup()
	var item_text: String = popup.get_item_text(id)
	if item_text.begins_with("💾"):
		_save_current_as_template()
		return
	var t := _store.load_template(item_text)
	if t.is_empty():
		return
	var template_msgs: Array = t.get("messages", [])
	for m in template_msgs:
		_messages.append(m.duplicate(true))
	_rebuild_list()
	_set_status("已插入模板: " + item_text)


func _save_current_as_template() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "保存为模板"
	dialog.min_size = Vector2(300, 120)
	var vbox := VBoxContainer.new()
	var name_input := LineEdit.new()
	name_input.placeholder_text = "模板名称"
	vbox.add_child(name_input)
	var done_btn := Button.new()
	done_btn.text = "保存"
	done_btn.pressed.connect(func():
		var tname := name_input.text.strip_edges()
		if tname.is_empty():
			return
		_store.save_template(tname, _model, _thinking, _effort, _max_tokens, _messages)
		dialog.queue_free()
		_populate_template_menu()
		_set_status("已保存模板: " + tname)
	)
	vbox.add_child(done_btn)
	dialog.add_child(vbox)
	add_child(dialog)
	dialog.popup_centered()
	await dialog.tree_exited


func _on_tab_toggled(on: bool, tab: String) -> void:
	if not on:
		return
	if tab == "req":
		log_request.visible = true
		log_response.visible = false
		res_tab.button_pressed = false
	else:
		log_response.visible = true
		log_request.visible = false
		req_tab.button_pressed = false


func _add_block_with_role(role: String, subtype: String = "content") -> void:
	var block := {"role": role, "content": "", "reasoning": "", "tool_calls": []}
	if subtype == "reasoning":
		block["reasoning"] = "在此输入思考过程..."
	elif role == "tool":
		block["tool_call_id"] = ""
		block["name"] = ""
	_messages.append(block)
	_rebuild_list()
	_scroll_to_bottom()


func _on_add_block(id: int) -> void:
	match id:
		0: _add_block_with_role("system")
		1: _add_block_with_role("user")
		2: _add_block_with_role("assistant", "content")
		3: _add_block_with_role("assistant", "reasoning")
		4: _add_block_with_role("assistant")
		5: _add_block_with_role("tool")


func _rebuild_list() -> void:
	for child in msg_list.get_children():
		msg_list.remove_child(child)
		child.queue_free()
	_message_widgets.clear()

	for i in _messages.size():
		var w := _build_block_widget(i, _messages[i])
		_message_widgets.append(w)
		msg_list.add_child(w.container)

	msg_count.text = str(_messages.size()) + " 条"


func _build_block_widget(idx: int, data: Dictionary) -> Dictionary:
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL

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
	var preview_label := Label.new()
	preview_label.text = preview
	preview_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(preview_label)

	if has_reasoning:
		var rtag := Label.new()
		rtag.text = "🧠" + str(data["reasoning"].length())
		rtag.add_theme_color_override("font_color", Color(0.8, 0.6, 0.2))
		rtag.custom_minimum_size.x = 60
		header.add_child(rtag)

	var expand_btn := Button.new()
	expand_btn.text = "▼"
	expand_btn.custom_minimum_size.x = 24
	expand_btn.toggle_mode = true
	header.add_child(expand_btn)

	var edit_btn := Button.new()
	edit_btn.text = "✏"
	edit_btn.custom_minimum_size.x = 24
	header.add_child(edit_btn)

	var up_btn := Button.new()
	up_btn.text = "↑"
	up_btn.custom_minimum_size.x = 22
	header.add_child(up_btn)

	var down_btn := Button.new()
	down_btn.text = "↓"
	down_btn.custom_minimum_size.x = 22
	header.add_child(down_btn)

	var del_btn := Button.new()
	del_btn.text = "✕"
	del_btn.custom_minimum_size.x = 22
	header.add_child(del_btn)

	root.add_child(header)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.visible = false

	if has_reasoning:
		var rlbl := Label.new()
		rlbl.text = "━━━ reasoning_content（原始思考过程）━━━"
		rlbl.add_theme_color_override("font_color", Color(0.8, 0.6, 0.2))
		body.add_child(rlbl)
		var rte := TextEdit.new()
		rte.text = data.get("reasoning", "")
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
		var cte := TextEdit.new()
		cte.text = data.get("content", "")
		cte.custom_minimum_size.y = 120
		cte.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cte.size_flags_vertical = Control.SIZE_EXPAND_FILL
		cte.text_changed.connect(func(): data["content"] = cte.text)
		body.add_child(cte)

	expand_btn.toggled.connect(func(on: bool):
		body.visible = on
		expand_btn.text = "▲" if on else "▼"
	)

	edit_btn.pressed.connect(func(): _edit_block(idx))
	up_btn.pressed.connect(func(): _move_block(idx, -1))
	down_btn.pressed.connect(func(): _move_block(idx, 1))
	del_btn.pressed.connect(func(): _remove_block(idx))

	root.add_child(body)
	return {"container": root, "header": header, "body": body, "index_label": index_label, "role_label": role_label, "preview_label": preview_label}


func _role_color(role: String) -> Color:
	match role:
		"system": return Color(0.6, 0.4, 1.0)
		"user": return Color(0.4, 0.8, 1.0)
		"assistant": return Color(0.4, 1.0, 0.6)
		"tool": return Color(1.0, 0.8, 0.3)
		_: return Color(1.0, 1.0, 1.0)


func _edit_block(idx: int) -> void:
	if idx < 0 or idx >= _messages.size():
		return
	var data: Dictionary = _messages[idx]
	var dialog := AcceptDialog.new()
	dialog.title = "编辑积木 #" + str(idx)
	dialog.min_size = Vector2(500, 400)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var role_edit := LineEdit.new()
	role_edit.text = data.get("role", "")
	vbox.add_child(_make_label("role:"))
	vbox.add_child(role_edit)

	var content_edit := TextEdit.new()
	content_edit.text = data.get("content", "")
	content_edit.custom_minimum_size.y = 100
	content_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_make_label("content:"))
	vbox.add_child(content_edit)

	if data.has("reasoning"):
		var re_edit := TextEdit.new()
		re_edit.text = data.get("reasoning", "")
		re_edit.custom_minimum_size.y = 80
		re_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_child(_make_label("reasoning:"))
		vbox.add_child(re_edit)
		re_edit.text_changed.connect(func(): data["reasoning"] = re_edit.text)

	var done_btn := Button.new()
	done_btn.text = "确认"
	done_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	done_btn.pressed.connect(func():
		data["role"] = role_edit.text
		data["content"] = content_edit.text
		dialog.queue_free()
		_rebuild_list()
	)
	vbox.add_child(done_btn)

	dialog.add_child(vbox)
	add_child(dialog)
	dialog.popup_centered()
	await dialog.tree_exited


func _move_block(idx: int, dir: int) -> void:
	var target := idx + dir
	if target < 0 or target >= _messages.size():
		return
	var temp: Dictionary = _messages[idx]
	_messages[idx] = _messages[target]
	_messages[target] = temp
	_rebuild_list()


func _remove_block(idx: int) -> void:
	if idx < 0 or idx >= _messages.size():
		return
	_messages.remove_at(idx)
	_rebuild_list()


func _on_clear() -> void:
	_messages.clear()
	log_request.text = ""
	log_response.text = ""
	log_usage.text = ""
	_last_response_body = ""
	_last_usage = {}
	_rebuild_list()
	_set_status("已清空")


func _on_send() -> void:
	if _messages.is_empty():
		_set_status("消息列表为空，无法发送")
		return

	_set_status("发送中...")
	send_btn.disabled = true

	var msgs_to_send := _build_api_messages()
	var body_dict := {
		"model": _model,
		"messages": msgs_to_send,
		"stream": true,
	}
	if _thinking == "enabled":
		body_dict["thinking"] = {"type": "enabled"}
	if _effort != "不传":
		body_dict["reasoning_effort"] = _effort
	body_dict["max_tokens"] = _max_tokens

	var body_str := JSON.stringify(body_dict, "\t")
	log_request.text = body_str

	_accumulated_content = ""
	_accumulated_reasoning = ""

	var idx := _messages.size()
	var new_msg := {"role": "assistant", "content": "", "reasoning": ""}
	_messages.append(new_msg)
	_rebuild_list()
	_set_status("等待回复...")

	_deepseek = DeepSeekStreamClient.new()
	add_child(_deepseek)
	_deepseek.api_key = api_key
	_deepseek.content_chunk.connect(_on_content_chunk.bind(idx))
	_deepseek.reasoning_chunk.connect(_on_reasoning_chunk.bind(idx))
	_deepseek.stream_finished.connect(_on_stream_finished.bind(body_str))
	_deepseek.usage_received.connect(_on_usage_received)
	_deepseek.connection_error.connect(_on_connection_error)
	_deepseek.start_streaming(msgs_to_send)


func _build_api_messages() -> Array:
	var result: Array = []
	for m in _messages:
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


func _on_content_chunk(text: String, msg_idx: int) -> void:
	_accumulated_content += text
	_messages[msg_idx]["content"] = _accumulated_content
	_update_block_preview(msg_idx)
	_set_status("生成中... (" + str(_accumulated_content.length()) + " 字)")


func _on_reasoning_chunk(text: String, msg_idx: int) -> void:
	_accumulated_reasoning += text
	_messages[msg_idx]["reasoning"] = _accumulated_reasoning
	_update_block_preview(msg_idx)
	_set_status("思考中... (" + str(_accumulated_reasoning.length()) + " 字)")


func _on_stream_finished(_body_str: String) -> void:
	_set_status("流式接收完成")
	send_btn.disabled = false

	_messages[_messages.size() - 1]["content"] = _accumulated_content
	_messages[_messages.size() - 1]["reasoning"] = _accumulated_reasoning
	_rebuild_list()

	_last_response_body = JSON.stringify({
		"choices": [{
			"index": 0,
			"message": {
				"role": "assistant",
				"content": _accumulated_content,
				"reasoning_content": _accumulated_reasoning
			}
		}]
	}, "\t")
	log_response.text = _last_response_body

	_deepseek.queue_free()
	_deepseek = null


func _on_usage_received(usage: Dictionary) -> void:
	_last_usage = usage
	var rt: int = usage.get("completion_tokens_details", {}).get("reasoning_tokens", 0)
	log_usage.text = "prompt: %d  completion: %d  reasoning: %d  total: %d" % [
		usage.get("prompt_tokens", 0),
		usage.get("completion_tokens", 0),
		rt,
		usage.get("total_tokens", 0)
	]


func _on_connection_error(msg: String) -> void:
	_set_status("连接错误: " + msg)
	send_btn.disabled = false
	if _deepseek:
		_deepseek.queue_free()
		_deepseek = null


func _update_block_preview(idx: int) -> void:
	if idx < 0 or idx >= _message_widgets.size():
		return
	var data: Dictionary = _messages[idx]
	var preview: String = data.get("content", "")
	if data.has("reasoning") and not data.get("reasoning", "").is_empty():
		preview = "🧠[%d] %s" % [data["reasoning"].length(), data["reasoning"]]
	preview = preview.left(50).replace("\n", " ")
	_message_widgets[idx].preview_label.text = preview


func _on_save() -> void:
	var title := params_title.text.strip_edges()
	if title.is_empty() and _messages.size() > 0:
		title = _messages[0].get("content", "")
		title = title.left(20).replace("\n", " ")
	if title.is_empty():
		title = "untitled"

	var msgs_to_send := _build_api_messages()
	var fpath := _store.save_experiment(
		title, _model, _thinking, _effort, _max_tokens,
		msgs_to_send, _messages,
		log_request.text, _last_response_body,
		_last_usage, notes_input.text
	)
	if fpath.is_empty():
		_set_status("保存失败")
	else:
		_set_status("已保存: " + fpath.get_file())
		experiment_saved.emit(fpath)


func _show_request_body() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "请求体"
	dialog.min_size = Vector2(600, 400)
	var te := TextEdit.new()
	te.text = log_request.text
	te.editable = false
	te.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	te.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dialog.add_child(te)
	add_child(dialog)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.popup_centered()
	await dialog.tree_exited


func _open_settings() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "设置"
	dialog.min_size = Vector2(500, 350)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)

	var key_label := Label.new()
	key_label.text = "DeepSeek API Key"
	vbox.add_child(key_label)
	var key_input := LineEdit.new()
	key_input.text = _config.api_key
	key_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_input.secret = true
	vbox.add_child(key_input)

	var exp_label := Label.new()
	exp_label.text = "实验存储路径"
	vbox.add_child(exp_label)
	var exp_row := HBoxContainer.new()
	exp_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var exp_input := LineEdit.new()
	exp_input.text = _config.experiments_path
	exp_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	exp_row.add_child(exp_input)
	var exp_open := Button.new()
	exp_open.text = "打开文件夹"
	exp_open.pressed.connect(func(): _config.open_in_explorer(_config.experiments_path))
	exp_row.add_child(exp_open)
	vbox.add_child(exp_row)

	var tpl_label := Label.new()
	tpl_label.text = "模板存储路径"
	vbox.add_child(tpl_label)
	var tpl_row := HBoxContainer.new()
	tpl_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tpl_input := LineEdit.new()
	tpl_input.text = _config.templates_path
	tpl_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tpl_row.add_child(tpl_input)
	var tpl_open := Button.new()
	tpl_open.text = "打开文件夹"
	tpl_open.pressed.connect(func(): _config.open_in_explorer(_config.templates_path))
	tpl_row.add_child(tpl_open)
	vbox.add_child(tpl_row)

	var ses_label := Label.new()
	ses_label.text = "会话存储路径"
	vbox.add_child(ses_label)
	var ses_row := HBoxContainer.new()
	ses_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ses_input := LineEdit.new()
	ses_input.text = _config.sessions_path
	ses_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ses_row.add_child(ses_input)
	var ses_open := Button.new()
	ses_open.text = "打开文件夹"
	ses_open.pressed.connect(func(): _config.open_in_explorer(_config.sessions_path))
	ses_row.add_child(ses_open)
	vbox.add_child(ses_row)

	var save_btn_dialog := Button.new()
	save_btn_dialog.text = "保存"
	save_btn_dialog.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_btn_dialog.pressed.connect(func():
		_config.api_key = key_input.text
		_config.experiments_path = exp_input.text
		_config.templates_path = tpl_input.text
		_config.sessions_path = ses_input.text
		_config.save_config()
		api_key = _config.api_key
		_store = ExperimentStore.new(_config.experiments_path, _config.templates_path)
		_populate_template_menu()
		dialog.queue_free()
		_set_status("已保存设置")
	)
	vbox.add_child(save_btn_dialog)

	dialog.add_child(vbox)
	add_child(dialog)
	dialog.popup_centered()
	await dialog.tree_exited


func _scroll_to_bottom() -> void:
	msg_scroll.scroll_vertical = int(msg_scroll.get_v_scroll_bar().max_value)


func _set_status(text: String) -> void:
	status_label.text = text


func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label
