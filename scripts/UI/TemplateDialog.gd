class_name TemplateDialog
extends RefCounted


static func show_delete(parent_node: Node, store: ExperimentStore, on_done: Callable) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "删除模板"
	dialog.min_size = Vector2(350, 200)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var templates := store.list_templates()
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
				store.delete_template(n)
				dialog.queue_free()
				on_done.call()
			)
			row.add_child(del_btn)
			vbox.add_child(row)

	scroll.add_child(vbox)
	dialog.add_child(scroll)
	parent_node.add_child(dialog)
	dialog.popup_centered()
	await dialog.tree_exited


static func show_save(parent_node: Node, store: ExperimentStore, model: String, thinking: String, effort: String, max_tokens: int, messages: Array, on_done: Callable) -> void:
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
		store.save_template(tname, model, thinking, effort, max_tokens, messages)
		dialog.queue_free()
		on_done.call()
	)
	vbox.add_child(done_btn)
	dialog.add_child(vbox)
	parent_node.add_child(dialog)
	dialog.popup_centered()
	await dialog.tree_exited


static func _make_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	return lbl
