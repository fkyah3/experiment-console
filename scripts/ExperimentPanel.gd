extends Control
class_name ExperimentPanel

signal experiment_saved(path: String)

const _ToolExecutor = preload("res://scripts/Core/ToolExecutor.gd")
const _BrickWidget = preload("res://scripts/UI/BrickWidget.gd")
const _BlockEditor = preload("res://scripts/UI/BlockEditor.gd")
const _SettingsDialog = preload("res://scripts/UI/SettingsDialog.gd")
const _BatchDialog = preload("res://scripts/UI/BatchDialog.gd")
const _TemplateDialog = preload("res://scripts/UI/TemplateDialog.gd")

const _APIBuilder = preload("res://scripts/APIBuilder.gd")
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
var _tc_max_rounds: int = 50
var _tool_executor

var _model: String = "deepseek-v4-flash"
var _thinking: String = "思考模式"
var _effort: String = "high"
var _max_tokens: int = 4096
var _temperature: float = 0.0
var _top_p: float = 1.0
var _frequency_penalty: float = 0.0
var _explore_separate: bool = false
var _bare_mode: bool = false
var _provider: String = "deepseek"
var _provider_host: String = "api.deepseek.com"
var _provider_path: String = "/chat/completions"

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
	_provider_host = _config.api_host
	_provider_path = _config.api_path
	_provider = "opencode_go" if _config.api_host.find("opencode") != -1 else "deepseek"
	api_key = _config.opencode_key if _provider == "opencode_go" else _config.deepseek_key
	_store = ExperimentStore.new(_config.experiments_path, _config.templates_path)
	_model_data = ExperimentModelScript.new()
	_batch_runner = BatchRunnerScript.new()
	_batch_runner.setup(self, api_key)
	_batch_runner.progress_updated.connect(_on_batch_progress)
	_batch_runner.all_done.connect(_on_batch_finished)
	_model_data.messages_changed.connect(_rebuild_list)
	_tool_executor = _ToolExecutor.new()
	_tool_executor.workspace_path = _config.workspace_path
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

	var bare_cb := CheckBox.new()
	bare_cb.text = "裸模式"
	bare_cb.tooltip_text = "不传工具定义，纯 LLM 回复"
	bare_cb.button_pressed = _bare_mode
	bare_cb.toggled.connect(func(on: bool): _bare_mode = on)
	hbox.add_child(bare_cb)

	var load_btn := Button.new()
	load_btn.text = "📄 加载文件"
	load_btn.tooltip_text = "将文件内容作为 user 消息插入积木列表"
	load_btn.pressed.connect(_on_load_file)
	if hbox:
		hbox.add_child(load_btn)

	var prov_label := Label.new()
	prov_label.text = "Provider"
	hbox.add_child(prov_label)
	var prov_select := OptionButton.new()
	prov_select.add_item("DeepSeek")
	prov_select.add_item("OpenCode Go")
	_provider = "opencode_go" if _config.api_host.find("opencode") != -1 else "deepseek"
	prov_select.selected = 1 if _config.api_host.find("opencode") != -1 else 0
	prov_select.item_selected.connect(func(idx: int):
		if idx == 0:
			_provider = "deepseek"
			_provider_host = "api.deepseek.com"
			_provider_path = "/chat/completions"
			api_key = _config.deepseek_key
		else:
			_provider = "opencode_go"
			_provider_host = "opencode.ai"
			_provider_path = "/zen/go/v1/chat/completions"
			api_key = _config.opencode_key
		_config.api_host = _provider_host
		_config.api_path = _provider_path
		_config.batch_host = _provider_host
		_config.batch_path = _provider_path
		_config.save_config()
		_batch_runner.setup(self, api_key)
	)
	hbox.add_child(prov_select)

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
	settings_btn.pressed.connect(_on_open_settings)
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
		_TemplateDialog.show_save(self, _store, _model, _thinking, _effort, _max_tokens, _model_data.messages, func():
			_populate_template_menu()
			_set_status("已保存模板")
		)
		return
	if item_text.begins_with("🗑"):
		_TemplateDialog.show_delete(self, _store, func():
			_populate_template_menu()
			_populate_template_menu()
			_set_status("已删除模板")
		)
		return
	var t := _store.load_template(item_text)
	if t.is_empty():
		return
	_model_data.insert_template(t.get("messages", []))
	_set_status("已插入模板: " + item_text)


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
		var w = _BrickWidget.new()
		w.edit_requested.connect(_edit_block)
		w.move_requested.connect(func(idx: int, dir: int): _model_data.move(idx, dir))
		w.delete_requested.connect(func(idx: int): _model_data.remove_at(idx))
		var root = w.build(i, _model_data.messages[i])
		_message_widgets.append(w)
		msg_list.add_child(root)
	msg_count.text = str(_model_data.messages.size()) + " 条"


func _edit_block(idx: int) -> void:
	if idx < 0 or idx >= _model_data.messages.size():
		return
	var data: Dictionary = _model_data.messages[idx]
	var editor = _BlockEditor.new(data, idx)
	editor.saved.connect(_rebuild_list)
	add_child(editor)


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
	if not _bare_mode and _tc_round < _tc_max_rounds:
		tools = _APIBuilder.build_tools()

	var msgs_to_send := _APIBuilder.build_api_messages(_model_data.messages)

	if _thinking == "思考模式":
		for msg in msgs_to_send:
			if msg.get("role") == "assistant" and not msg.has("reasoning_content"):
				msg["reasoning_content"] = "(reasoning omitted)"

	var body_dict := _APIBuilder.build_body_dict(_model, _thinking, _effort, _max_tokens, _temperature, msgs_to_send, _top_p, _frequency_penalty, true, tools, _provider)
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
	_deepseek.api_host = _provider_host
	_deepseek.api_path = _provider_path
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

	var api_msgs := _APIBuilder.build_api_messages(_sub_agent_messages)
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
	var body_dict := _APIBuilder.build_body_dict(_model, "无思考模式", "high", _max_tokens, _temperature, api_msgs, _top_p, _frequency_penalty, true, tools, _provider)
	var body_str := JSON.stringify(body_dict, "\t")
	log_request.text = body_str
	_set_status("子 agent 探索中... (第 %d 轮)" % _sub_agent_round)

	_deepseek = DeepSeekStreamClient.new()
	add_child(_deepseek)
	_deepseek.api_key = api_key
	_deepseek.api_host = _provider_host
	_deepseek.api_path = _provider_path
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
			content = _tool_executor.list_dir(dir_path)

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

	var file_paths = _tool_executor.scan_key_files(20)
	var file_contents := ""
	var count := 0
	for fpath in file_paths:
		if count >= 5:
			break
		var raw: String = _tool_executor.read_file(fpath)
		var truncated := raw
		if raw.length() > 10000:
			truncated = raw.left(10000) + "\n...（共 %d 字，已截断）" % raw.length()
		file_contents += "\n--- 文件: %s ---\n%s" % [fpath, truncated]
		count += 1

	var original: String = ""
	if _model_data.messages.size() >= 2:
		original = str(_model_data.messages[1].get("content", ""))
	var combined_user := "以下是工程层根据目录结构读取的关键文件内容：\n%s\n\n请基于以上文件内容，%s" % [file_contents, original]
	_model_data.append({"role": "user", "content": combined_user})

	_accumulated_content = ""
	_accumulated_reasoning = ""
	_rebuild_list()
	call_deferred("_deferred_main_agent_send")


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
	if msg_idx < _message_widgets.size():
		_message_widgets[msg_idx].update_preview()
	_set_status("生成中... (" + str(_accumulated_content.length()) + " 字)")


func _on_reasoning_chunk(text: String, msg_idx: int) -> void:
	if msg_idx < 0 or msg_idx >= _model_data.messages.size():
		return
	_accumulated_reasoning += text
	_model_data.messages[msg_idx]["reasoning"] = _accumulated_reasoning
	if msg_idx < _message_widgets.size():
		_message_widgets[msg_idx].update_preview()
	_set_status("思考中... (" + str(_accumulated_reasoning.length()) + " 字)")


func _on_stream_finished(_body_str: String) -> void:
	_set_status("流式接收完成")
	send_btn.disabled = false

	if not _model_data.messages.is_empty():
		var last: int = _model_data.messages.size() - 1
		_model_data.messages[last]["content"] = _accumulated_content
		_model_data.messages[last]["reasoning"] = _accumulated_reasoning
		_rebuild_list()

	_last_response_body = _APIBuilder.build_response_body(_accumulated_content, _accumulated_reasoning)
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
				content = _tool_executor.list_dir(dir_path)
				_set_status("工具调用: list_dir(%s) → %d chars" % [dir_path, content.length()])
			elif func_name == "read":
				var args = JSON.parse_string(args_str) as Dictionary
				var file_path: String = ""
				if args != null:
					file_path = args.get("filePath", "")
				content = _tool_executor.read_file(file_path)
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
				_tool_executor.write_file(write_path, write_content)
				content = "[已写入: %s] 文件内容已更新。" % write_path
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

	var msgs_to_send := _APIBuilder.build_api_messages(_model_data.messages)
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


func _on_open_settings() -> void:
	var dlg = _SettingsDialog.new(_config, _provider)
	dlg.confirmed.connect(func():
		api_key = _config.deepseek_key if _provider == "deepseek" else _config.opencode_key
		_batch_runner.setup(self, api_key)
		_store = ExperimentStore.new(_config.experiments_path, _config.templates_path)
		_tool_executor.workspace_path = _config.workspace_path
		_populate_template_menu()
		_set_status("已保存设置")
	)
	add_child(dlg)


func _on_batch_run() -> void:
	var dlg = _BatchDialog.new()
	dlg.batch_requested.connect(_start_batch)
	add_child(dlg)


func _start_batch(count: int, batch_name: String, rule_engine: bool, quality_assess: bool, assess_samples: int) -> void:
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
		_config.batch_concurrency, _explore_separate,
		_bare_mode, _config.batch_host, _config.batch_path,
		rule_engine, quality_assess, assess_samples,
		_provider
	)


func _on_batch_progress(done: int, failed: int, total: int, running: int) -> void:
	_set_status("批量: %d/%d 完成（%d 失败, %d 运行中）" % [done, total, failed, running])


func _on_batch_finished(success: int, failed: int) -> void:
	_set_status("批量完成: %d 成功, %d 失败" % [success, failed])


func _toggle_reader() -> void:
	var showing_reader: bool = batch_reader.visible
	batch_reader.visible = not showing_reader
	reader_btn.text = "🔬 实验台" if batch_reader.visible else "📖 浏览报告"
	if batch_reader.visible:
		batch_reader.set_experiments_dir(_config.experiments_path)
		batch_reader._refresh_batch_list()


func _list_dir(dir_path: String) -> String:
	return _tool_executor.list_dir(dir_path)


func _read_tool_file(file_path: String) -> String:
	return _tool_executor.read_file(file_path)


func _write_tool_file(file_path: String, content: String) -> void:
	_tool_executor.write_file(file_path, content)


func _scan_key_files(_base_dir: String, max_return: int) -> Array[String]:
	return _tool_executor.scan_key_files(max_return)


func _make_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	return lbl


func _set_status(text: String) -> void:
	status_label.text = text
