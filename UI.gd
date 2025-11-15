extends Panel

@onready var progress_timer = get_tree().root.get_child(0).get_node("ProgressTimer")
@onready var http_request = get_tree().root.get_child(0).get_node("HTTPRequest")
@onready var status_bar = get_tree().root.get_child(0).get_node("UI/StatusBarPanel/Hotbar/StatusBar")

@export var current_download_name = "N/A"

var is_downloading = false
var last_downloaded_bytes = 0
var loop_arounds = 0

func _on_close_button_pressed():
	$ScrollContainer.visible = true
	$StatusBarPanel.visible = true
	$Settings.visible = false

func _on_settings_button_pressed():
	$ScrollContainer.visible = false
	$StatusBarPanel.visible = false
	$Settings.visible = true

func start_download(download_name):
	is_downloading = true
	current_download_name = download_name
	progress_timer.start()

func _on_progress_timer_timeout():
	if not is_downloading:
		return
	var downloaded_bytes = http_request.get_downloaded_bytes() # Counts up 2GB at a time, then flips around to negative 2GB.
	var two_gb = 1024 * 1024 * 1024 * 2
	if downloaded_bytes < 0: # Count how many negatives it's reached
		if last_downloaded_bytes >= 0:
			loop_arounds += 1
		downloaded_bytes += two_gb * loop_arounds
		print("Download looped around " + str(loop_arounds) + " times.")
		
	var downloaded_megabytes = downloaded_bytes / 1024 / 1024
	if downloaded_megabytes > 1024:
		var downloaded_gigabytes = downloaded_megabytes / 1024
		status_bar.text = "Downloading " + current_download_name + " (" + str(downloaded_gigabytes) + " GB)"
	elif downloaded_megabytes > 0:
		status_bar.text = "Downloading " + current_download_name + " (" + str(downloaded_megabytes) + " MB)"
	else:
		status_bar.text = "Downloading " + current_download_name + " (" + str(downloaded_bytes / 1024) + " KB)"
	last_downloaded_bytes = downloaded_bytes
