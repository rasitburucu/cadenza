extends Control

# ── Durum değişkenleri ─────────────────────────────────────────────────
var tracks: Array[String]  = []
var current_index: int     = 0
var user_dragging: bool    = false
var shuffle_on: bool       = false
var is_muted: bool         = false
var pre_mute_volume: float = 80.0
var always_on_top: bool    = false
var last_elapsed_sec: int  = -1

# Marquee (Kayan Yazı) değişkenleri
var original_track_name: String = ""
var needs_marquee: bool         = false
var marquee_timer: float        = 0.0
const MARQUEE_SPEED: float      = 0.2
const MARQUEE_LIMIT: int        = 28

enum RepeatMode { OFF, ALL, ONE }
var repeat_mode: RepeatMode = RepeatMode.OFF

# YouTube İndirme ve UI Değişkenleri
var download_thread: Thread
var yt_dialog: ConfirmationDialog
var yt_line_edit: LineEdit

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

	_tex_shuffle_off = shuffle_btn.texture_normal
	_tex_repeat_off  = repeat_btn.texture_normal

	# UI TAŞMA (OVERFLOW) DÜZELTMESİ
	track_name.clip_text = true
	artist_name.clip_text = true
	track_name.custom_minimum_size.x = 1
	artist_name.custom_minimum_size.x = 1

	# Başlangıç UI
	elapsed_label.text = "00:00"
	total_label.text   = "00:00"
	track_name.text    = "Cadenza"
	artist_name.text   = "Bir parça ekle"
	DisplayServer.window_set_title("Cadenza")
	
	seek_slider.max_value = 100.0
	seek_slider.step = 0.01
	volume_slider.value = 80.0

	_setup_signals()
	_bind_button_animations()
	_load_config()


func _setup_signals() -> void:
	minimize_btn.pressed.connect(_on_minimize)
	close_btn.pressed.connect(_on_close)
	
	$PlayerBackground/MainLayout/TopBar.gui_input.connect(_on_topbar_input)
	get_window().files_dropped.connect(_on_files_dropped)

	play_pause_btn.pressed.connect(_on_play_pause_pressed)
	prev_btn.pressed.connect(_on_prev_pressed)
	next_btn.pressed.connect(_on_next_pressed)
	shuffle_btn.pressed.connect(_on_shuffle_pressed)
	repeat_btn.pressed.connect(_on_repeat_pressed)
	audio_player.finished.connect(_on_track_finished)

	seek_slider.drag_started.connect(_on_seek_drag_started)
	seek_slider.drag_ended.connect(_on_seek_drag_ended)

	volume_slider.value_changed.connect(_on_volume_changed)
	volume_slider.gui_input.connect(_on_volume_scroll)
	mute_btn.pressed.connect(_on_mute_pressed)

	# Akıllı Butonlar
	add_file_btn.pressed.connect(_on_youtube_smart_pressed)
	add_folder_btn.gui_input.connect(_on_smart_local_input)
	remove_btn.pressed.connect(_on_remove_pressed)
	
	# Tracklist - Tek ve Çift tık desteği
	tracklist.item_activated.connect(_on_track_activated)
	tracklist.item_selected.connect(_on_track_activated)


# ── Sürekli Akış (Frame-based Update & Marquee) ────────────────────────
func _process(delta: float) -> void:
	if needs_marquee:
		marquee_timer += delta
		if marquee_timer >= MARQUEE_SPEED:
			marquee_timer = 0.0
			var current_text = track_name.text
			track_name.text = current_text.substr(1, current_text.length() - 1) + current_text[0]

	if audio_player.stream == null:
		return
		
	if audio_player.playing and not audio_player.stream_paused and not user_dragging:
		var total = audio_player.stream.get_length()
		if total > 0.0:
			var pos = audio_player.get_playback_position()
			seek_slider.value = (pos / total) * 100.0
			
			var current_sec = int(pos)
			if current_sec != last_elapsed_sec:
				last_elapsed_sec = current_sec
				elapsed_label.text = _format_time(pos)


# ── Dinamik Tween Animasyon Motoru ─────────────────────────────────────
func _bind_button_animations() -> void:
	await get_tree().process_frame 
	
	var interactive_buttons = [
		play_pause_btn, prev_btn, next_btn, shuffle_btn, repeat_btn, 
		mute_btn, minimize_btn, close_btn, add_file_btn, add_folder_btn, remove_btn
	]
	
	for btn in interactive_buttons:
		if btn == null: continue
		btn.pivot_offset = btn.size / 2.0
		
		btn.button_down.connect(func(): _animate_node(btn, Vector2(0.85, 0.85), 0.1))
		btn.button_up.connect(func(): _animate_node(btn, Vector2(1.05, 1.05), 0.15))
		btn.mouse_entered.connect(func(): _animate_node(btn, Vector2(1.05, 1.05), 0.15))
		btn.mouse_exited.connect(func(): _animate_node(btn, Vector2(1.0, 1.0), 0.2))

func _animate_node(node: Node, target_scale: Vector2, duration: float) -> void:
	var tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "scale", target_scale, duration)


# ── Keyboard & Media Shortcuts ─────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return

	match event.keycode:
		KEY_SPACE, KEY_MEDIAPLAY:
			_on_play_pause_pressed()
		KEY_MEDIANEXT, KEY_N:
			_on_next_pressed()
		KEY_MEDIAPREVIOUS, KEY_P:
			_on_prev_pressed()
		KEY_MEDIASTOP:
			audio_player.stop()
			_refresh_play_button()
		KEY_LEFT:
			if audio_player.stream != null:
				var pos = max(0.0, audio_player.get_playback_position() - 5.0)
				audio_player.seek(pos)
		KEY_RIGHT:
			if audio_player.stream != null:
				var total = audio_player.stream.get_length()
				var pos   = min(total, audio_player.get_playback_position() + 5.0)
				audio_player.seek(pos)
		KEY_M:
			_on_mute_pressed()


# ── Pencere Sürükleme ──────────────────────────────────────────────────
func _on_topbar_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			DisplayServer.window_start_drag()


# ── Parça Yükleme ──────────────────────────────────────────────────────
func _load_track(index: int, autoplay: bool = true) -> void:
	current_index = index
	last_elapsed_sec = -1

	var stream  = AudioStreamMP3.new()
	stream.data = FileAccess.get_file_as_bytes(tracks[index])
	audio_player.stream = stream

	var basename = tracks[index].get_file().get_basename()
	if " - " in basename:
		var parts = basename.split(" - ", true, 1)
		artist_name.text = parts[0].strip_edges()
		original_track_name = parts[1].strip_edges()
	else:
		original_track_name = basename.strip_edges()
		artist_name.text = ""

	if original_track_name.length() > MARQUEE_LIMIT:
		needs_marquee = true
		track_name.text = original_track_name + "   •   "
	else:
		needs_marquee = false
		track_name.text = original_track_name

	total_label.text  = _format_time(stream.get_length())
	seek_slider.value = 0.0
	elapsed_label.text = "00:00"

	if autoplay:
		audio_player.play()

	tracklist.select(index)
	tracklist.ensure_current_is_visible()
	
	_refresh_play_button()
	DisplayServer.window_set_title("Cadenza - " + original_track_name)


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
	if tracks.is_empty(): return
	if audio_player.get_playback_position() > 3.0:
		audio_player.seek(0.0)
	else:
		_load_track((current_index - 1 + tracks.size()) % tracks.size())

func _on_next_pressed() -> void:
	if not tracks.is_empty(): _play_next(true)

func _on_track_finished() -> void:
	_play_next(false)

func _play_next(force_next: bool = false) -> void:
	if force_next:
		if shuffle_on: _load_track(randi() % tracks.size())
		else: _load_track((current_index + 1) % tracks.size())
		return

	match repeat_mode:
		RepeatMode.ONE:
			_load_track(current_index)
		RepeatMode.ALL:
			if shuffle_on: _load_track(randi() % tracks.size())
			else: _load_track((current_index + 1) % tracks.size())
		RepeatMode.OFF:
			if shuffle_on: _load_track(randi() % tracks.size())
			else:
				var next = current_index + 1
				if next < tracks.size(): _load_track(next)
				else:
					audio_player.stop()
					_refresh_play_button()


# ── Seek Kontrolleri ───────────────────────────────────────────────────
func _on_seek_drag_started() -> void:
	user_dragging = true

func _on_seek_drag_ended(_value_changed: bool) -> void:
	user_dragging = false
	if audio_player.stream == null: return
	var total    = audio_player.stream.get_length()
	var seek_pos = (seek_slider.value / 100.0) * total
	audio_player.seek(seek_pos)
	elapsed_label.text = _format_time(seek_pos)
	last_elapsed_sec = int(seek_pos)


# ── Volume & Mute ──────────────────────────────────────────────────────
func _on_volume_changed(value: float) -> void:
	if not is_muted:
		audio_player.volume_db = linear_to_db(value / 100.0)

func _on_volume_scroll(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			volume_slider.value = min(100.0, volume_slider.value + 5.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			volume_slider.value = max(0.0, volume_slider.value - 5.0)

func _on_mute_pressed() -> void:
	is_muted = not is_muted
	if is_muted:
		pre_mute_volume        = 80.0 if volume_slider.value <= 1.0 else volume_slider.value
		audio_player.volume_db = -80.0
		mute_btn.modulate      = Color(1, 0.4, 0.4)
	else:
		volume_slider.value    = pre_mute_volume
		audio_player.volume_db = linear_to_db(pre_mute_volume / 100.0)
		mute_btn.modulate      = Color(1, 1, 1)


# ── Shuffle & Repeat ───────────────────────────────────────────────────
func _on_shuffle_pressed() -> void:
	shuffle_on = not shuffle_on
	shuffle_btn.texture_normal = _tex_shuffle_on if shuffle_on else _tex_shuffle_off

func _on_repeat_pressed() -> void:
	repeat_mode = ((repeat_mode + 1) % 3) as RepeatMode
	_refresh_repeat_button()


# ── YOUTUBE PANO (CLIPBOARD) VE İNDİRME MOTORU ─────────────────────────
func _get_base_dir() -> String:
	# Eğer uygulaman Godot Editörünün içinde çalışıyorsa (Test)
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://")
	# Eğer uygulaman Editörde DEĞİLSE (Yani bir .exe isek)
	else:
		return OS.get_executable_path().get_base_dir()

func _on_youtube_smart_pressed() -> void:
	var clipboard_text = DisplayServer.clipboard_get().strip_edges()
	
	if clipboard_text.begins_with("https://www.youtube.com/") or clipboard_text.begins_with("https://youtu.be/"):
		_start_youtube_download(clipboard_text)
	else:
		_show_youtube_popup()

func _show_youtube_popup() -> void:
	if yt_dialog == null:
		yt_dialog = ConfirmationDialog.new()
		yt_dialog.title = "YouTube'dan İndir"
		yt_dialog.dialog_text = "Videonun linkini yapıştırın:"
		yt_dialog.confirmed.connect(_on_youtube_popup_confirmed)
		
		yt_line_edit = LineEdit.new()
		yt_line_edit.placeholder_text = "https://www.youtube.com/..."
		yt_line_edit.custom_minimum_size.x = 300
		yt_dialog.add_child(yt_line_edit)
		
		add_child(yt_dialog)
	
	yt_line_edit.text = ""
	yt_dialog.popup_centered()
	yt_line_edit.grab_focus()

func _on_youtube_popup_confirmed() -> void:
	var url = yt_line_edit.text.strip_edges()
	if url != "":
		_start_youtube_download(url)

func _start_youtube_download(url: String) -> void:
	if download_thread != null and download_thread.is_alive():
		print("Zaten bir indirme işlemi sürüyor!")
		return
		
	var base_dir = _get_base_dir()
	var bin_dir = base_dir + "/bin"
	var dl_dir = base_dir + "/downloads"
	
	var dir = DirAccess.open(base_dir)
	if not dir.dir_exists(dl_dir):
		dir.make_dir("downloads")
		
	var ytdlp_path = bin_dir + "/yt-dlp.exe"
	
	# İŞTE BURASI KÖR UÇUŞU BİTİREN VE HATAYI EKRANA BASAN KISIM
	if not FileAccess.file_exists(ytdlp_path):
		var error_msg = "KRİTİK HATA: yt-dlp.exe bulunamadı!\nŞu klasörde arandı: " + ytdlp_path
		OS.alert(error_msg, "Eksik Dosya veya Klasör")
		return

	print("İndirme başladı: ", url)
	download_thread = Thread.new()
	download_thread.start(_run_ytdlp_thread.bind(ytdlp_path, bin_dir, dl_dir, url))

func _run_ytdlp_thread(ytdlp_path: String, bin_dir: String, dl_dir: String, url: String) -> void:
	var args = [
		"--ffmpeg-location", bin_dir,
		"-x", 
		"--audio-format", "mp3", 
		"--audio-quality", "0", 
		"--output", dl_dir + "/%(title)s.%(ext)s", 
		"--no-playlist", 
		url
	]
	var output = []
	var exit_code = OS.execute(ytdlp_path, args, output, true)
	call_deferred("_on_download_finished", exit_code, output, dl_dir)

func _on_download_finished(exit_code: int, output: Array, dl_dir: String) -> void:
	download_thread.wait_to_finish()
	
	if exit_code == 0:
		print("İndirme başarılı! Kütüphaneye ekleniyor...")
		var was_empty = tracks.is_empty()
		
		await _scan_folder_recursive(dl_dir)
		_refresh_playlist()
		
		if was_empty and not tracks.is_empty():
			_load_track(0)
	else:
		print("İndirme başarısız! Hata kodu: ", exit_code)
		if output.size() > 0: print(output[0])


# ── AKILLI YEREL MEDYA SEÇİCİ ──────────────────────────────────────────
func _on_smart_local_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			DisplayServer.file_dialog_show(
				"MP3 Dosyalarını Seç", "", "", false, 
				DisplayServer.FILE_DIALOG_MODE_OPEN_FILES, 
				PackedStringArray(["*.mp3"]), _on_native_files_selected
			)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			DisplayServer.file_dialog_show(
				"Müzik Klasörünü Seç", "", "", false, 
				DisplayServer.FILE_DIALOG_MODE_OPEN_DIR, 
				PackedStringArray(), _on_native_folder_selected
			)

func _on_native_files_selected(status: bool, selected_paths: PackedStringArray, _filter_index: int) -> void:
	if not status or selected_paths.is_empty(): return
	var was_empty = tracks.is_empty()
	for path in selected_paths:
		if not tracks.has(path): tracks.append(path)
	_refresh_playlist()
	if was_empty and not tracks.is_empty(): _load_track(0)

func _on_native_folder_selected(status: bool, selected_paths: PackedStringArray, _filter_index: int) -> void:
	if not status or selected_paths.is_empty(): return
	var was_empty = tracks.is_empty()
	await _scan_folder_recursive(selected_paths[0])
	_refresh_playlist()
	if was_empty and not tracks.is_empty(): _load_track(0)


# ── Anti-Donma (Anti-Freeze) Klasör Tarayıcı ───────────────────────────
func _scan_folder_recursive(path: String) -> void:
	var dir = DirAccess.open(path)
	if dir == null: return
		
	dir.list_dir_begin()
	var file_name = dir.get_next()
	var iterations = 0
	
	while file_name != "":
		if file_name == "." or file_name == "..":
			file_name = dir.get_next()
			continue
			
		var full_path = path + "/" + file_name
		if dir.current_is_dir():
			await _scan_folder_recursive(full_path)
		elif file_name.to_lower().ends_with(".mp3"):
			if not tracks.has(full_path): tracks.append(full_path)
		
		iterations += 1
		if iterations % 50 == 0: await get_tree().process_frame
		file_name = dir.get_next()
		
	dir.list_dir_end()


# ── Liste ve Sürükle-Bırak Yönetimi ────────────────────────────────────
func _on_files_dropped(files: PackedStringArray) -> void:
	var was_empty = tracks.is_empty()
	for path in files:
		var dir = DirAccess.open(path)
		if dir != null:
			await _scan_folder_recursive(path)
		elif path.to_lower().ends_with(".mp3"):
			if not tracks.has(path): tracks.append(path)
				
	_refresh_playlist()
	if was_empty and not tracks.is_empty(): _load_track(0)

func _on_track_activated(index: int) -> void:
	_load_track(index)

func _on_remove_pressed() -> void:
	var selected = tracklist.get_selected_items()
	if selected.is_empty(): return
	var index = selected[0]
	tracks.remove_at(index)
	_refresh_playlist()
	
	if index == current_index:
		audio_player.stop()
		_refresh_play_button()
		track_name.text  = "Cadenza"
		artist_name.text = "Bir parça ekle"
		total_label.text = "00:00"
		needs_marquee = false
		DisplayServer.window_set_title("Cadenza")
	elif index < current_index:
		current_index -= 1

func _refresh_playlist() -> void:
	tracklist.clear()
	for i in tracks.size():
		var basename = tracks[i].get_file().get_basename()
		tracklist.add_item(basename)


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
	if not FileAccess.file_exists("user://config.json"): return
	var file = FileAccess.open("user://config.json", FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if data == null: return

	if data.has("volume"): volume_slider.value = data["volume"]
	if data.has("shuffle"):
		shuffle_on = data["shuffle"]
		shuffle_btn.texture_normal = _tex_shuffle_on if shuffle_on else _tex_shuffle_off
	if data.has("repeat_mode"):
		repeat_mode = int(data["repeat_mode"]) as RepeatMode
		_refresh_repeat_button()

	if data.has("last_playlist"):
		for path in data["last_playlist"]:
			if FileAccess.file_exists(path): tracks.append(path)
		_refresh_playlist()
		if not tracks.is_empty():
			var saved_index = int(data.get("last_index", 0))
			_load_track(clamp(saved_index, 0, tracks.size() - 1), false)


# ── Yardımcı ───────────────────────────────────────────────────────────
func _format_time(seconds: float) -> String:
	var m: int = floori(seconds / 60.0)
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
