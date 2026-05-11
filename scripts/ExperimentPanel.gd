extends Control
class_name ExperimentPanel

signal experiment_saved(path: String)

const APIBuilder = preload("res://scripts/APIBuilder.gd")
const ExperimentModelScript = preload("res://scripts/ExperimentModel.gd")
const BatchRunnerScript = preload("res://scripts/BatchRunner.gd")

var api_key: String = ""

var _config: ConfigManager
var _store: ExperimentStore
var _model_data
var _batch_runner
var _deepseek: DeepSeekStreamClient
var _message_widgets: Array = []
var _accumulated_content: String = ""
var _accumulated_reasoning: String = ""
var _last_response_body: String = ""
var _last_usage: Dictionary = {}
var _tc_round: int = 0
var _start_ms: int = 0
## 工具调用最大轮数
## 范围 0-50，0 表示不调工具
## 默认 50（测试阶段开大一点）
@export var _tc_max_rounds: int = 50

var _model: String = "deepseek-v4-flash"
var _thinking: String = "思考模式"
var _effort: String = "high"
var _max_tokens: int = 4096
var _temperature: float = 0.0
var _top_p: float = 1.0
var _frequency_penalty: float = 0.0
var _explore_separate: bool = false

var _sub_agent_messages: Array = []
var _sub_agent_round: int = 0
var _sub_agent_max_rounds: int = 30

@onready var params_model: OptionButton = %ParamsModel
@onready var params_thinking: OptionButton = %ParamsThinking
@onready var params_effort: OptionButton = %ParamsEffort
@onready var params_max_tokens: SpinBox = %ParamsMaxTokens
@onready var params_temperature: SpinBox = %ParamsTemperature
@onready var params_top_p: SpinBox = %ParamsTopP
@onready var params_freq_penalty: SpinBox = %ParamsFreqPenalty
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
	_model_data = ExperimentModelScript.new()
	_batch_runner = BatchRunnerScript.new()
	_batch_runner.setup(self, api_key)
	_batch_runner.progress_updated.connect(_on_batch_progress)
	_batch_runner.all_done.connect(_on_batch_finished)
	_model_data.messages_changed.connect(_rebuild_list)
	_build_dynamic()


func _build_dynamic() -> void:
	_build_settings_menu()
	params_model.add_item("deepseek-v4-flash")
	params_model.add_item("deepseek-v4-pro")
	params_model.select(0)
	params_model.item_selected.connect(func(idx: int): _model = params_model.get_item_text(idx))

	params_thinking.add_item("思考模式")
	params_thinking.add_item("无思考模式")
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

	params_top_p.min_value = 0.0
	params_top_p.max_value = 1.0
	params_top_p.step = 0.05
	params_top_p.value = _top_p
	params_top_p.value_changed.connect(func(v: float): _top_p = v)

	params_freq_penalty.min_value = -2.0
	params_freq_penalty.max_value = 2.0
	params_freq_penalty.step = 0.1
	params_freq_penalty.value = _frequency_penalty
	params_freq_penalty.value_changed.connect(func(v: float): _frequency_penalty = v)

	var explore_cb := CheckBox.new()
	explore_cb.text = "探索分离"
	explore_cb.tooltip_text = "子 agent（non-thinking）探索目录→产出中文摘要→主 agent（thinking）单轮分析"
	explore_cb.button_pressed = _explore_separate
	explore_cb.toggled.connect(func(on: bool): _explore_separate = on)
	var hbox := get_node_or_null("VBox/ParamsPanel/ParamsHBox")
	if hbox:
		hbox.add_child(explore_cb)

	var load_btn := Button.new()
	load_btn.text = "📄 加载文件"
	load_btn.tooltip_text = "将文件内容作为 user 消息插入积木列表（不经过 UI 编辑框，支持大文件）"
	load_btn.pressed.connect(_on_load_file)
	if hbox:
		hbox.add_child(load_btn)

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
	var labels := ["模型", "参数模式", "推理强度", "max_tokens", "温度", "top_p", "freq_penalty", "实验标题"]
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
	_model_data.insert_template(t.get("messages", []))
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
		_store.save_template(tname, _model, _thinking, _effort, _max_tokens, _model_data.messages)
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


func _on_add_block(id: int) -> void:
	match id:
		0: _model_data.add("system")
		1: _model_data.add("user")
		2: _model_data.add("assistant", "content")
		3: _model_data.add("assistant", "reasoning")
		4: _model_data.add("assistant")
		5: _model_data.add("tool")


func _on_load_file() -> void:
	var dialog := FileDialog.new()
	dialog.title = "选择文件加载到消息"
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.add_filter("*.md,*.txt,*.json,*.ts,*.js,*.py,*.gd", "代码/文本文件")
	dialog.add_filter("*", "全部文件")
	dialog.file_selected.connect(func(path: String):
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			_set_status("无法读取文件: " + path)
			return
		var content := file.get_as_text()
		_model_data.append({"role": "user", "content": content})
		_set_status("已加载: %s (%d 字符)" % [path.get_file(), content.length()])
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()


func _rebuild_list() -> void:
	for child in msg_list.get_children():
		msg_list.remove_child(child)
		child.queue_free()
	_message_widgets.clear()

	for i in _model_data.messages.size():
		var w := _build_block_widget(i, _model_data.messages[i])
		_message_widgets.append(w)
		msg_list.add_child(w.container)
	msg_count.text = str(_model_data.messages.size()) + " 条"


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

	edit_btn.pressed.connect(func(): _edit_block(idx))
	up_btn.pressed.connect(func(): _model_data.move(idx, -1))
	down_btn.pressed.connect(func(): _model_data.move(idx, 1))
	del_btn.pressed.connect(func(): _model_data.remove_at(idx))

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
	if idx < 0 or idx >= _model_data.messages.size():
		return
	var data: Dictionary = _model_data.messages[idx]
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


func _on_clear() -> void:
	_model_data.clear()
	log_request.text = ""
	log_response.text = ""
	log_usage.text = ""
	_last_response_body = ""
	_last_usage = {}
	_set_status("已清空")


func _on_send() -> void:
	if _model_data.messages.is_empty():
		_set_status("消息列表为空，无法发送")
		return

	_set_status("发送中...")
	send_btn.disabled = true
	_tc_round = 0
	_start_ms = Time.get_ticks_msec()
	_accumulated_content = ""
	_accumulated_reasoning = ""

	if _explore_separate:
		_start_sub_agent()
	else:
		_do_send()


func _do_send() -> void:
	var tools: Array = []
	if _tc_round < _tc_max_rounds:
		tools = APIBuilder.build_tools()

	var msgs_to_send := APIBuilder.build_api_messages(_model_data.messages)

	if _thinking == "思考模式":
		for msg in msgs_to_send:
			if msg.get("role") == "assistant" and not msg.has("reasoning_content"):
				msg["reasoning_content"] = "(reasoning omitted)"

	var body_dict := APIBuilder.build_body_dict(_model, _thinking, _effort, _max_tokens, _temperature, msgs_to_send, _top_p, _frequency_penalty, true, tools)
	var body_str := JSON.stringify(body_dict, "\t")
	log_request.text = body_str

	_accumulated_content = ""
	_accumulated_reasoning = ""

	var idx: int = _model_data.messages.size()
	_model_data.add("assistant")
	_set_status("等待回复...")

	_deepseek = DeepSeekStreamClient.new()
	add_child(_deepseek)
	_deepseek.api_key = api_key
	_deepseek.content_chunk.connect(_on_content_chunk.bind(idx))
	_deepseek.reasoning_chunk.connect(_on_reasoning_chunk.bind(idx))
	_deepseek.stream_finished.connect(_on_stream_finished.bind(body_str))
	_deepseek.tool_calls_done.connect(_on_tool_calls_done)
	_deepseek.usage_received.connect(_on_usage_received)
	_deepseek.connection_error.connect(_on_connection_error)
	_deepseek.start_streaming(body_str)


func _start_sub_agent() -> void:
	_set_status("子 agent 探索中...")
	_sub_agent_messages = [
		{"role": "system", "content": "你是一个目录探索助手。只用 list_dir 探索目录结构，输出完整目录树。不需要 read 文件内容。"},
		{"role": "user", "content": "探索当前工作区目录结构，列出所有目录和文件。"}
	]
	_sub_agent_round = 0
	_sub_agent_send()


func _sub_agent_send() -> void:
	_sub_agent_round += 1
	if _sub_agent_round > _sub_agent_max_rounds:
		_set_status("子 agent 超时")
		send_btn.disabled = false
		return

	var api_msgs := APIBuilder.build_api_messages(_sub_agent_messages)
	var tools: Array = [{
		"type": "function",
		"function": {
			"name": "list_dir",
			"description": "列出工作区目录中的文件和子目录。用于探索项目结构。",
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
	}]
	var body_dict := APIBuilder.build_body_dict(_model, "无思考模式", "high", _max_tokens, _temperature, api_msgs, _top_p, _frequency_penalty, true, tools)
	var body_str := JSON.stringify(body_dict, "\t")
	log_request.text = body_str
	_set_status("子 agent 探索中... (第 %d 轮)" % _sub_agent_round)

	_deepseek = DeepSeekStreamClient.new()
	add_child(_deepseek)
	_deepseek.api_key = api_key
	_deepseek.content_chunk.connect(_on_sub_agent_chunk)
	_deepseek.stream_finished.connect(_on_sub_agent_done)
	_deepseek.tool_calls_done.connect(_on_sub_agent_tc)
	_deepseek.connection_error.connect(_on_sub_agent_error)
	_deepseek.start_streaming(body_str)


func _on_sub_agent_chunk(text: String) -> void:
	_accumulated_content += text
	log_response.text = "[子 agent 流式输出]\n" + _accumulated_content
	log_response.scroll_vertical = log_response.get_line_count()
	_set_status("子 agent 探索中... (已收到 %d 字符)" % _accumulated_content.length())


func _on_sub_agent_tc(tool_calls: Array) -> void:
	if _deepseek:
		_deepseek.queue_free()
		_deepseek = null

	var actions: String = ""
	for tc in tool_calls:
		var fn: String = str(tc.get("name", ""))
		var args: String = str(tc.get("arguments", ""))
		actions += "  → %s(%s)\n" % [fn, args.left(60)]
	log_response.text += "\n[子 agent 工具调用]\n" + actions
	log_response.scroll_vertical = log_response.get_line_count()
	_set_status("子 agent 工具调用中...")

	var tc_for_api: Array = []
	for tc in tool_calls:
		tc_for_api.append({
			"id": tc.get("id", ""),
			"type": "function",
			"function": {
				"name": tc.get("name", ""),
				"arguments": tc.get("arguments", "")
			}
		})

	_sub_agent_messages.append({"role": "assistant", "content": null, "tool_calls": tc_for_api})

	for tc in tool_calls:
		var func_name: String = tc.get("name", "")
		var args_str: String = tc.get("arguments", "{}")
		var call_id: String = tc.get("id", "")

		var content := "[工具结果为空]"
		if func_name == "list_dir":
			var args = JSON.parse_string(args_str) as Dictionary
			var dir_path: String = "."
			if args != null:
				dir_path = args.get("dirPath", ".")
			content = _list_dir(dir_path)

		_sub_agent_messages.append({
			"role": "tool",
			"tool_call_id": call_id,
			"name": func_name,
			"content": content
		})

	_sub_agent_send()


func _on_sub_agent_done() -> void:
	if _deepseek:
		_deepseek.queue_free()
		_deepseek = null

	_set_status("子 agent 完成，工程层读文件中...")

	# 工程层直接扫描工作区目录
	var file_paths := _scan_key_files(_config.workspace_path, 20)
	var file_contents := ""
	var count := 0
	for fpath in file_paths:
		if count >= 5:
			break
		var raw := _read_tool_file(fpath)
		var truncated := raw
		if raw.length() > 10000:
			truncated = raw.left(10000) + "\n...（共 %d 字，已截断）" % raw.length()
		file_contents += "\n--- 文件: %s ---\n%s" % [fpath, truncated]
		count += 1

	# 假 user 消息：原始任务 + 文件内容合并为一条
	var original: String = ""
	if _model_data.messages.size() >= 2:
		original = str(_model_data.messages[1].get("content", ""))
	var combined_user := "以下是工程层根据目录结构读取的关键文件内容：\n%s\n\n请基于以上文件内容，%s" % [file_contents, original]
	_model_data.append({"role": "user", "content": combined_user})

	_accumulated_content = ""
	_accumulated_reasoning = ""
	_rebuild_list()
	call_deferred("_deferred_main_agent_send")


func _scan_key_files(base_dir: String, max_return: int) -> Array[String]:
	var result: Array[String] = []
	var priority: Array[String] = []
	var rest: Array[String] = []
	_scan_dir(base_dir, "", priority, rest)
	priority.sort()
	rest.sort()
	for p in priority:
		if result.size() >= max_return:
			break
		result.append(p)
	for r in rest:
		if result.size() >= max_return:
			break
		result.append(r)
	return result


func _scan_dir(base: String, rel: String, priority: Array[String], rest: Array[String]) -> void:
	var dir := DirAccess.open(base.path_join(rel))
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while not fname.is_empty():
		if fname.begins_with("."):
			fname = dir.get_next()
			continue
		var full_rel := rel.path_join(fname) if not rel.is_empty() else fname
		if dir.current_is_dir():
			if fname == "node_modules":
				fname = dir.get_next()
				continue
			_scan_dir(base, full_rel, priority, rest)
		else:
			if fname.ends_with(".ts") or fname.ends_with(".tsx") or fname.ends_with(".js") or fname.ends_with(".json") or fname.ends_with(".md"):
				if fname.contains("snapshot"):
					rest.append(full_rel)
				elif fname.contains("provider") or fname.contains("index") or fname.contains("main") or fname.contains("core") or fname.contains("schema") or fname.contains("auth"):
					priority.append(full_rel)
				else:
					rest.append(full_rel)
		fname = dir.get_next()
	dir.list_dir_end()


func _on_sub_agent_error(msg: String) -> void:
	push_error("子 agent 错误: %s" % msg)
	if _deepseek:
		_deepseek.queue_free()
		_deepseek = null
	_set_status("子 agent 错误: %s" % msg)
	send_btn.disabled = false


func _deferred_main_agent_send() -> void:
	_tc_round = _tc_max_rounds
	_do_send()


func _on_content_chunk(text: String, msg_idx: int) -> void:
	if msg_idx < 0 or msg_idx >= _model_data.messages.size():
		return
	_accumulated_content += text
	_model_data.messages[msg_idx]["content"] = _accumulated_content
	_update_block_preview(msg_idx)
	_set_status("生成中... (" + str(_accumulated_content.length()) + " 字)")


func _on_reasoning_chunk(text: String, msg_idx: int) -> void:
	if msg_idx < 0 or msg_idx >= _model_data.messages.size():
		return
	_accumulated_reasoning += text
	_model_data.messages[msg_idx]["reasoning"] = _accumulated_reasoning
	_update_block_preview(msg_idx)
	_set_status("思考中... (" + str(_accumulated_reasoning.length()) + " 字)")


func _on_stream_finished(_body_str: String) -> void:
	_set_status("流式接收完成")
	send_btn.disabled = false

	if not _model_data.messages.is_empty():
		var last: int = _model_data.messages.size() - 1
		_model_data.messages[last]["content"] = _accumulated_content
		_model_data.messages[last]["reasoning"] = _accumulated_reasoning
		_rebuild_list()

	_last_response_body = APIBuilder.build_response_body(_accumulated_content, _accumulated_reasoning)
	log_response.text = _last_response_body

	if _deepseek:
		_deepseek.queue_free()
		_deepseek = null


func _on_tool_calls_done(tool_calls: Array) -> void:
	if _deepseek:
		_deepseek.queue_free()
		_deepseek = null

	_tc_round += 1
	if _tc_round >= _tc_max_rounds:
		_set_status("工具调用已达上限 (%d)" % _tc_max_rounds)
		send_btn.disabled = false
		_rebuild_list()
		return

	if not _model_data.messages.is_empty():
		var last: int = _model_data.messages.size() - 1
		_model_data.messages[last]["content"] = _accumulated_content
		_model_data.messages[last]["reasoning"] = _accumulated_reasoning

		var tc_for_api: Array = []
		for tc in tool_calls:
			tc_for_api.append({
				"id": tc.get("id", ""),
				"type": "function",
				"function": {
					"name": tc.get("name", ""),
					"arguments": tc.get("arguments", "")
				}
			})
		_model_data.messages[last]["tool_calls"] = tc_for_api

		for tc in tool_calls:
			var func_name: String = tc.get("name", "")
			var args_str: String = tc.get("arguments", "{}")
			var call_id: String = tc.get("id", "")

			var content := "[工具结果为空]"
			if func_name == "list_dir":
				var args = JSON.parse_string(args_str) as Dictionary
				var dir_path: String = "."
				if args != null:
					dir_path = args.get("dirPath", ".")
				content = _list_dir(dir_path)
				_set_status("工具调用: list_dir(%s) → %d chars" % [dir_path, content.length()])
			elif func_name == "read":
				var args = JSON.parse_string(args_str) as Dictionary
				var file_path: String = ""
				if args != null:
					file_path = args.get("filePath", "")
				content = _read_tool_file(file_path)
				_set_status("工具调用: read(%s) → %d chars" % [file_path, content.length()])
			elif func_name == "write":
				var args_raw = args_str
				if typeof(args_raw) != TYPE_STRING:
					args_raw = JSON.stringify(args_raw)
				var args = JSON.parse_string(args_raw) as Dictionary
				var write_path: String = ""
				var write_content: String = ""
				if args != null:
					write_path = args.get("filePath", "")
					write_content = args.get("content", "")
				_write_tool_file(write_path, write_content)
				content = "[已写入: %s] 文件内容已更新，将英文注释翻译为中文。" % write_path
				_set_status("工具调用: write(%s)" % write_path)

			_model_data.append({
			"role": "tool",
			"tool_call_id": call_id,
			"name": func_name,
			"content": content
		})

	_rebuild_list()
	_accumulated_content = ""
	_accumulated_reasoning = ""
	_do_send()


func _read_tool_file(filePath: String) -> String:
	var shadow := _shadow_path(filePath)
	if FileAccess.file_exists(shadow):
		return FileAccess.get_file_as_string(shadow)
	var base := _config.workspace_path
	if not base.ends_with("/"):
		base += "/"
	var fpath := filePath
	if not fpath.begins_with("E:/") and not fpath.begins_with("e:/") and not fpath.begins_with("C:/") and not fpath.begins_with("c:/"):
		fpath = base.path_join(filePath)
	if FileAccess.file_exists(fpath):
		return FileAccess.get_file_as_string(fpath)
	return "[文件不存在: %s]" % filePath


func _write_tool_file(filePath: String, content: String) -> void:
	var shadow := _shadow_path(filePath)
	var dir_path := shadow.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir_path)
	var file := FileAccess.open(shadow, FileAccess.WRITE)
	if file:
		file.store_string(content)
		file.close()


func _shadow_path(filePath: String) -> String:
	return ProjectSettings.globalize_path("user://opencode-shadow/").path_join(filePath)


func _list_dir(dirPath: String) -> String:
	var base := _config.workspace_path
	if not base.ends_with("/"):
		base += "/"
	var dpath := dirPath
	if not dpath.begins_with("E:/") and not dpath.begins_with("e:/") and not dpath.begins_with("C:/") and not dpath.begins_with("c:/"):
		dpath = base.path_join(dirPath)
	var dir := DirAccess.open(dpath)
	if dir == null:
		return "[目录不存在: %s]" % dirPath
	var result: String = ""
	dir.list_dir_begin()
	var fname := dir.get_next()
	while not fname.is_empty():
		if dir.current_is_dir():
			result += "[DIR]  %s/" % fname
		else:
			result += "[FILE] %s" % fname
		result += "\n"
		fname = dir.get_next()
	dir.list_dir_end()
	return result


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
	log_response.text = "[错误] " + msg
	res_tab.button_pressed = true
	send_btn.disabled = false
	_tc_round = _tc_max_rounds
	if _deepseek:
		_deepseek.queue_free()
		_deepseek = null


func _update_block_preview(idx: int) -> void:
	if idx < 0 or idx >= _message_widgets.size():
		return
	var data: Dictionary = _model_data.messages[idx]
	var preview: String = data.get("content", "")
	if data.has("reasoning") and not data.get("reasoning", "").is_empty():
		preview = "🧠[%d] %s" % [data["reasoning"].length(), data["reasoning"]]
	preview = preview.left(50).replace("\n", " ")
	_message_widgets[idx].preview_label.text = preview


func _on_save() -> void:
	var title := params_title.text.strip_edges()
	if title.is_empty() and _model_data.messages.size() > 0:
		title = _model_data.messages[0].get("content", "")
		title = title.left(20).replace("\n", " ")
	if title.is_empty():
		title = "untitled"

	var safe_title := ""
	var illegal := [":", "\\", "/", "*", "?", "\"", "<", ">", "|"]
	for c in title:
		var skip := false
		for il in illegal:
			if c == il:
				skip = true
				break
		if not skip:
			safe_title += c if c != " " else "_"
	safe_title = safe_title.strip_edges().left(60)
	if safe_title.is_empty():
		safe_title = "untitled"

	var exp_dir := _config.experiments_path.path_join(safe_title)
	DirAccess.make_dir_recursive_absolute(exp_dir)
	var round_num := 1
	var dir := DirAccess.open(exp_dir)
	if dir:
		dir.list_dir_begin()
		var entry := dir.get_next()
		while not entry.is_empty():
			if entry.begins_with("round-") and entry.ends_with(".md"):
				var num_str := entry.trim_prefix("round-").trim_suffix(".md")
				if num_str.is_valid_int():
					var n := num_str.to_int()
					if n >= round_num:
						round_num = n + 1
			entry = dir.get_next()
		dir.list_dir_end()

	var now := Time.get_datetime_dict_from_system()
	var ts := "%04d%02d%02d_%02d%02d%02d" % [now.year, now.month, now.day, now.hour, now.minute, now.second]
	var fname := "%s_round-%02d.md" % [ts, round_num]
	var fpath := exp_dir.path_join(fname)

	var msgs_to_send := APIBuilder.build_api_messages(_model_data.messages)
	var duration_ms := 0
	if _start_ms > 0:
		duration_ms = Time.get_ticks_msec() - _start_ms

	var ok := _store.save_experiment_file(
		fpath, safe_title, _model, _thinking, _effort, _max_tokens, _temperature,
		msgs_to_send, _model_data.messages,
		log_request.text, _last_response_body,
		_last_usage, notes_input.text, duration_ms
	)
	if not ok:
		_set_status("保存失败")
	else:
		_set_status("已保存: %s/%s" % [safe_title, fname])
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
	dialog.min_size = Vector2(500, 520)

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

	var ws_label := Label.new()
	ws_label.text = "工作区路径（tool calling 的 read 工具根目录）"
	vbox.add_child(ws_label)
	var ws_input := LineEdit.new()
	ws_input.text = _config.workspace_path
	ws_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(ws_input)

	var bc_label := Label.new()
	bc_label.text = "批量运行并发数（设为 1 = 串行，逐轮运行）"
	vbox.add_child(bc_label)
	var bc_input := SpinBox.new()
	bc_input.min_value = 1
	bc_input.max_value = 10
	bc_input.value = _config.batch_concurrency
	bc_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(bc_input)

	var save_btn_dialog := Button.new()
	save_btn_dialog.text = "保存"
	save_btn_dialog.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_btn_dialog.pressed.connect(func():
		_config.api_key = key_input.text
		_config.experiments_path = exp_input.text
		_config.templates_path = tpl_input.text
		_config.workspace_path = ws_input.text
		_config.batch_concurrency = int(bc_input.value)
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
	dialog.min_size = Vector2(400, 180)

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
	if _model_data.messages.is_empty():
		_set_status("消息列表为空，无法批量运行")
		return

	var actual_max_rounds := _tc_max_rounds
	if _config.batch_concurrency > 1 and _tc_max_rounds > 0:
		push_warning("并发 > 1 时禁用多轮工具调用，避免 worker 间状态冲突")
		actual_max_rounds = 0

	var mode := "串行" if _config.batch_concurrency <= 1 else "并行"
	_set_status("批量 %d 次开始，%s（并发%d）%s..." % [count, mode, _config.batch_concurrency, "，已禁用多轮" if _config.batch_concurrency > 1 and _tc_max_rounds > 0 else ""])
	_batch_runner.start(
		count, batch_name,
		_model_data.messages,
		_config.experiments_path,
		_config.templates_path,
		_model, _thinking, _effort, _max_tokens, _temperature,
		_top_p, _frequency_penalty,
		_config.workspace_path, actual_max_rounds,
		_config.batch_concurrency, _explore_separate
	)


func _on_batch_progress(done: int, failed: int, total: int, running: int) -> void:
	_set_status("批量 %d/%d | 运行中 %d | 失败 %d" % [done + failed, total, running, failed])


func _on_batch_finished(success: int, failed: int) -> void:
	_set_status("批量完成：成功 %d / %d，失败 %d" % [success, success + failed, failed])


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
