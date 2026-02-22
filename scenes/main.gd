extends Control

# ── Durum değişkenleri ─────────────────────────────────────────────────
var tracks: Array[String] = []
var current_index: int     = 0
var user_dragging: bool    = false
var shuffle_on: bool       = false
var is_muted: bool         = false
var pre_mute_volume: float = 80.0

enum RepeatMode { OFF, ALL, ONE }
var repeat_mode = RepeatMode.OFF

# ── Texture önbelleği ──────────────────────────────────────────────────
var _tex_play: Texture2D        = preload("res://assets/ui/graphics/PlayBtnFull.png")
var _tex_stop: Texture2D        = preload("res://assets/ui/graphics/StopBtnFull.png")
var _tex_shuffle_on: Texture2D  = preload("res://assets/ui/graphics/ShuffleBtnPressFull.png")
var _tex_repeat_all: Texture2D  = preload("res://assets/ui/graphics/RepeatBtnPressFull.png")
var _tex_repeat_one: Texture2D  = preload("res://assets/ui/graphics/RepeatTrackBtnPressFull.png")
var _tex_shuffle_off: Texture2D
var _tex_repeat_off: Texture2D

# ── Node referansları ──────────────────────────────────────────────────
@onready var audio_player   = $AudioStreamPlayer
@onready var seek_timer     = $SeekTimer
@onready var file_dialog    = $FileDialog
@onready var folder_dialog  = $FolderDialog

@onready var seek_slider    = $PlayerBackground/MainLayout/SeekBar/SeekSlider
@onready var elapsed_label  = $PlayerBackground/MainLayout/SeekBar/ElapsedLabel
@onready var total_label    = $PlayerBackground/MainLayout/SeekBar/TotalLabel

@onready var volume_slider  = $PlayerBackground/MainLayout/VolumeBar/VolumeSlider
@onready var mute_btn       = $PlayerBackground/MainLayout/VolumeBar/MuteBtn

@onready var track_name     = $PlayerBackground/MainLayout/TrackName
@onready var artist_name    = $PlayerBackground/MainLayout/ArtistName

@onready var minimize_btn   = $PlayerBackground/MainLayout/TopBar/MinimizeBtn
@onready var close_btn      = $PlayerBackground/MainLayout/TopBar/CloseBtn

@onready var shuffle_btn    = $PlayerBackground/MainLayout/ControlBar/ShuffleBtn
@onready var prev_btn       = $PlayerBackground/MainLayout/ControlBar/PrevBtn
@onready var play_pause_btn = $PlayerBackground/MainLayout/ControlBar/PlayPauseBtn
@onready var next_btn       = $PlayerBackground/MainLayout/ControlBar/NextBtn
@onready var repeat_btn     = $PlayerBackground/MainLayout/ControlBar/RepeatBtn

@onready var tracklist      = $TrackListPanel/TrackList
@onready var add_file_btn   = $PlaylistControlsPanel/PlaylistControls/AddFileBtn
@onready var add_folder_btn = $PlaylistControlsPanel/PlaylistControls/AddFolderBtn
@onready var remove_btn     = $PlaylistControlsPanel/PlaylistControls/RemoveBtn


# ── Başlangıç ──────────────────────────────────────────────────────────
func _ready() -> void:
	get_tree().auto_accept_quit = false

	# Normal texture'ları editördeki hallerinden sakla
	_tex_shuffle_off = shuffle_btn.texture_normal
	_tex_repeat_off  = repeat_btn.texture_normal

	# Pencere
	minimize_btn.pressed.connect(_on_minimize)
	close_btn.pressed.connect(_on_close)

	# TopBar sürükleme
	var topbar = $PlayerBackground/MainLayout/TopBar
	topbar.gui_input.connect(_on_topbar_input)

	# Playback
	play_pause_btn.pressed.connect(_on_play_pause_pressed)
	prev_btn.pressed.connect(_on_prev_pressed)
	next_btn.pressed.connect(_on_next_pressed)
	shuffle_btn.pressed.connect(_on_shuffle_pressed)
	repeat_btn.pressed.connect(_on_repeat_pressed)
	audio_player.finished.connect(_on_track_finished)

	# Seek
	seek_slider.drag_started.connect(_on_seek_drag_started)
	seek_slider.drag_ended.connect(_on_seek_drag_ended)
	seek_timer.timeout.connect(_on_seek_timer_timeout)
	seek_slider.max_value = 100

	# Volume
	volume_slider.value_changed.connect(_on_volume_changed)
	mute_btn.pressed.connect(_on_mute_pressed)
	volume_slider.value = 80.0

	# Playlist
	add_file_btn.pressed.connect(_on_add_file_pressed)
	add_folder_btn.pressed.connect(_on_add_folder_pressed)
	remove_btn.pressed.connect(_on_remove_pressed)
	tracklist.item_selected.connect(_on_track_selected)
	file_dialog.files_selected.connect(_on_file_dialog_files_selected)
	folder_dialog.dir_selected.connect(_on_folder_dialog_dir_selected)

	# FileDialog filtreleri
	file_dialog.filters     = PackedStringArray(["*.mp3 ; MP3 Files"])
	file_dialog.file_mode   = FileDialog.FILE_MODE_OPEN_FILES
	folder_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR

	# Başlangıç UI
	elapsed_label.text = "00:00"
	total_label.text   = "00:00"
	track_name.text    = "Cadenza"
	artist_name.text   = "Bir parça ekle"

	seek_timer.start()
	_load_config()


# ── Pencere sürükleme ──────────────────────────────────────────────────
func _on_topbar_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			DisplayServer.window_start_drag()


# ── Parça yükleme ──────────────────────────────────────────────────────
func _load_track(index: int, autoplay: bool = true) -> void:
	current_index = index

	var stream      = AudioStreamMP3.new()
	stream.data     = FileAccess.get_file_as_bytes(tracks[index])
	audio_player.stream = stream

	track_name.text   = tracks[index].get_file().get_basename()
	artist_name.text  = ""
	total_label.text  = _format_time(stream.get_length())
	seek_slider.value = 0.0

	if autoplay:
		audio_player.play()

	tracklist.select(index)
	_refresh_play_button()


func _refresh_play_button() -> void:
	var is_paused = audio_player.stream_paused or not audio_player.playing
	play_pause_btn.texture_normal = _tex_play if is_paused else _tex_stop


func _refresh_repeat_button() -> void:
	match repeat_mode:
		RepeatMode.OFF: repeat_btn.texture_normal = _tex_repeat_off
		RepeatMode.ALL: repeat_btn.texture_normal = _tex_repeat_all
		RepeatMode.ONE: repeat_btn.texture_normal = _tex_repeat_one


# ── Playback kontrolleri ───────────────────────────────────────────────
func _on_play_pause_pressed() -> void:
	if audio_player.stream_paused:
		audio_player.stream_paused = false
	elif audio_player.playing:
		audio_player.stream_paused = true
	else:
		if not tracks.is_empty():
			_load_track(current_index)
	_refresh_play_button()


func _on_prev_pressed() -> void:
	if tracks.is_empty():
		return
	if audio_player.get_playback_position() > 3.0:
		audio_player.seek(0.0)
	else:
		_load_track((current_index - 1 + tracks.size()) % tracks.size())


func _on_next_pressed() -> void:
	if not tracks.is_empty():
		_play_next()


func _on_track_finished() -> void:
	_play_next()


func _play_next() -> void:
	match repeat_mode:
		RepeatMode.ONE:
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
				else:
					audio_player.stop()
					_refresh_play_button()


# ── Seek ───────────────────────────────────────────────────────────────
func _on_seek_timer_timeout() -> void:
	if audio_player.playing and not audio_player.stream_paused and not user_dragging:
		var pos   = audio_player.get_playback_position()
		var total = audio_player.stream.get_length()
		seek_slider.value  = (pos / total) * 100.0
		elapsed_label.text = _format_time(pos)


func _on_seek_drag_started() -> void:
	user_dragging = true


func _on_seek_drag_ended(_value_changed: bool) -> void:
	user_dragging = false
	if audio_player.stream == null:
		return
	var total    = audio_player.stream.get_length()
	var seek_pos = (seek_slider.value / 100.0) * total
	audio_player.seek(seek_pos)


# ── Volume & Mute ──────────────────────────────────────────────────────
func _on_volume_changed(value: float) -> void:
	if not is_muted:
		audio_player.volume_db = linear_to_db(value / 100.0)


func _on_mute_pressed() -> void:
	is_muted = not is_muted
	if is_muted:
		pre_mute_volume        = volume_slider.value
		audio_player.volume_db = -80.0
		mute_btn.modulate      = Color(1, 0.4, 0.4)
	else:
		audio_player.volume_db = linear_to_db(pre_mute_volume / 100.0)
		mute_btn.modulate      = Color(1, 1, 1)


# ── Shuffle & Repeat ───────────────────────────────────────────────────
func _on_shuffle_pressed() -> void:
	shuffle_on = not shuffle_on
	shuffle_btn.texture_normal = _tex_shuffle_on if shuffle_on else _tex_shuffle_off


func _on_repeat_pressed() -> void:
	repeat_mode = (repeat_mode + 1) % 3
	_refresh_repeat_button()


# ── Playlist ───────────────────────────────────────────────────────────
func _on_add_file_pressed() -> void:
	file_dialog.popup_centered(Vector2(800, 600))


func _on_add_folder_pressed() -> void:
	folder_dialog.popup_centered(Vector2(800, 600))


func _on_file_dialog_files_selected(paths: PackedStringArray) -> void:
	var was_empty = tracks.is_empty()
	for path in paths:
		tracks.append(path)
	_refresh_playlist()
	if was_empty:
		_load_track(0)


func _on_folder_dialog_dir_selected(path: String) -> void:
	var dir = DirAccess.open(path)
	if dir == null:
		return
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


func _on_track_selected(index: int) -> void:
	_load_track(index)


func _on_remove_pressed() -> void:
	var selected = tracklist.get_selected_items()
	if selected.is_empty():
		return
	var index = selected[0]
	tracks.remove_at(index)
	_refresh_playlist()
	if index == current_index:
		audio_player.stop()
		_refresh_play_button()
		track_name.text  = "Cadenza"
		artist_name.text = "Bir parça ekle"
		total_label.text = "00:00"
	elif index < current_index:
		current_index -= 1


func _refresh_playlist() -> void:
	tracklist.clear()
	for i in tracks.size():
		tracklist.add_item(tracks[i].get_file().get_basename())


# ── Config ─────────────────────────────────────────────────────────────
func _save_config() -> void:
	var config = {
		"volume":        volume_slider.value,
		"shuffle":       shuffle_on,
		"repeat_mode":   repeat_mode,
		"last_playlist": tracks,
		"last_index":    current_index
	}
	var file = FileAccess.open("user://config.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(config))
	file.close()


func _load_config() -> void:
	if not FileAccess.file_exists("user://config.json"):
		return
	var file = FileAccess.open("user://config.json", FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if data == null:
		return

	if data.has("volume"):
		volume_slider.value = data["volume"]

	if data.has("shuffle"):
		shuffle_on = data["shuffle"]
		shuffle_btn.texture_normal = _tex_shuffle_on if shuffle_on else _tex_shuffle_off

	if data.has("repeat_mode"):
		repeat_mode = int(data["repeat_mode"])
		_refresh_repeat_button()

	if data.has("last_playlist"):
		for path in data["last_playlist"]:
			if FileAccess.file_exists(path):
				tracks.append(path)
		_refresh_playlist()
		if not tracks.is_empty():
			var saved_index = int(data.get("last_index", 0))
			_load_track(clamp(saved_index, 0, tracks.size() - 1), false)


# ── Yardımcı ───────────────────────────────────────────────────────────
func _format_time(seconds: float) -> String:
	var m: int = int(seconds) / 60
	var s: int = int(seconds) % 60
	return "%02d:%02d" % [m, s]


func _on_minimize() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)


func _on_close() -> void:
	_save_config()
	get_tree().quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_config()
		get_tree().quit()
