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
var _temperature: float = 0.0

var _batch_queue: Array = []
var _batch_running: int = 0
var _batch_done: int = 0
var _batch_failed: int = 0
var _batch_total: int = 0
var _batch_dir: String = ""
var _batch_save_store: ExperimentStore
var _batch_stats: Array[Dictionary] = []
var _batch_prototype_messages: Array = []
var _batch_start_ms: int = 0
const BATCH_CONCURRENCY: int = 5

@onready var params_model: OptionButton = %ParamsModel
@onready var params_thinking: OptionButton = %ParamsThinking
@onready var params_effort: OptionButton = %ParamsEffort
@onready var params_max_tokens: SpinBox = %ParamsMaxTokens
@onready var params_temperature: SpinBox = %ParamsTemperature
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
@onready var batch_btn: Button = %BatchBtn
@onready var reader_btn: Button = %ReaderBtn
@onready var batch_reader = %BatchReader

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

	params_temperature.min_value = 0.0
	params_temperature.max_value = 2.0
	params_temperature.step = 0.1
	params_temperature.value = _temperature
	params_temperature.value_changed.connect(func(v: float): _temperature = v)

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
	var labels := ["模型", "思考模式", "推理强度", "max_tokens", "温度", "实验标题"]
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
	batch_btn.pressed.connect(_on_batch_run)
	reader_btn.pressed.connect(_toggle_reader)
	batch_reader.back_requested.connect(_toggle_reader)
	_populate_template_menu()


func _build_settings_menu() -> void:
	pass


func _populate_template_menu() -> void:
	var popup := template_btn.get_popup()
	popup.clear()
	if popup.id_pressed.is_connected(_on_template_selected):
		popup.id_pressed.disconnect(_on_template_selected)
	var templates := _store.list_templates()
	for t in templates:
		var tname: String = t.get("name", "")
		popup.add_item(tname)
	if popup.item_count > 0:
		popup.add_separator("")
	popup.add_item("💾 保存当前为模板")
	popup.add_item("🗑 删除模板")
	popup.id_pressed.connect(_on_template_selected)


func _on_template_selected(id: int) -> void:
	var popup := template_btn.get_popup()
	var item_text: String = popup.get_item_text(id)
	if item_text.begins_with("💾"):
		_save_current_as_template()
		return
	if item_text.begins_with("🗑"):
		_show_delete_template_dialog()
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


func _show_delete_template_dialog() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "删除模板"
	dialog.min_size = Vector2(350, 200)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var templates := _store.list_templates()
	if templates.is_empty():
		vbox.add_child(_make_label("没有已保存的模板。"))
	else:
		for t in templates:
			var tname: String = t.get("name", "")
			var row := HBoxContainer.new()
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var label := Label.new()
			label.text = tname
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(label)
			var del_btn := Button.new()
			del_btn.text = "删除"
			del_btn.pressed.connect(func(n := tname):
				_store.delete_template(n)
				dialog.queue_free()
				_show_delete_template_dialog()
				_populate_template_menu()
				_set_status("已删除模板: " + n)
			)
			row.add_child(del_btn)
			vbox.add_child(row)

	scroll.add_child(vbox)
	dialog.add_child(scroll)
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
	body_dict["temperature"] = _temperature

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
	if msg_idx < 0 or msg_idx >= _messages.size():
		return
	_accumulated_content += text
	_messages[msg_idx]["content"] = _accumulated_content
	_update_block_preview(msg_idx)
	_set_status("生成中... (" + str(_accumulated_content.length()) + " 字)")


func _on_reasoning_chunk(text: String, msg_idx: int) -> void:
	if msg_idx < 0 or msg_idx >= _messages.size():
		return
	_accumulated_reasoning += text
	_messages[msg_idx]["reasoning"] = _accumulated_reasoning
	_update_block_preview(msg_idx)
	_set_status("思考中... (" + str(_accumulated_reasoning.length()) + " 字)")


func _on_stream_finished(_body_str: String) -> void:
	_set_status("流式接收完成")
	send_btn.disabled = false

	if not _messages.is_empty():
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

	if _deepseek:
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
		title, _model, _thinking, _effort, _max_tokens, _temperature,
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


func _on_batch_run() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "批量运行"
	dialog.min_size = Vector2(350, 150)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)

	vbox.add_child(_make_label("运行次数"))
	var count_input := SpinBox.new()
	count_input.min_value = 1
	count_input.max_value = 100
	count_input.value = 20
	count_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(count_input)

	vbox.add_child(_make_label("批次名称（可选）"))
	var batch_name_input := LineEdit.new()
	batch_name_input.placeholder_text = "会追加到目录名上"
	batch_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(batch_name_input)

	var start_btn := Button.new()
	start_btn.text = "开始"
	start_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start_btn.pressed.connect(func():
		var count := int(count_input.value)
		var bname := batch_name_input.text.strip_edges()
		dialog.queue_free()
		_start_batch(count, bname)
	)
	vbox.add_child(start_btn)

	dialog.add_child(vbox)
	add_child(dialog)
	dialog.popup_centered()
	await dialog.tree_exited


func _start_batch(count: int, batch_name: String) -> void:
	if _messages.is_empty():
		_set_status("消息列表为空，无法批量运行")
		return

	_batch_total = count
	_batch_done = 0
	_batch_failed = 0
	_batch_running = 0
	_batch_stats.clear()
	_batch_prototype_messages = _messages.duplicate(true)
	_batch_start_ms = Time.get_ticks_msec()

	var now := Time.get_datetime_dict_from_system()
	var dir_name := "batch_%04d%02d%02d_%02d%02d" % [now.year, now.month, now.day, now.hour, now.minute]
	if not batch_name.is_empty():
		dir_name += "_" + batch_name.left(20)
	_batch_dir = _config.experiments_path.path_join(dir_name)
	_batch_save_store = ExperimentStore.new(_batch_dir, _config.templates_path)

	_batch_queue.clear()
	var raw_copies: Array = _messages.duplicate(true)
	for i in count:
		_batch_queue.append(raw_copies.duplicate(true))

	_set_status("批量 %d 次开始，5 个并发..." % count)
	for i in min(BATCH_CONCURRENCY, count):
		_start_batch_worker()


func _start_batch_worker() -> void:
	if _batch_queue.is_empty():
		return
	var raw_messages: Array = _batch_queue.pop_front()
	var api_messages := _build_api_messages_for(raw_messages)

	var body_dict := {
		"model": _model,
		"messages": api_messages,
		"stream": true,
	}
	if _thinking == "enabled":
		body_dict["thinking"] = {"type": "enabled"}
	if _effort != "不传":
		body_dict["reasoning_effort"] = _effort
	body_dict["max_tokens"] = _max_tokens
	body_dict["temperature"] = _temperature
	var body_str := JSON.stringify(body_dict, "\t")

	var client := DeepSeekStreamClient.new()
	add_child(client)
	client.api_key = api_key

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
		"index": _batch_total - _batch_queue.size() - _batch_running,
		"start_ms": Time.get_ticks_msec(),
	}

	_batch_running += 1
	client.content_chunk.connect(_on_batch_content_chunk.bind(wd))
	client.reasoning_chunk.connect(_on_batch_reasoning_chunk.bind(wd))
	client.stream_finished.connect(_on_batch_worker_done.bind(wd))
	client.usage_received.connect(_on_batch_usage.bind(wd))
	client.connection_error.connect(_on_batch_worker_error.bind(wd))
	client.start_streaming(api_messages)
	_set_status("批量 %d/%d | 运行中 %d | 失败 %d" % [_batch_done + _batch_failed, _batch_total, _batch_running, _batch_failed])


func _on_batch_content_chunk(text: String, wd: Dictionary) -> void:
	wd.content += text


func _on_batch_reasoning_chunk(text: String, wd: Dictionary) -> void:
	wd.reasoning += text


func _on_batch_usage(usage: Dictionary, wd: Dictionary) -> void:
	wd.usage = usage


func _on_batch_worker_done(wd: Dictionary) -> void:
	wd.response_body = JSON.stringify({
		"choices": [{
			"index": 0,
			"message": {
				"role": "assistant",
				"content": wd.content,
				"reasoning_content": wd.reasoning,
			}
		}]
	}, "\t")
	wd.ok = true
	_finish_batch_worker(wd)


func _on_batch_worker_error(msg: String, wd: Dictionary) -> void:
	push_warning("Batch worker #%d error: %s" % [wd.index, msg])
	wd.ok = false
	_finish_batch_worker(wd)


func _finish_batch_worker(wd: Dictionary) -> void:
	if wd.client:
		wd.client.queue_free()

	_batch_running -= 1

	if wd.ok:
		var title := params_title.text.strip_edges()
		if title.is_empty():
			title = "batch_%03d" % wd.index
		_batch_save_store.save_experiment(
			title, _model, _thinking, _effort, _max_tokens, _temperature,
			wd.api_messages, wd.raw_messages,
			wd.body_str, wd.response_body, wd.usage, ""
		)
		_batch_stats.append(_calc_worker_stats(wd))
		_batch_done += 1
	else:
		_batch_failed += 1

	_set_status("批量 %d/%d | 运行中 %d | 失败 %d" % [_batch_done + _batch_failed, _batch_total, _batch_running, _batch_failed])

	if _batch_done + _batch_failed >= _batch_total:
		_generate_batch_summary()
		_set_status("批量完成：成功 %d / %d，失败 %d" % [_batch_done, _batch_total, _batch_failed])
		return

	if not _batch_queue.is_empty():
		_start_batch_worker()


func _calc_worker_stats(wd: Dictionary) -> Dictionary:
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
	s["reasoning_language"] = _detect_language_str(wd.reasoning)
	s["output_language"] = _detect_language_str(wd.content)
	s["reasoning_first_line"] = wd.reasoning.left(80).replace("\n", " ")
	s["output_first_line"] = wd.content.left(80).replace("\n", " ")
	return s


func _detect_language_str(text: String) -> String:
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


func _generate_batch_summary() -> void:
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
	lines.append("- **总次数**: %d\n" % _batch_total)
	lines.append("- **成功**: %d\n" % _batch_done)
	lines.append("- **失败**: %d\n" % _batch_failed)
	lines.append("\n")

	lines.append("## 本次使用的 prompt\n\n")
	lines.append("```\n")
	var has_prompt := false
	for m in _batch_prototype_messages:
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

	if _batch_stats.is_empty():
		lines.append("无成功数据。\n")
	else:
		var reasoning_vals: Array[int] = []
		var prompt_vals: Array[int] = []
		var completion_vals: Array[int] = []
		var total_vals: Array[int] = []
		var zh_count: int = 0
		var en_count: int = 0
		for s in _batch_stats:
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
		lines.append("| prompt_tokens 平均值 | %.1f |\n" % (float(_sum(prompt_vals)) / float(prompt_vals.size())))
		lines.append("| completion_tokens 平均值 | %.1f |\n" % (float(_sum(completion_vals)) / float(completion_vals.size())))
		lines.append("| total_tokens 平均值 | %.1f |\n" % (float(_sum(total_vals)) / float(total_vals.size())))
		lines.append("| reasoning 中文占比 | %d / %d (%.1f%%) |\n" % [zh_count, _batch_stats.size(), float(zh_count) / float(_batch_stats.size()) * 100.0])
		lines.append("| reasoning 英文占比 | %d / %d (%.1f%%) |\n" % [en_count, _batch_stats.size(), float(en_count) / float(_batch_stats.size()) * 100.0])
		lines.append("\n")

		var total_duration_ms: int = Time.get_ticks_msec() - _batch_start_ms
		var avg_duration_ms: float = float(total_duration_ms) / float(max(1, _batch_stats.size()))
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
		for s in _batch_stats:
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


func _sum(arr: Array[int]) -> int:
	var total := 0
	for v in arr:
		total += v
	return total


func _median(arr: Array[int]) -> float:
	if arr.is_empty():
		return 0.0
	var sorted := arr.duplicate()
	sorted.sort()
	var mid := int(sorted.size() * 0.5)
	if sorted.size() % 2 == 0:
		return (sorted[mid - 1] + sorted[mid]) / 2.0
	return float(sorted[mid])


func _build_api_messages_for(raw: Array) -> Array:
	var result: Array = []
	for m in raw:
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


func _toggle_reader() -> void:
	var main_content := $VBox
	if main_content == null or batch_reader == null:
		return
	var showing_reader: bool = batch_reader.visible
	batch_reader.visible = not showing_reader
	main_content.visible = showing_reader
	reader_btn.text = "🔬 实验台" if batch_reader.visible else "📖 浏览报告"
	if batch_reader.visible:
		batch_reader.set_experiments_dir(_config.experiments_path)
		batch_reader._refresh_batch_list()


func _scroll_to_bottom() -> void:
	msg_scroll.scroll_vertical = int(msg_scroll.get_v_scroll_bar().max_value)


func _set_status(text: String) -> void:
	status_label.text = text


func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label
