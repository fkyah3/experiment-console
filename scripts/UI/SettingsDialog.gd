class_name SettingsDialog
extends AcceptDialog

var config_manager: ConfigManager
var provider: String


func _init(cfg: ConfigManager, prov: String) -> void:
	config_manager = cfg
	provider = prov
	title = "设置"
	min_size = Vector2(500, 520)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)

	var deepseek_label := Label.new()
	deepseek_label.text = "DeepSeek API Key"
	vbox.add_child(deepseek_label)
	var deepseek_input := LineEdit.new()
	deepseek_input.text = config_manager.deepseek_key
	deepseek_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deepseek_input.secret = true
	vbox.add_child(deepseek_input)

	var opencode_label := Label.new()
	opencode_label.text = "OpenCode Go API Key"
	vbox.add_child(opencode_label)
	var opencode_input := LineEdit.new()
	opencode_input.text = config_manager.opencode_key
	opencode_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opencode_input.secret = true
	vbox.add_child(opencode_input)

	var exp_label := Label.new()
	exp_label.text = "实验存储路径"
	vbox.add_child(exp_label)
	var exp_row := HBoxContainer.new()
	exp_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var exp_input := LineEdit.new()
	exp_input.text = config_manager.experiments_path
	exp_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	exp_row.add_child(exp_input)
	var exp_open := Button.new()
	exp_open.text = "打开文件夹"
	exp_open.pressed.connect(func(): config_manager.open_in_explorer(config_manager.experiments_path))
	exp_row.add_child(exp_open)
	vbox.add_child(exp_row)

	var tpl_label := Label.new()
	tpl_label.text = "模板存储路径"
	vbox.add_child(tpl_label)
	var tpl_row := HBoxContainer.new()
	tpl_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tpl_input := LineEdit.new()
	tpl_input.text = config_manager.templates_path
	tpl_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tpl_row.add_child(tpl_input)
	var tpl_open := Button.new()
	tpl_open.text = "打开文件夹"
	tpl_open.pressed.connect(func(): config_manager.open_in_explorer(config_manager.templates_path))
	tpl_row.add_child(tpl_open)
	vbox.add_child(tpl_row)

	var ws_label := Label.new()
	ws_label.text = "工作区路径（tool calling 的 read 工具根目录）"
	vbox.add_child(ws_label)
	var ws_input := LineEdit.new()
	ws_input.text = config_manager.workspace_path
	ws_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(ws_input)

	var bc_label := Label.new()
	bc_label.text = "批量运行并发数（设为 1 = 串行，逐轮运行）"
	vbox.add_child(bc_label)
	var bc_input := SpinBox.new()
	bc_input.min_value = 1
	bc_input.max_value = 10
	bc_input.value = config_manager.batch_concurrency
	bc_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(bc_input)

	var save_btn := Button.new()
	save_btn.text = "保存"
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_btn.pressed.connect(func():
		config_manager.deepseek_key = deepseek_input.text
		config_manager.opencode_key = opencode_input.text
		config_manager.experiments_path = exp_input.text
		config_manager.templates_path = tpl_input.text
		config_manager.workspace_path = ws_input.text
		config_manager.batch_concurrency = int(bc_input.value)
		config_manager.save_config()
		confirmed.emit()
		hide()
		queue_free()
	)
	vbox.add_child(save_btn)

	add_child(vbox)
	confirmed.connect(queue_free)
	call_deferred("popup_centered")
