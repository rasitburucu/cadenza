extends Control

var tracks: Array[String] = [
	"res://assets/music/Dead Skin Mask.mp3",
	"res://assets/music/Excessive Funeral.mp3",
    "res://assets/music/Sünger Bob Tema Müziği.mp3"
]
var current_index: int = 0
var user_dragging: bool = false


func _ready():
	_load_track(current_index)
	$SeekTimer.start()
	$VBoxContainer/VolumeSlider.value = 80.0
	$VBoxContainer/ControlRow/PlayPauseButton.text = "⏸"


# ─────────────────────────────────────────
# PARÇA YÜKLEME
# ─────────────────────────────────────────
func _load_track(index: int):
	current_index = index
	var file = FileAccess.open(tracks[index], FileAccess.READ)
	var stream = AudioStreamMP3.new()
	stream.data = file.get_buffer(file.get_length())
	$AudioStreamPlayer.stream = stream
	$AudioStreamPlayer.play()
	$VBoxContainer/TrackTitle.text = tracks[index].get_file().get_basename()
	$VBoxContainer/TimeRow/DurationLabel.text = _format_time(stream.get_length())
	$VBoxContainer/SeekBar.value = 0.0


# ─────────────────────────────────────────
# PLAY / PAUSE
# ─────────────────────────────────────────
func _on_play_pause_button_pressed():
	if not $AudioStreamPlayer.playing:
		$AudioStreamPlayer.play()
	else:
		$AudioStreamPlayer.stream_paused = not $AudioStreamPlayer.stream_paused
	_refresh_play_button()

func _refresh_play_button():
	var is_paused = $AudioStreamPlayer.stream_paused or not $AudioStreamPlayer.playing
	$VBoxContainer/ControlRow/PlayPauseButton.text = "▶" if is_paused else "⏸"


# ─────────────────────────────────────────
# STOP
# ─────────────────────────────────────────
func _on_stop_button_pressed():
	$AudioStreamPlayer.stop()
	$VBoxContainer/SeekBar.value = 0.0
	$VBoxContainer/TimeRow/ElapsedLabel.text = "00:00"
	_refresh_play_button()


# ─────────────────────────────────────────
# SEEK BAR
# ─────────────────────────────────────────
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


# ─────────────────────────────────────────
# VOLUME
# ─────────────────────────────────────────
func _on_volume_slider_value_changed(value: float):
	$AudioStreamPlayer.volume_db = linear_to_db(value / 100.0)


# ─────────────────────────────────────────
# PREVIOUS / NEXT
# ─────────────────────────────────────────
func _on_prev_button_pressed():
	_load_track((current_index - 1 + tracks.size()) % tracks.size())

func _on_next_button_pressed():
	_load_track((current_index + 1) % tracks.size())


# ─────────────────────────────────────────
# YARDIMCI
# ─────────────────────────────────────────
func _format_time(seconds: float) -> String:
	var m: int = int(seconds) / 60
	var s: int = int(seconds) % 60
	return "%02d:%02d" % [m, s]
