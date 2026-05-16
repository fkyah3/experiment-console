class_name BatchDialog
extends AcceptDialog

signal batch_requested(count: int, batch_name: String, rule_engine: bool, quality_assess: bool, assess_samples: int)


func _init() -> void:
	title = "批量运行"
	min_size = Vector2(400, 240)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)

	vbox.add_child(_make_label("运行次数"))
	var count_input := SpinBox.new()
	count_input.min_value = 1
	count_input.max_value = 10000
	count_input.value = 20
	count_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(count_input)

	vbox.add_child(_make_label("批次名称（可选）"))
	var batch_name_input := LineEdit.new()
	batch_name_input.placeholder_text = "会追加到目录名上"
	batch_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(batch_name_input)

	var rule_cb := CheckBox.new()
	rule_cb.text = "规则引擎（不花钱，预筛可疑样本）"
	rule_cb.button_pressed = true
	vbox.add_child(rule_cb)

	var assess_cb := CheckBox.new()
	assess_cb.text = "LLM 质量评估（花少量 token）"
	assess_cb.button_pressed = false
	vbox.add_child(assess_cb)

	var hrow := HBoxContainer.new()
	hrow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hrow.add_child(_make_label("  采样量："))
	var assess_spin := SpinBox.new()
	assess_spin.min_value = 1
	assess_spin.max_value = 100
	assess_spin.value = 5
	assess_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hrow.add_child(assess_spin)
	var assess_label := Label.new()
	assess_label.text = "条（随机）"
	hrow.add_child(assess_label)
	vbox.add_child(hrow)

	var start_btn := Button.new()
	start_btn.text = "▶ 开始"
	start_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start_btn.pressed.connect(func():
		var count := int(count_input.value)
		var bname := batch_name_input.text.strip_edges()
		batch_requested.emit(count, bname, rule_cb.button_pressed, assess_cb.button_pressed, int(assess_spin.value))
		hide()
		queue_free()
	)
	vbox.add_child(start_btn)

	add_child(vbox)
	call_deferred("popup_centered")


func _make_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	return lbl
