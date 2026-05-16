class_name BlockEditor
extends AcceptDialog

signal saved()


func _init(data: Dictionary, idx: int) -> void:
	title = "编辑积木 #" + str(idx)
	min_size = Vector2(500, 400)

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
		saved.emit()
		hide()
		queue_free()
	)
	vbox.add_child(done_btn)

	add_child(vbox)
	call_deferred("popup_centered")


func _make_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	return lbl
