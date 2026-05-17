extends Control


func show_popup(title, content, button_text):
	$Panel/Control/ScrollContainer/VBoxContainer/Title.text = title
	$Panel/Control/ScrollContainer/VBoxContainer/Content.text = content
	$Panel/Control/ScrollContainer/VBoxContainer/CloseButton.text = button_text
	show()

func _on_close_button_pressed() -> void:
	hide()
