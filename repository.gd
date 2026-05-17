extends VBoxContainer
@onready var root = get_tree().root.get_child(0)
@onready var python = get_tree().root.get_child(0).get_node("PythonInterpreter")
# @onready var http_request = get_tree().root.get_child(0).get_node("HTTPRequest")
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
	"last_updated": Time.get_unix_time_from_system(),
	"requirements_hash": ""
}

@export var script_path = "run_repo.py"
@export var watchdog = false
var PID = 0
var installed = false
var repositories_dir = "res://repositories/"
var repo_dir = repositories_dir+repo["repo"].replace("/", "_")+repo["dir_suffix"]
var temp_path = "res://temp/"
var active = false

var mingit_path = "res://cmd/git.exe"
var git_binary = mingit_path

func get_repo_filename():
	return repo["repo"].replace("/", "_") + repo["dir_suffix"]

func get_repo_dir_path():
	repo_dir = repositories_dir + get_repo_filename()
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path(repo_dir)
	else:
		return DIR + repo_dir.replace("res://", "")

func apply_repo(json):
	print("Applying repo")
	repo = json
	print(repo)
	get_node("RepoPanel/VBoxContainer/HBoxContainer/Info/Title").text = repo["name"]
	get_node("RepoPanel/VBoxContainer/HBoxContainer/Info/Title").self_modulate = Color.from_string(repo["color"], Color.WHITE)
	get_node("RepoPanel/VBoxContainer/HBoxContainer/Info/Repo").text = repo["repo"]
	get_node("RepoPanel/VBoxContainer/HBoxContainer/Info/Desc").text = repo["description"]
	watchdog = repo["watchdog"]
	
	get_node("RepoPanel/VBoxContainer/HBoxContainer/Controls/Download").visible = false
	get_node("RepoPanel/VBoxContainer/HBoxContainer/Controls/Start").visible = false
	
	var dir_access = DirAccess.open(get_repo_dir_path())
	if dir_access:
		# check_for_updates()
		installed = true
		get_node("RepoPanel/VBoxContainer/HBoxContainer/Controls/Start").visible = true
	else:
		get_node("RepoPanel/VBoxContainer/HBoxContainer/Controls/Download").visible = true

	# get_node("HBoxContainer/Controls/Start").visible = false
	populate_plugins_list()
	print("Applied repo")

func check_for_updates(force=false):
	if repo["commit"] != "":
		print(repo["name"]+repo["dir_suffix"]+"is a static commit repo - no updates required")
		return
	var current_timestamp = Time.get_unix_time_from_system()
	# Check every fifteen minutes
	if not force and current_timestamp - repo.last_checked_for_updates < 900: # 15 minutes
		print("Checked "+repo["name"]+repo["dir_suffix"]+" recently, skipping update check")
		return

	status_bar.text = "Checking for updates for " + repo["name"] + "..."

	load_repo()
	
	var old_commit_info_path = "res://install_info/" + get_repo_filename() + ".json"
	var new_commit_info_path = "res://temp/" + get_repo_filename() + ".json"
	if OS.has_feature("editor"):
		old_commit_info_path = ProjectSettings.globalize_path(old_commit_info_path)
		new_commit_info_path = ProjectSettings.globalize_path(new_commit_info_path)
	else:
		old_commit_info_path = DIR + old_commit_info_path.replace("res://", "")
		new_commit_info_path = DIR + new_commit_info_path.replace("res://", "")

	if FileAccess.file_exists(new_commit_info_path): # if file already exists, remove it
		OS.move_to_trash(new_commit_info_path)
		
	var need_update = false
	print("Global OC Info Path: " + old_commit_info_path)
	if FileAccess.file_exists(old_commit_info_path):
		print("Checking "+repo["name"]+repo["dir_suffix"]+" for updates")
		var repo_api_url = "https://api.github.com/repos/" + repo["repo"] + "/commits"

		# Download latest commit info to temp location
		$GithubHTTPRequest.download_file = new_commit_info_path
		await $GithubHTTPRequest/OffsetTimer.timeout
		$GithubHTTPRequest.request(repo_api_url)
		await $GithubHTTPRequest.request_completed


		var new_commit_file = FileAccess.open(new_commit_info_path, FileAccess.READ)
		if new_commit_file != null:
			var new_commit_info = JSON.parse_string(new_commit_file.get_as_text())
			if new_commit_info is Array:
				new_commit_info = new_commit_info[0]
			else:
				print("Error: Unexpected JSON format (You're probably ratelimited! Try to update again later!")
				return
			var old_commit_info = JSON.parse_string(FileAccess.open(old_commit_info_path, FileAccess.READ).get_as_text())[0]
			if old_commit_info["sha"] != new_commit_info["sha"]:
				print("check_for_update: New "+repo["name"]+" commit found: new" + new_commit_info["sha"] + " vs old" + old_commit_info["sha"])
				need_update = true
			repo["last_checked_for_updates"] = current_timestamp
			save_repo()
		else:
			print("Error: Could not open new commit info file to check for updates (You're probably ratelimited! Try to update again later!)")
			status_bar.text = "Error checking for updates for " + repo["name"] + " (You're probably ratelimited! Try to update again later!)"
		new_commit_file.close()
		OS.move_to_trash(new_commit_info_path)

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
				if OS.has_feature("editor"):
					old_plugin_commit_info_path = ProjectSettings.globalize_path(old_plugin_commit_info_path)
					new_plugin_commit_info_path = ProjectSettings.globalize_path(new_plugin_commit_info_path)
					plugin_dir = ProjectSettings.globalize_path(plugin_dir)
				else:
					old_plugin_commit_info_path = DIR + old_plugin_commit_info_path.replace("res://", "")
					new_plugin_commit_info_path = DIR + new_plugin_commit_info_path.replace("res://", "")
					plugin_dir = DIR + plugin_dir.replace("res://", "")
				
				var plugin_commit_info_exists = FileAccess.file_exists(old_plugin_commit_info_path)
				
				if FileAccess.file_exists(new_plugin_commit_info_path): # if file already exists, remove it
					OS.move_to_trash(new_plugin_commit_info_path)

				$GithubHTTPRequest.download_file = new_plugin_commit_info_path # Download the new plugin commit info
				await $GithubHTTPRequest/OffsetTimer.timeout
				$GithubHTTPRequest.request(plugin_api_url) # Request the plugin commit info
				await $GithubHTTPRequest.request_completed

				var plugin_already_installed = false
				if DirAccess.dir_exists_absolute(plugin_dir):
					plugin_already_installed = true

				if not plugin_already_installed: # Plugin not installed
					print("check_for_update: Fresh "+repo["name"]+"["+plugin["name"]+"] plugin found: " + new_plugin_commit_info_path)
					need_update = true
				else: # Plugin already installed
					if not plugin_commit_info_exists: # Old plugin commit info does not exist
						print("check_for_update: Old "+repo["name"]+"["+plugin["name"]+"] plugin commit info does not exist at: " + old_plugin_commit_info_path)
						need_update = true
					else: # Old plugin commit info exists
						var new_plugin_file = FileAccess.open(new_plugin_commit_info_path, FileAccess.READ)
						if new_plugin_file != null: # New plugin commit info exists
							var new_plugin_commit_info = JSON.parse_string(new_plugin_file.get_as_text())
							if new_plugin_commit_info is Array:
								new_plugin_commit_info = new_plugin_commit_info[0]
							else:
								print("Error: Unexpected JSON format (You're probably ratelimited! Try to update again later!")
								status_bar.text = "Error checking for updates for plugin " + plugin["name"] + " (You're probably ratelimited! Try to update again later!)"
								return
							var old_plugin_commit_info = JSON.parse_string(FileAccess.open(old_plugin_commit_info_path, FileAccess.READ).get_as_text())[0] # Old plugin commit info
							if old_plugin_commit_info["sha"] != new_plugin_commit_info["sha"]:
								print("check_for_update: New "+repo["name"]+"["+plugin["name"]+"] plugin commit found: new" + new_plugin_commit_info["sha"] + " vs old" + old_plugin_commit_info["sha"])
								need_update = true
						new_plugin_file.close()
				if FileAccess.file_exists(new_plugin_commit_info_path):
					OS.move_to_trash(new_plugin_commit_info_path) # move the temp commit info to trash, it is no longer needed - I think
		if need_update:
			get_node("RepoPanel/VBoxContainer/HBoxContainer/Controls/Download").text = "Update"
			get_node("RepoPanel/VBoxContainer/HBoxContainer/Controls/Download").visible = true
		else:
			get_node("RepoPanel/VBoxContainer/HBoxContainer/Controls/Download").text = "No Updates Available"
			get_node("RepoPanel/VBoxContainer/HBoxContainer/Controls/Download").visible = false
		print("Checked "+repo["name"]+" for updates")
	return need_update

func populate_plugins_list():
	# Clear the plugins list
	for plugin in plugins_list.get_children():
		plugin.queue_free()
	# Add the plugins
	if installed:
		for plugin in repo["plugins"]:
			# var should_be_downloaded = false
			for game in plugin["games"]:
				print("Adding plugin for " + game + " | " + plugin["repo"] + " | to " + repo["name"])
				var button = plugins_button.instantiate()
				button.plugin = plugin
				button.game = game
				button.repo = self
				plugins_list.add_child(button)
				# should_be_downloaded = true
			# if should_be_downloaded:
			# 	print("Plugin " + plugin["name"] + " should be downloaded")
			# 	download_plugin(plugin)
			
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
	
	
	var commit_info_path = "res://install_info/" + get_repo_filename() + ".json"
	var temp_commit_info_path = "res://temp/" + get_repo_filename() + ".json"
	# Globalize the paths
	if OS.has_feature("editor"):
		commit_info_path = ProjectSettings.globalize_path(commit_info_path)
		temp_commit_info_path = ProjectSettings.globalize_path(temp_commit_info_path)
	else:
		commit_info_path = DIR + commit_info_path.replace("res://", "")
		temp_commit_info_path = DIR + temp_commit_info_path.replace("res://", "")
		
	var repo_already_installed = DirAccess.dir_exists_absolute(get_repo_dir_path()) # Check if the repo is already installed by checking if the repo directory exists
	var commit_info_exists = FileAccess.file_exists(commit_info_path) # Boolean to check if commit info file exists
	var update_repo = false # Boolean to check if the repo needs to be updated
	var clone_repo = false # Boolean to check if we should clone the repo 
	var should_download_commit_info = false # Boolean to check if we should download the latest commit info, this is used to prevent unnecessary downloads of the commit info when we already know an update is needed or not needed based on the existence of the commit info file and whether the repo is already installed or not
	var is_static_commit = repo["commit"] != "" # Boolean to check if the repo is a static commit repo, this is used to prevent unnecessary update checks for repos that are static commits, since they will never have updates
	print("Repo already installed: " + str(repo_already_installed))
	print("Commit info file exists: " + str(commit_info_exists))
	print("Repo is a static commit: " + str(is_static_commit))
	
	var repo_api_url = "https://api.github.com/repos/" + repo["repo"] + "/commits" # API URL to get the latest commits of the repo, this is used to check for updates and to get the latest commit sha if the repo is not already installed or if the commit info file does not exist


	
	if commit_info_exists: # Commit info exists - Download new info to temporary destination
		$GithubHTTPRequest.download_file = temp_commit_info_path
		should_download_commit_info = true
		print("Repo already installed -- downloading latest commit info to temp")
	else: # Commit info does not exist - Download to final destination
		$GithubHTTPRequest.download_file = commit_info_path
		should_download_commit_info = true
		print("Repo not installed -- downloading commit info")

	if not repo_already_installed: # Repo not installed - we need to clone/download the repo
		clone_repo = true

		
	if should_download_commit_info:
		await $GithubHTTPRequest/OffsetTimer.timeout
		$GithubHTTPRequest.request(repo_api_url)
		await $GithubHTTPRequest.request_completed

	if repo_already_installed and commit_info_exists and not is_static_commit and not update_repo and not clone_repo: # If the repo is already installed, the commit info file exists, the repo is not a static commit repo, and we haven't already determined that the repo needs to be freshly installed, then we can check if an update is needed by comparing the latest commit info with the existing commit info
		print("Repo already installed -- loading commit infos to check for updates")
		# Load the commit info from the file
		var new_commit_info = JSON.parse_string(FileAccess.open(temp_commit_info_path, FileAccess.READ).get_as_text())
		if new_commit_info is Array:
			new_commit_info = new_commit_info[0]
		else:
			print("Error: Unexpected JSON format (You're probably ratelimited! Try to update again later!")
			return
		var old_commit_info = JSON.parse_string(FileAccess.open(commit_info_path, FileAccess.READ).get_as_text())[0]
		print("Commits: new" + new_commit_info["sha"] + " vs old" + old_commit_info["sha"])
		if old_commit_info["sha"] != new_commit_info["sha"]:
			update_repo = true
			print("New "+repo["name"]+" commit found: new" + new_commit_info["sha"] + " vs old" + old_commit_info["sha"])
		else:
			status_bar.text = repo["name"] + " already up to date!"

	if is_static_commit and repo_already_installed: # Static Commit
		update_repo = false
	if clone_repo:
		print("Repo is a static commit or not installed -- cloning repo")
		update_repo = false

	print("Should Clone: " + str(clone_repo))
	print("Should Update: " + str(update_repo))

	if clone_repo:
		print("Proceeding with repo download")
		var git_command = [git_binary, "clone", "https://github.com/" + repo["repo"], get_repo_dir_path()]
		print("Executing command: " + " ".join(git_command))
		# var output = []
		# var error_code = OS.execute("powershell.exe", git_command, output, true)
		# print("Git command output: " + " ".join(output))
		# print("Git command error code: " + str(error_code))
		var repo_PID = OS.create_process("powershell.exe", git_command, true)

		# wait for the repo to be cloned before checking out the specific commit, this is necessary to prevent errors when trying to checkout a commit that doesn't exist yet because the cloning process hasn't finished
		while OS.is_process_running(repo_PID):
			await get_tree().process_frame
		
		if repo["commit"] != "": # Static commit - checkout the specific commit
			print("Repo is a static commit -- checking out specific commit: " + repo["commit"])
			var git_checkout_command = [git_binary, "reset", "--hard", repo["commit"]]
			print("Executing command: " + " ".join(git_checkout_command))
			var output_checkout = []
			var error_code_checkout = OS.execute("powershell.exe", git_checkout_command, output_checkout, true, get_repo_dir_path())
			print("Git checkout command output: " + " ".join(output_checkout))
			print("Git checkout command error code: " + str(error_code_checkout))
		print("Finished downloading repo: " + repo["name"])

	if update_repo:
		var git_command = ["cd", get_repo_dir_path(), "&&", git_binary, "pull"]
		if OS.has_feature("windows"):
			git_command = ["cd", "\""+get_repo_dir_path()+"\";", git_binary, "pull"]
		print("Executing command: " + " ".join(git_command))
		# var output = []
		# var error_code = OS.execute("powershell.exe", git_command, output, true)
		# print("Git command output: " + " ".join(output))
		# print("Git command error code: " + str(error_code))
		var repo_PID = OS.create_process("powershell.exe", git_command, true)
		
		# Replace the old commit info with the new commit info
		print("Deleting "+commit_info_path)
		OS.move_to_trash(commit_info_path)
		var move_old_commit_info_to_trash_command = [
			"Move-Item",
			"\"" + temp_commit_info_path.replace(" ","' '") + "\"",
			"\"" + commit_info_path.replace(" ","' '") + "\""
		]
		
		# copy commit history
		print("Executing command in powershell: " + " ".join(move_old_commit_info_to_trash_command))
		var output1 = []
		OS.execute("powershell.exe", move_old_commit_info_to_trash_command, output1, true)
		print("Output: " + " ".join(output1))
		print("Finished repo download/update: " + repo["name"])
		
	if FileAccess.file_exists(temp_commit_info_path):
			print("No Updated Needed: Discarding latest commit info: " + temp_commit_info_path)
			OS.move_to_trash(temp_commit_info_path)

	# Download related plugins
	status_bar.text = "Downloading " + repo["name"] + " Plugins..."
	for plugin in repo["plugins"]:
		print("Downloading plugin: " + plugin["name"])
		
		var plugin_commit_info_path = "res://install_info/" + plugin["repo"].replace("/", "_") + ".json"
		var temp_plugin_commit_info_path = "res://temp/" + plugin["repo"].replace("/", "_") + ".json"
		var plugin_dir = "res://repositories/" + plugin["repo"].replace("/", "_")
		if plugin["dir_suffix"] != "":
			plugin_commit_info_path = "res://install_info/" + plugin["repo"].replace("/", "_") + plugin["dir_suffix"] + ".json"
			temp_plugin_commit_info_path = "res://temp/" + plugin["repo"].replace("/", "_") + plugin["dir_suffix"] + ".json"
			plugin_dir = "res://repositories/" + plugin["repo"].replace("/", "_") + plugin["dir_suffix"]
		# Globalize
		if OS.has_feature("editor"):
			plugin_commit_info_path = ProjectSettings.globalize_path(plugin_commit_info_path)
			temp_plugin_commit_info_path = ProjectSettings.globalize_path(temp_plugin_commit_info_path)
			plugin_dir = ProjectSettings.globalize_path(plugin_dir)
		else:
			plugin_commit_info_path = DIR + plugin_commit_info_path.replace("res://", "")
			temp_plugin_commit_info_path = DIR + temp_plugin_commit_info_path.replace("res://", "")
			plugin_dir = DIR + plugin_dir.replace("res://", "")


		var plugin_repo_api_url = "https://api.github.com/repos/" + plugin["repo"] + "/commits"
		
		var plugin_commit_info_exists = FileAccess.file_exists(plugin_commit_info_path)
		var already_installed = DirAccess.dir_exists_absolute(plugin_dir)
		var update_plugin = false
		var clone_plugin = false
		var should_download_plugin_commit_info = false

		
		if plugin_commit_info_exists: # Commit info exists - Download new info to temporary destination
			$GithubHTTPRequest.download_file = temp_plugin_commit_info_path
			should_download_plugin_commit_info = true
			print("Plugin already installed -- downloading latest commit info to temp")
		else: # Commit info does not exist - Download to final destination
			$GithubHTTPRequest.download_file = plugin_commit_info_path
			should_download_plugin_commit_info = true
			print("Plugin not installed -- downloading commit info")

		if not already_installed: # Repo not installed - we need to clone/download the repo
			print("Repo not installed, so plugin needs to be cloned")
			clone_plugin = true

		if plugin["commit"] != "" and already_installed: # Static Commit
			update_plugin = false


		if should_download_plugin_commit_info: # Download the plugin commit info
			print("Downloading plugin commit info for " + plugin["name"])
			await $GithubHTTPRequest/OffsetTimer.timeout
			$GithubHTTPRequest.request(plugin_repo_api_url)
			await $GithubHTTPRequest.request_completed

		if already_installed and plugin_commit_info_exists and plugin["commit"] == "" and not update_plugin and not clone_plugin: # If the plugin is already installed, the commit info file exists, the plugin is not a static commit plugin, and we haven't already determined that the plugin needs to be freshly installed, then we can check if an update is needed by comparing the latest commit info with the existing commit info
			print("Plugin already installed -- loading commit infos to check for updates")
			# Load the commit info from the file
			var new_plugin_commit_info = JSON.parse_string(FileAccess.open(temp_plugin_commit_info_path, FileAccess.READ).get_as_text())
			if new_plugin_commit_info is Array:
				new_plugin_commit_info = new_plugin_commit_info[0]
			else:
				print("Error: Unexpected JSON format (You're probably ratelimited! Try to update again later!")
				return
			var old_plugin_commit_info = JSON.parse_string(FileAccess.open(plugin_commit_info_path, FileAccess.READ).get_as_text())[0]
			print("Commits: new" + new_plugin_commit_info["sha"] + " vs old" + old_plugin_commit_info["sha"])
			if old_plugin_commit_info["sha"] != new_plugin_commit_info["sha"]:
				update_plugin = true
				print("New "+plugin["name"]+" commit found: new" + new_plugin_commit_info["sha"] + " vs old" + old_plugin_commit_info["sha"])
			else:
				status_bar.text = plugin["name"] + " already up to date!"

		if clone_plugin:
			print("Plugin repo is a static commit or not installed -- cloning repo")
			update_plugin = false

		print("Should Clone Plugin: " + str(clone_plugin))
		print("Should Update Plugin: " + str(update_plugin))
			
		if clone_plugin: # If the plugin is flagged for download, download it
			status_bar.text = "Downloading " + plugin["repo"] + "[" + plugin["branch"] + "]..."
			for plugin_node in get_tree().get_nodes_in_group("plugin"):  # undeploy the old plugins that were installed
				if plugin_node.plugin["repo"] == plugin["repo"]:
					if plugin_node.installed:
						plugin_node.undeploy()
						plugin_node._on_install_button_pressed()
			var git_command = [git_binary, "clone", "https://github.com/" + plugin["repo"], plugin_dir]
			print("Executing command: " + " ".join(git_command))
			# OS.execute("powershell.exe", git_command, [], true)
			var plugin_PID = OS.create_process("powershell.exe", git_command, true)
			while OS.is_process_running(plugin_PID):
				await get_tree().process_frame
			if plugin["commit"] != "": # Static commit - checkout the specific commit
				var git_checkout_command = [git_binary, "reset", "--hard", plugin["commit"]]
				OS.execute("powershell.exe", git_checkout_command, [], true, plugin_dir)
			print("Finished downloading plugin: " + plugin["name"])

		if update_plugin: # If the plugin is flagged for update, update it
			var git_command = ["cd", plugin_dir, "&&", git_binary, "pull"]
			if OS.has_feature("windows"):
				git_command = ["cd", "\""+plugin_dir+"\";", git_binary, "pull"]
			print("Executing command: " + " ".join(git_command))
			# var output = []
			# var error_code = OS.execute("powershell.exe", git_command, output, true)
			# print("Git command output: " + " ".join(output))
			# print("Git command error code: " + str(error_code))
			# print("Finished updating plugin: " + plugin["name"])
			var plugin_PID = OS.create_process("powershell.exe", git_command, true)
			while OS.is_process_running(plugin_PID):
				await get_tree().process_frame
			print("Finished updating plugin: " + plugin["name"])
			
	for button in buttons:
		button.disabled = false
	get_node("RepoPanel/VBoxContainer/HBoxContainer/Controls/Download").text = "No Updates Available"
	get_node("RepoPanel/VBoxContainer/HBoxContainer/Controls/Download").visible = false
	# get_node("RepoPanel/VBoxContainer/HBoxContainer/Controls/Start").visible = true
	installed = true
	root.hide_spinner()
	repo_download_finished.emit()
	print("Finished repo download/update: " + repo["name"])

func _ready():
	if repo["dir_suffix"] != "":
		repo_dir = "res://repositories/" + get_repo_filename()
	
	if OS.has_feature("editor"):
		temp_path = ProjectSettings.globalize_path(temp_path)
		repo_dir = ProjectSettings.globalize_path(repo_dir)
		mingit_path = ProjectSettings.globalize_path(mingit_path)
	else:
		temp_path = DIR + temp_path.replace("res://", "")
		repo_dir = DIR + repo_dir.replace("res://", "")
		mingit_path = DIR + mingit_path.replace("res://", "")

	if OS.has_feature("windows"):
		git_binary = mingit_path
	else:
		git_binary = "git" # Assume git is in PATH for non-windows platforms, which should be the case for most users

# func start_repo():
# 	if $RepoPanel/VBoxContainer/HBoxContainer/Controls/Start.text == "Start":
# 		_start_repo()
# 	else:
# 		_stop_repo()

func _start_repo():
	print("Starting repo")
	# Check if python_binary is set and if it exists
	$RepoPanel/VBoxContainer/HBoxContainer/Controls/Start.text = "Stop"
	var python_binary_missing = not FileAccess.file_exists(repo["python_binary"])
	var python_binary_is_path = "/" in repo["python_binary"] or "\\" in repo["python_binary"]
	if repo["python_binary"] == "" or (python_binary_missing and python_binary_is_path):
		status_bar.text = "Error: Python binary not found for " + repo["name"]
		root.popup.show_popup("Missing Python Binary", "The python binary for this repository is not set or cannot be found. Please set the correct path in the repository configuration.\n\nExpected Path: " + repo["python_binary"] + "\nMake sure you download the correct embedded python directory and extract it into the launcher directory if you're using Pantella or Mantella on Windows 10/11!", "OK")
		$RepoPanel/VBoxContainer/HBoxContainer/Controls/Start.text = "Start"
		return
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
		PID = python.run_script(repo["python_binary"], script_path, [repo['repo'], "--dir_suffix", repo["dir_suffix"]], root.settings["debug_console"], watchdawg)
	else:
		PID = python.run_script(repo["python_binary"], script_path, [repo['repo']], root.settings["debug_console"], watchdawg)
	active = true
	print("Started repo")

func _stop_repo():
	print("Stopping repo")
	$RepoPanel/VBoxContainer/HBoxContainer/Controls/Start.text = "Start"
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
	apply_repo(repo) # Update the repo variable with the current values from the UI before saving

func load_repo():
	var file_path = "res://repo_configs/"+repo["file_name"]
	if OS.has_feature("editor"):
		file_path = ProjectSettings.globalize_path(file_path)
	else:
		file_path = DIR + file_path.replace("res://", "")
	if FileAccess.file_exists(file_path):
		print("Loading repo config from: " + file_path)
		var file = FileAccess.open(file_path, FileAccess.READ)
		var json_string = file.get_as_text()
		file.close()
		var json = JSON.new()
		var error = json.parse(json_string)
		if error == OK:
			apply_repo(json.data)
		else:
			print("Error parsing repo config JSON: " + json.get_error_message(), " in ", json_string, " at line ", json.get_error_line())
	else:
		print("Repo config file does not exist at path: " + file_path)

func _on_repo_download_finished():
	populate_plugins_list()
	$RepoPanel/VBoxContainer/HBoxContainer/Controls/Start.visible = true
	ui.is_downloading = false
	status_bar.text = "Finished downloading " + repo["name"] + ", please configure the repo and start it"


func start_repo():
	pass # Replace with function body.
