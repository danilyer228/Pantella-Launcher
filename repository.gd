extends VBoxContainer
@onready var root = get_tree().root.get_child(0)
@onready var python = get_tree().root.get_child(0).get_node("PythonInterpreter")
@onready var http_request = get_tree().root.get_child(0).get_node("HTTPRequest")
@onready var progress_timer = get_tree().root.get_child(0).get_node("ProgressTimer")
@onready var status_bar = get_tree().root.get_child(0).get_node("UI/StatusBarPanel/Hotbar/StatusBar")
@onready var ui = get_tree().root.get_child(0).get_node("UI")
@onready var plugins_list = $RepoPanel/VBoxContainer/PluginsList
@onready var plugins_button = preload("res://plugin_button.tscn")

signal download_extracted
signal repo_download_finished

var DIR = OS.get_executable_path().get_base_dir() + "/"

var repo = {
	"args": [],
	"file_name": "N/A",
	"name": "N/A",
	"description": "N/A",
	"repo": "N/A",
	"branch": "main",
	"commit": "",
	"dir_suffix": "",
	"watchdog": false,
	"entry_point": "N/A",
	"python_binary": "./python-3.10.11-embed/python.exe",
	"blacklist": [],
	"plugins": [],
	"color": "ffffff",
	"last_checked_for_updates": Time.get_unix_time_from_system(),
	"last_updated": Time.get_unix_time_from_system()
}
@export var script_path = "run_repo.py"
@export var watchdog = false
var PID = 0
var installed = false
var repositories_dir = "res://repositories/"
var repo_dir = repositories_dir+repo["repo"].replace("/", "_")+repo["dir_suffix"]
var temp_path = "res://temp/"
var active = false
var current_download = {
	"repo": "N/A",
	"name": "N/A",
	"branch": "main",
	"commit": "",
	"dir_suffix": "",
	"blacklist": [],
}

func apply_repo(json):
	print("Applying repo")
	repo = json
	print(repo)
	get_node("RepoPanel/VBoxContainer/HBoxContainer/Info/Title").text = repo["name"]
	get_node("RepoPanel/VBoxContainer/HBoxContainer/Info/Title").self_modulate = Color.from_string(repo["color"], Color.WHITE)
	get_node("RepoPanel/VBoxContainer/HBoxContainer/Info/Repo").text = repo["repo"]
	get_node("RepoPanel/VBoxContainer/HBoxContainer/Info/Desc").text = repo["description"]
	watchdog = repo["watchdog"]
	if OS.has_feature("editor"):
		repositories_dir = ProjectSettings.globalize_path(repositories_dir)
	else:
		repositories_dir = DIR + repositories_dir.replace("res://", "")
	repo_dir = repositories_dir+repo["repo"].replace("/", "_")
	if repo["dir_suffix"] != "":
		repo_dir += repo["dir_suffix"]
	
	get_node("RepoPanel/VBoxContainer/HBoxContainer/Controls/Download").visible = false
	get_node("RepoPanel/VBoxContainer/HBoxContainer/Controls/Start").visible = false
	
	var dir_access = DirAccess.open(repo_dir)
	if dir_access:
		check_for_updates()
		installed = true
		get_node("RepoPanel/VBoxContainer/HBoxContainer/Controls/Start").visible = true
	else:
		get_node("RepoPanel/VBoxContainer/HBoxContainer/Controls/Download").visible = true

	# get_node("HBoxContainer/Controls/Start").visible = false
	populate_plugins_list()
	print("Applied repo")

func check_for_updates(force=false):
	var current_timestamp = Time.get_unix_time_from_system()
	# Check every fifteen minutes
	if not force:
		if current_timestamp - repo.last_checked_for_updates < 900: # 15 minutes
			print("Checked "+repo["name"]+repo["dir_suffix"]+" recently, skipping update check")
			return
	if repo["commit"] != "":
		print(repo["name"]+repo["dir_suffix"]+"is a static commit repo - no updates required")
		return
	var old_commit_info_path = "res://install_info/" + repo["repo"].replace("/", "_") + repo["dir_suffix"] + ".json"
	var global_oc_info_path = null
	if OS.has_feature("editor"):
		global_oc_info_path = ProjectSettings.globalize_path(old_commit_info_path)
	else:
		global_oc_info_path = DIR + old_commit_info_path.replace("res://", "")
	print("Global OC Info Path: " + global_oc_info_path)
	if FileAccess.file_exists(global_oc_info_path):
		print("Checking "+repo["name"]+repo["dir_suffix"]+" for updates")
		var repo_api_url = "https://api.github.com/repos/" + repo["repo"] + "/commits"
		var new_commit_info_path = "res://temp/" + repo["repo"].replace("/", "_") + repo["dir_suffix"] + ".json"
		var global_new_commit_info_path = null
		if OS.has_feature("editor"):
			global_new_commit_info_path = ProjectSettings.globalize_path(new_commit_info_path)
		else:
			global_new_commit_info_path = DIR + new_commit_info_path.replace("res://", "")
		# if file already exists, remove it
		if FileAccess.file_exists(global_new_commit_info_path):
			OS.move_to_trash(global_new_commit_info_path)

		$GithubHTTPRequest.download_file = global_new_commit_info_path
		await $GithubHTTPRequest/OffsetTimer.timeout
		$GithubHTTPRequest.request(repo_api_url)
		await $GithubHTTPRequest.request_completed

		var need_update = false

		var new_commit_file = FileAccess.open(global_new_commit_info_path, FileAccess.READ)
		if new_commit_file != null:
			var new_commit_info = JSON.parse_string(new_commit_file.get_as_text())
			if new_commit_info is Array:
				new_commit_info = new_commit_info[0]
			else:
				print("Error: Unexpected JSON format (You're probably ratelimited! Try to update again later!")
				return
			var old_commit_info = JSON.parse_string(FileAccess.open(global_oc_info_path, FileAccess.READ).get_as_text())[0]
			if old_commit_info["sha"] != new_commit_info["sha"]:
				print("check_for_update: New "+repo["name"]+" commit found: new" + new_commit_info["sha"] + " vs old" + old_commit_info["sha"])
				need_update = true
			repo["last_checked_for_updates"] = current_timestamp
			save_repo()

		# Check for plugin updates
		for plugin_node in plugins_list.get_children():
			if plugin_node.visible and plugin_node and is_instance_valid(plugin_node): # Check if the plugin_node is not previously freed yet
				print("check_for_update: Checking for updates in plugin: " + plugin_node.plugin["name"])
				var plugin = plugin_node.plugin
				var plugin_api_url = "https://api.github.com/repos/" + plugin["repo"] + "/commits"
				
				var new_plugin_commit_info_path = "res://temp/" + plugin["repo"].replace("/", "_") + ".json"
				var old_plugin_commit_info_path = "res://install_info/" + plugin["repo"].replace("/", "_") + ".json"
				var plugin_dir = "res://repositories/" + plugin["repo"].replace("/", "_")
				if plugin["dir_suffix"] != "":
					new_plugin_commit_info_path = "res://temp/" + plugin["repo"].replace("/", "_") + plugin["dir_suffix"] + ".json"
					old_plugin_commit_info_path = "res://install_info/" + plugin["repo"].replace("/", "_") + plugin["dir_suffix"] + ".json"
					plugin_dir = "res://repositories/" + plugin["repo"].replace("/", "_") + plugin["dir_suffix"]
				# Globalize
				var global_old_plugin_commit_info_path = null
				var global_new_plugin_commit_info_path = null
				var global_plugin_dir = null
				if OS.has_feature("editor"):
					global_old_plugin_commit_info_path = ProjectSettings.globalize_path(old_plugin_commit_info_path)
					global_new_plugin_commit_info_path = ProjectSettings.globalize_path(new_plugin_commit_info_path)
					global_plugin_dir = ProjectSettings.globalize_path(plugin_dir)
				else:
					global_old_plugin_commit_info_path = DIR + old_plugin_commit_info_path.replace("res://", "")
					global_new_plugin_commit_info_path = DIR + new_plugin_commit_info_path.replace("res://", "")
					global_plugin_dir = DIR + plugin_dir.replace("res://", "")
				var plugin_commit_info_exists = FileAccess.file_exists(global_old_plugin_commit_info_path)

				$GithubHTTPRequest.download_file = global_new_plugin_commit_info_path # Download the new plugin commit info
				# if plugin_commit_info_exists:
				# 	$GithubHTTPRequest.download_file = global_old_plugin_commit_info_path

				await $GithubHTTPRequest/OffsetTimer.timeout
				$GithubHTTPRequest.request(plugin_api_url) # Request the plugin commit info
				await $GithubHTTPRequest.request_completed

				var plugin_already_installed = false
				if DirAccess.dir_exists_absolute(global_plugin_dir):
					plugin_already_installed = true

				if not plugin_already_installed: # Plugin not installed
					print("check_for_update: New "+repo["name"]+"["+plugin["name"]+"] plugin found: " + global_new_plugin_commit_info_path)
					need_update = true
				else: # Plugin already installed
					if not plugin_commit_info_exists: # Old plugin commit info does not exist
						print("check_for_update: Old "+repo["name"]+"["+plugin["name"]+"] plugin commit info does not exist at: " + global_old_plugin_commit_info_path)
						need_update = true
					else: # Old plugin commit info exists
						var new_plugin_file = FileAccess.open(global_new_plugin_commit_info_path, FileAccess.READ)
						if new_plugin_file != null: # New plugin commit info exists
							var new_plugin_commit_info = JSON.parse_string(new_plugin_file.get_as_text())
							if new_plugin_commit_info is Array:
								new_plugin_commit_info = new_plugin_commit_info[0]
							else:
								print("Error: Unexpected JSON format (You're probably ratelimited! Try to update again later!")
								return
							var old_plugin_commit_info = JSON.parse_string(FileAccess.open(global_old_plugin_commit_info_path, FileAccess.READ).get_as_text())[0] # Old plugin commit info
							if old_plugin_commit_info["sha"] != new_plugin_commit_info["sha"]:
								print("check_for_update: New "+repo["name"]+"["+plugin["name"]+"] plugin commit found: new" + new_plugin_commit_info["sha"] + " vs old" + old_plugin_commit_info["sha"])
								need_update = true
							# move the temp commit info to trash, it is no longer needed - I think
							OS.move_to_trash(global_new_plugin_commit_info_path)
		if need_update:
			get_node("RepoPanel/VBoxContainer/HBoxContainer/Controls/Download").text = "Update"
			get_node("RepoPanel/VBoxContainer/HBoxContainer/Controls/Download").visible = true
		else:
			get_node("RepoPanel/VBoxContainer/HBoxContainer/Controls/Download").text = "No Updates Available"
			get_node("RepoPanel/VBoxContainer/HBoxContainer/Controls/Download").visible = false
		print("Checked "+repo["name"]+" for updates")

func populate_plugins_list():
	# Clear the plugins list
	for plugin in plugins_list.get_children():
		plugin.queue_free()
	# Add the plugins
	if installed:
		for plugin in repo["plugins"]:
			for game in plugin["games"]:
				print("Adding plugin for " + game + " | " + plugin["repo"] + " | to " + repo["name"])
				var button = plugins_button.instantiate()
				button.plugin = plugin
				button.game = game
				button.repo = self
				plugins_list.add_child(button)

func download_repo():
	print("Downloading latest repo")
	root.show_spinner()
	# Get all nodes in group download_buttons and disable them - this is to prevent multiple downloads at the same time
	print(repo)
	var buttons = get_tree().get_nodes_in_group("download_buttons")
	for button in buttons:
		button.disabled = true
	get_node("RepoPanel/VBoxContainer/HBoxContainer/Controls/Download").text = "Downloading..."
	status_bar.text = "Downloading " + repo["repo"] + "..."
	
	
	var commit_info_path = "res://install_info/" + repo["repo"].replace("/", "_") + ".json"
	var temp_commit_info_path = "res://temp/" + repo["repo"].replace("/", "_") + ".json"
	if repo["dir_suffix"] != "":
		commit_info_path += repo["dir_suffix"]
		temp_commit_info_path += repo["dir_suffix"]
	# Globalize
	var global_c_info_path = null
	var global_temp_c_info_path = null
	if OS.has_feature("editor"):
		global_c_info_path = ProjectSettings.globalize_path(commit_info_path)
		global_temp_c_info_path = ProjectSettings.globalize_path(temp_commit_info_path)
	else:
		global_c_info_path = DIR + commit_info_path.replace("res://", "")
		global_temp_c_info_path = DIR + temp_commit_info_path.replace("res://", "")
		
	var repo_already_installed = false
	if DirAccess.dir_exists_absolute(repo_dir):
		repo_already_installed = true


	var commit_info_exists = FileAccess.file_exists(global_c_info_path) # Boolean to check if commit info file exists
	var update_repo = false
	var should_download_commit = false
	var repo_api_url = "https://api.github.com/repos/" + repo["repo"] + "/commits"


	if repo["commit"] != "": # Static Commit
		if not repo_already_installed: # Static Commit
			if not commit_info_exists:
				should_download_commit = true
			update_repo = true
	else: # Latest Commit
		if repo_already_installed:
			# Download the commit info
			if commit_info_exists: # Commit info exists - Downloading to temporary destination
				$GithubHTTPRequest.download_file = global_temp_c_info_path
				should_download_commit = true
				print("Repo already installed -- downloading latest commit info to temp")
			else: # Commit info does not exist - Downloading to final destination
				$GithubHTTPRequest.download_file = global_c_info_path
				print("Repo not installed -- downloading commit info")
				should_download_commit = true
				update_repo = true
		else:
			# Handle the case where the repo is not already installed
			print("Repo not installed -- downloading commit info")
			$GithubHTTPRequest.download_file = global_c_info_path
			should_download_commit = true
			update_repo = true
		
	if should_download_commit:
		await $GithubHTTPRequest/OffsetTimer.timeout
		$GithubHTTPRequest.request(repo_api_url)
		await $GithubHTTPRequest.request_completed

	if repo_already_installed and commit_info_exists and not update_repo:
		print("Repo already installed -- loading commit infos to check for updates")
		# Load the commit info from the file
		var new_commit_info = JSON.parse_string(FileAccess.open(global_temp_c_info_path, FileAccess.READ).get_as_text())
		if new_commit_info is Array:
			new_commit_info = new_commit_info[0]
		else:
			print("Error: Unexpected JSON format (You're probably ratelimited! Try to update again later!")
			return
		var old_commit_info = JSON.parse_string(FileAccess.open(global_c_info_path, FileAccess.READ).get_as_text())[0]
		print("Commits: new" + new_commit_info["sha"] + " vs old" + old_commit_info["sha"])
		if old_commit_info["sha"] != new_commit_info["sha"]:
			update_repo = true
			print("New "+repo["name"]+" commit found: new" + new_commit_info["sha"] + " vs old" + old_commit_info["sha"])
		else:
			status_bar.text = repo["name"] + " already up to date!"

	print("Should Update: " + str(update_repo))
	if update_repo:
		# Download the repo
		print("Downloading " + repo["name"] + "...")
		ui.start_download(repo["repo"])
		var repo_url = "https://github.com/" + repo["repo"] + "/archive/refs/heads/"+repo["branch"]+".zip"
		if repo["commit"] != "": # Static commit
			repo_url = "https://github.com/" + repo["repo"] + "/archive/"+repo["commit"]+".zip"
		print(repo_url)
		var repo_path = "res://temp/" + repo["repo"].replace("/", "_")+repo["commit"] + ".zip"
		http_request.download_file = repo_path
		http_request.request(repo_url)
		http_request.request_completed.connect(download_completed)
		current_download = {
			"repo": repo["repo"],
			"name": repo["name"],
			"branch": repo["branch"],
			"commit": repo["commit"],
			"dir_suffix": repo["dir_suffix"],
		}
		await download_extracted # Wait for repo download to complete
		# Replace the old commit info with the new commit info
		print("Deleting "+global_c_info_path)
		OS.move_to_trash(global_c_info_path)
		var move_old_commit_info_to_trash_command = [
			"Move-Item",
			"\"\"" + global_temp_c_info_path.replace(" ","' '") + "\"\"",
			"\"\"" + global_c_info_path.replace(" ","' '") + "\"\""
		]
		
		# copy commit history
		print("Executing command in powershell: " + " ".join(move_old_commit_info_to_trash_command))
		var output1 = []
		OS.execute("powershell.exe", move_old_commit_info_to_trash_command, output1, true)
		print("Output: " + " ".join(output1))
		# OS.execute("mv", [, ])
	else:
		print("No Updated Needed: Discarding latest commit info: " + global_temp_c_info_path)
		OS.move_to_trash(global_temp_c_info_path)
	
	# Download related plugins
	status_bar.text = "Downloading " + repo["name"] + " Plugins..."
	for plugin in repo["plugins"]:
		var plugin_download = true
		
		var plugin_repo_api_url = "https://api.github.com/repos/" + plugin["repo"] + "/commits"
		
		var plugin_commit_info_path = "res://install_info/" + plugin["repo"].replace("/", "_") + ".json"
		var temp_plugin_commit_info_path = "res://temp/" + plugin["repo"].replace("/", "_") + ".json"
		var plugin_dir = "res://repositories/" + plugin["repo"].replace("/", "_")
		if plugin["dir_suffix"] != "":
			plugin_commit_info_path = "res://install_info/" + plugin["repo"].replace("/", "_") + plugin["dir_suffix"] + ".json"
			temp_plugin_commit_info_path = "res://temp/" + plugin["repo"].replace("/", "_") + plugin["dir_suffix"] + ".json"
			plugin_dir = "res://repositories/" + plugin["repo"].replace("/", "_") + plugin["dir_suffix"]
		# Globalize
		var global_plugin_c_info_path = null
		var global_temp_plugin_c_info_path = null
		var global_plugin_dir = null
		if OS.has_feature("editor"):
			global_plugin_c_info_path = ProjectSettings.globalize_path(plugin_commit_info_path)
			global_temp_plugin_c_info_path = ProjectSettings.globalize_path(temp_plugin_commit_info_path)
			global_plugin_dir = ProjectSettings.globalize_path(plugin_dir)
		else:
			global_plugin_c_info_path = DIR + plugin_commit_info_path.replace("res://", "")
			global_temp_plugin_c_info_path = DIR + temp_plugin_commit_info_path.replace("res://", "")
			global_plugin_dir = DIR + plugin_dir.replace("res://", "")
		
		var already_installed = false
		# Download the plugin commit info
		$GithubHTTPRequest.download_file = global_plugin_c_info_path
		if FileAccess.file_exists(global_plugin_c_info_path): # If the plugin is already installed, download the new commit info to a temp file and check if an update is required
			if DirAccess.dir_exists_absolute(global_plugin_dir):
				$GithubHTTPRequest.download_file = global_temp_plugin_c_info_path
				already_installed = true
		await $GithubHTTPRequest/OffsetTimer.timeout
		$GithubHTTPRequest.request(plugin_repo_api_url)
		await $GithubHTTPRequest.request_completed
		if already_installed:
			# Load the commit info from the file
			var new_plugin_commit_info = JSON.parse_string(FileAccess.open(global_temp_plugin_c_info_path, FileAccess.READ).get_as_text())
			if new_plugin_commit_info is Array:
				new_plugin_commit_info = new_plugin_commit_info[0]
			else:
				print("Error: Unexpected JSON format (You're probably ratelimited! Try to update again later!")
				return
			var old_plugin_commit_info = JSON.parse_string(FileAccess.open(global_plugin_c_info_path, FileAccess.READ).get_as_text())[0]
			if old_plugin_commit_info["sha"] != new_plugin_commit_info["sha"]: # If the plugin is not up to date flag it for download
				print("New "+repo["name"]+"[" + plugin["name"] + "] plugin commit found - Overwriting old commit info: new" + new_plugin_commit_info["sha"] + " vs old" + old_plugin_commit_info["sha"])
				# Replace the old commit info with the new commit info
				OS.move_to_trash(global_plugin_c_info_path)
				var command2 = [
					"Move-Item",
					"\"\"" + global_temp_plugin_c_info_path.replace(" ","' '") + "\"\"",
					"\"\"" + global_plugin_c_info_path.replace(" ","' '") + "\"\""
				]
				# copy commit history
				print("Executing command in powershell: " + " ".join(command2))
				var output2 = []
				OS.execute("powershell.exe", command2, output2, true)
				print("Output: " + " ".join(output2))
				# OS.execute("mv", [, ])
			else: # Remove the temp commit info if the plugin is already up to date
				OS.move_to_trash(global_temp_plugin_c_info_path)
				plugin_download = false
			
		if plugin_download: # If the plugin is flagged for download, download it
			var plugin_url = "https://github.com/" + plugin["repo"] + "/archive/refs/heads/" + plugin["branch"] + ".zip"
			if plugin["commit"] != "":
				plugin_url = "https://github.com/" + plugin["repo"] + "/archive/refs/heads/"+plugin["commit"]+".zip"
			var plugin_path = "res://temp/" + plugin["repo"].replace("/", "_") + ".zip"
			http_request.download_file = plugin_path
			http_request.request(plugin_url)
			current_download = plugin
			status_bar.text = "Downloading " + current_download["repo"] + "[" + current_download["branch"] + "]..."
			ui.start_download(current_download["repo"] + "[" + current_download["branch"] + "]")
			await download_extracted # Wait for plugin download to complete
			
			for plugin_node in get_tree().get_nodes_in_group("plugin"):  # undeploy the old plugins that were installed
				if plugin_node.plugin["repo"] == plugin["repo"]:
					if plugin_node.installed:
						plugin_node.undeploy()
						plugin_node._on_install_button_pressed()
	for button in buttons:
		button.disabled = false
	get_node("RepoPanel/VBoxContainer/HBoxContainer/Controls/Download").text = "No Updates Available"
	get_node("RepoPanel/VBoxContainer/HBoxContainer/Controls/Download").visible = false
	# get_node("RepoPanel/VBoxContainer/HBoxContainer/Controls/Start").visible = true
	installed = true
	root.hide_spinner()
	repo_download_finished.emit()

func download_completed(_status, _body, _headers, _code):
	print("Download completed")
	status_bar.text = "Downloaded " + current_download["repo"] + "[" + current_download["branch"] + "], extracting..."
	print(http_request.download_file)
	print(current_download)
	# Check if repo directory exists, if not create it
	var zip_path = http_request.download_file # "res://temp/" + repo["repo"].replace("/", "_") + ".zip"
	if OS.has_feature("editor"):
		zip_path = ProjectSettings.globalize_path(zip_path)
	else:
		zip_path = DIR + zip_path.replace("res://", "")
	var main_dir = temp_path + current_download["repo"].split("/")[1]+"-" + current_download["branch"] + "/*"
	if current_download["commit"] != "":
		main_dir = temp_path + current_download["repo"].split("/")[1]+"-" + current_download["commit"] + "/*"
	var output_dir = repositories_dir + current_download["repo"].replace("/", "_")
	if current_download["dir_suffix"] != "":
		output_dir += current_download["dir_suffix"]
	print(temp_path)
	print(zip_path)
	print(main_dir)
	print(output_dir)
	
	# Clear everything but the filenames in repo["blacklist"] from the repo directory
	if installed:
		var dir_access = DirAccess.open(output_dir)
		if dir_access:
			dir_access.list_dir_begin()
			while true:
				var file = dir_access.get_next()
				if file == "":
					break
				if file in repo["blacklist"]:
					continue
				OS.move_to_trash(output_dir + "/" + file)
		else:
			DirAccess.make_dir_absolute(output_dir)
	else:
		DirAccess.make_dir_absolute(output_dir)

	OS.execute("tar", ["-xf", zip_path, "-C", temp_path]) # Extract the downloaded zip to the temp directory
	OS.execute("powershell.exe", ["mv", "\""+main_dir.replace(" ","' '")+"\"", "\""+output_dir.replace(" ","' '")+"\""]) # Move the contents of the temp directory to the repo directory
	# Remove the temp directory
	OS.move_to_trash(main_dir.replace("/*", ""))
	OS.move_to_trash(zip_path)
	status_bar.text = "Extracted " + current_download["name"] + "..."
	download_extracted.emit()
	print("Extracted zip")

func _ready():
	if OS.has_feature("editor"):
		temp_path = ProjectSettings.globalize_path(temp_path)
	else:
		temp_path = DIR + temp_path.replace("res://", "")
	if repo["dir_suffix"] != "":
		repo_dir = "res://repositories/" + repo["repo"].replace("/", "_") + repo["dir_suffix"]
	if OS.has_feature("editor"):
		repo_dir = ProjectSettings.globalize_path(repo_dir)
	else:
		repo_dir = DIR + repo_dir.replace("res://", "")

# func start_repo():
# 	if $RepoPanel/VBoxContainer/HBoxContainer/Controls/Start.text == "Start":
# 		_start_repo()
# 	else:
# 		_stop_repo()

func _start_repo():
	print("Starting repo")
	# $RepoPanel/VBoxContainer/HBoxContainer/Controls/Start.text = "Stop"
	status_bar.text = "Running " + repo["name"] + "..."
	print(repo_dir)
	print(script_path)
	# var buttons = get_tree().get_nodes_in_group("start_button")
	# for button in buttons:
	# 	if button != get_node("RepoPanel/VBoxContainer/HBoxContainer/Controls/Start"):
	# 		button.disabled = true
	get_node("RepoPanel/VBoxContainer/HBoxContainer/Controls/Download").visible = false
	
	var watchdawg = watchdog
	if root.settings["crash_recovery"] != true:
		watchdawg = false
	if repo["dir_suffix"] != "":
		PID = python.run_script(repo["python_binary"], script_path, ["\""+repo['repo']+"\"", "-dir_suffice", "\""+repo["dir_suffix"]+"\""], root.settings["debug_console"], watchdawg)
	else:
		PID = python.run_script(repo["python_binary"], script_path, ["\""+repo['repo']+"\""], root.settings["debug_console"], watchdawg)
	active = true
	print("Started repo")

func _stop_repo():
	print("Stopping repo")
	# $RepoPanel/VBoxContainer/HBoxContainer/Controls/Start.text = "Start"
	status_bar.text = "Stopping " + repo["name"] + "..."
	python.stop_PID(PID)
	var buttons = get_tree().get_nodes_in_group("start_button")
	for button in buttons:
		button.disabled = false
	active = false
	status_bar.text = repo["name"] + " has been stopped"
	print("Stopped repo")
	
# func _on_button_pressed(): # When selected, visible = false for all other repositories download and start buttons
# 	var repositories = get_tree().get_nodes_in_group("repository")
# 	for repository in repositories:
# 		if repository != self:
# 			repository.get_node("RepoPanel/VBoxContainer/HBoxContainer/Controls/Download").visible = false
# 			# repository.get_node("RepoPanel/VBoxContainer/HBoxContainer/Controls/Start").visible = false
# 	self.get_node("RepoPanel/VBoxContainer/HBoxContainer/Controls/Download").visible = true
		
		
# func plugin_selected(plugin): # from plugin button
# 	print("Plugin selected")
# 	if "plugin_path" not in root.settings or root.settings["plugin_path"] == "":
# 		status_bar.text = "Please set the plugin path in the settings"
# 	else:
# 		if active == true: # If the repo is running, stop it
# 			_stop_repo()
# 		else: # If the repo is not running, start it
# 			root.plugin_selected(plugin)
# 			_start_repo()

func save_repo():
	var file_path = "res://repo_configs/"+repo["file_name"]
	if OS.has_feature("editor"):
		file_path = ProjectSettings.globalize_path(file_path)
	else:
		file_path = DIR + file_path.replace("res://", "")
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(repo, "\t"))
	file.close()

func _on_repo_download_finished():
	populate_plugins_list()
	$RepoPanel/VBoxContainer/HBoxContainer/Controls/Start.visible = true
	ui.is_downloading = false
	status_bar.text = "Finished downloading " + repo["name"] + ", please configure the repo and start it"


func start_repo():
	pass # Replace with function body.
