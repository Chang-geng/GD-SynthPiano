extends Button

@export var semitone: int = 0
@export var audio_player: AudioStreamPlayer
var action_name=""

func _ready():
	action_name="note_"+str(semitone)

func _on_button_down() -> void:
	set_pressed_no_signal(true)
	if audio_player and audio_player.has_method("note_on"):
		audio_player.note_on(semitone)

func _on_button_up() -> void:
	set_pressed_no_signal(false)
	if audio_player and audio_player.has_method("note_off"):
		audio_player.note_off(semitone)

func _input(event: InputEvent) -> void:
	if action_name=="" or not event.is_action(action_name):
		return
	if event.is_action_pressed(action_name) and not event.is_echo():
		_on_button_down()
	elif event.is_action_released(action_name):
		_on_button_up()

func _on_mouse_exited() -> void:
	if is_pressed():
		_on_button_up()
