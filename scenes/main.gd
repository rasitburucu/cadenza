extends Control

var tracks: Array[String] = []

var current_index: int = 0
var user_dragging: bool = false
var shuffle_on: bool = false
enum RepeatMode { OFF, ALL, ONE }
var repeat_mode = RepeatMode.OFF


func _ready():
	get_tree().auto_accept_quit = false
	$SeekTimer.start()
	$VBoxContainer/VolumeSlider.value = 80.0   # önce default
	$VBoxContainer/ControlRow/PlayPauseButton.text = "▶"
	_load_config()


# PARÇA YÜKLEME
func _load_track(index: int, autoplay: bool = true):
	current_index = index
	var stream = AudioStreamMP3.new()
	stream.data = FileAccess.get_file_as_bytes(tracks[index])
	$AudioStreamPlayer.stream = stream
	if autoplay:
		$AudioStreamPlayer.play()
	$VBoxContainer/TrackTitle.text = tracks[index].get_file().get_basename()
	$VBoxContainer/TimeRow/DurationLabel.text = _format_time(stream.get_length())
	$VBoxContainer/SeekBar.value = 0.0
	$VBoxContainer/PlaylistPanel/TrackList.select(index)


func _refresh_play_button():
	var is_paused = $AudioStreamPlayer.stream_paused or not $AudioStreamPlayer.playing
	$VBoxContainer/ControlRow/PlayPauseButton.text = "▶" if is_paused else "⏸"

# PLAY / PAUSE
func _on_play_pause_button_pressed():
	if $AudioStreamPlayer.stream_paused:
		# Duraklatılmıştı → devam et
		$AudioStreamPlayer.stream_paused = false
	elif $AudioStreamPlayer.playing:
		# Çalıyordu → duraklat
		$AudioStreamPlayer.stream_paused = true
	else:
		# Tamamen durmuştu → baştan başlat
		if not tracks.is_empty():
			_load_track(current_index)
	_refresh_play_button()
	

# SEEK BAR
func _on_seek_timer_timeout():
	if $AudioStreamPlayer.playing and not $AudioStreamPlayer.stream_paused and not user_dragging:
		var pos = $AudioStreamPlayer.get_playback_position()
		var total = $AudioStreamPlayer.stream.get_length()
		$VBoxContainer/SeekBar.value = (pos / total) * 100.0
		$VBoxContainer/TimeRow/ElapsedLabel.text = _format_time(pos)

func _on_seek_bar_drag_started():
	user_dragging = true

func _on_seek_bar_drag_ended(_value_changed: bool):
	user_dragging = false
	var total = $AudioStreamPlayer.stream.get_length()
	var seek_pos = ($VBoxContainer/SeekBar.value / 100.0) * total
	$AudioStreamPlayer.seek(seek_pos)


# VOLUME
func _on_volume_slider_value_changed(value: float):
	$AudioStreamPlayer.volume_db = linear_to_db(value / 100.0)


# PREVIOUS / NEXT
func _on_prev_button_pressed():
	_load_track((current_index - 1 + tracks.size()) % tracks.size())

func _on_next_button_pressed():
	if tracks.is_empty():
		return
	match repeat_mode:
		RepeatMode.ONE:
			# Aynı parçayı baştan başlat
			_load_track(current_index)
		RepeatMode.ALL:
			if shuffle_on:
				_load_track(randi() % tracks.size())
			else:
				_load_track((current_index + 1) % tracks.size())
		RepeatMode.OFF:
			if shuffle_on:
				_load_track(randi() % tracks.size())
			else:
				var next = current_index + 1
				if next < tracks.size():
					_load_track(next)
				# Son parçadaysa dur, bir şey yapma

# YARDIMCI
func _format_time(seconds: float) -> String:
	var m: int = int(seconds) / 60
	var s: int = int(seconds) % 60
	return "%02d:%02d" % [m, s]

# AddFileButton'ın pressed signal'ına bağla
func _on_add_file_button_pressed():
	$FileDialog.popup_centered(Vector2(800, 600))
	# popup_centered: diyalogu ekranın ortasında açar
	# Vector2(800, 600): pencere boyutu

# FileDialog'ın files_selected signal'ına bağla
# (file_selected değil, files_selected — çoklu seçim için)
func _on_file_dialog_files_selected(paths: PackedStringArray):
	var was_empty = tracks.is_empty()
	for path in paths:
		tracks.append(path)
	_refresh_playlist()
	if was_empty:
		_load_track(0)

# TrackList'e tıklanınca çağrılır
# item_selected: kullanıcının tıkladığı satırın index numarası
func _on_track_list_item_selected(index: int):
	_load_track(index)

# Dosya eklenince listeyi güncelle
# _on_file_dialog_files_selected içine, tracks.append(path) satırından SONRA ekle:
func _refresh_playlist():
	$VBoxContainer/PlaylistPanel/TrackList.clear()
	for i in tracks.size():
		var name = tracks[i].get_file().get_basename()
		$VBoxContainer/PlaylistPanel/TrackList.add_item(name)

# Seçili parçayı sil
func _on_remove_button_pressed():
	var selected = $VBoxContainer/PlaylistPanel/TrackList.get_selected_items()
	if selected.is_empty():
		return
	var index = selected[0]
	tracks.remove_at(index)
	_refresh_playlist()
	# Silinen çalan parçaysa durdur, değilse index'i güncelle
	if index == current_index:
		$AudioStreamPlayer.stop()
		_refresh_play_button()
	elif index < current_index:
		current_index -= 1

# AddFolderButton'ın pressed signal'ına bağla
func _on_add_folder_button_pressed():
	$FolderDialog.popup_centered(Vector2(800, 600))

# FolderDialog'ın dir_selected signal'ına bağla
# path: kullanıcının seçtiği klasörün tam yolu
func _on_folder_dialog_dir_selected(path: String):
	var dir = DirAccess.open(path)
	if dir == null:
		return
	
	# list_dir_begin: klasörü tara
	# false, false → gizli dosyaları ve . / .. girdilerini atla
	dir.list_dir_begin()
	var file_name = dir.get_next()
	var was_empty = tracks.is_empty()
	
	while file_name != "":
		if not dir.current_is_dir() and file_name.to_lower().ends_with(".mp3"):
			tracks.append(path + "/" + file_name)
		file_name = dir.get_next()
	
	dir.list_dir_end()
	_refresh_playlist()
	if was_empty and not tracks.is_empty():
		_load_track(0)

func _on_shuffle_button_pressed():
	shuffle_on = not shuffle_on
	var btn = $VBoxContainer/ControlRow/ShuffleButton
	btn.modulate = Color(1, 1, 0) if shuffle_on else Color(1, 1, 1)

func _on_repeat_button_pressed():
	repeat_mode = (repeat_mode + 1) % 3
	var btn = $VBoxContainer/ControlRow/RepeatButton
	match repeat_mode:
		RepeatMode.OFF: btn.modulate = Color(1, 1, 1)   # normal
		RepeatMode.ALL: btn.modulate = Color(1, 1, 0)   # sarı = hepsi tekrar
		RepeatMode.ONE: btn.modulate = Color(1, 0.5, 0) # turuncu = tek tekrar

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_config()
		get_tree().quit()


func _save_config():
	var config = {
		"volume": $VBoxContainer/VolumeSlider.value,
		"shuffle": shuffle_on,
		"repeat_mode": repeat_mode,
		"last_playlist": tracks,
		"last_index": current_index
	}
	
	var file = FileAccess.open("user://config.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(config))
	file.close()


func _load_config():
	if not FileAccess.file_exists("user://config.json"):
		return

	var file = FileAccess.open("user://config.json", FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()

	if data == null:
		return

	if data.has("volume"):
		$VBoxContainer/VolumeSlider.value = data["volume"]

	if data.has("shuffle"):
		shuffle_on = data["shuffle"]
		var btn = $VBoxContainer/ControlRow/ShuffleButton
		btn.modulate = Color(1, 1, 0) if shuffle_on else Color(1, 1, 1)

	if data.has("repeat_mode"):
		repeat_mode = int(data["repeat_mode"])
		var btn = $VBoxContainer/ControlRow/RepeatButton
		match repeat_mode:
			RepeatMode.OFF: btn.modulate = Color(1, 1, 1)
			RepeatMode.ALL: btn.modulate = Color(1, 1, 0)
			RepeatMode.ONE: btn.modulate = Color(1, 0.5, 0)

	if data.has("last_playlist"):
		for path in data["last_playlist"]:
			if FileAccess.file_exists(path):
				tracks.append(path)
		_refresh_playlist()
		if not tracks.is_empty():
			var saved_index = int(data.get("last_index", 0))
			# Kaydedilen index hala geçerli mi kontrol et
			var safe_index = clamp(saved_index, 0, tracks.size() - 1)
			_load_track(safe_index, false)
