extends AudioStreamPlayer

enum WaveType { SAWTOOTH,SQUARE,TRIANGLE,SINE }

const ROOT_FREQUENCY=261.63
const RELEASE_TIME=0.08
const WAVE_NAMES={
	WaveType.SAWTOOTH: "锯齿波 (Sawtooth)",
	WaveType.SQUARE: "方波 (Square)",
	WaveType.TRIANGLE: "三角波 (Triangle)",
	WaveType.SINE: "正弦波 (Sine)"
}
const DEMO_SONGS={
	"欢乐颂": [
		{"note": 4, "duration": 0.5}, {"note": 4, "duration": 0.5},
		{"note": 5, "duration": 0.5}, {"note": 7, "duration": 0.5},
		{"note": 7, "duration": 0.5}, {"note": 5, "duration": 0.5},
		{"note": 4, "duration": 0.5}, {"note": 2, "duration": 0.5},
		{"note": 0, "duration": 0.5}, {"note": 0, "duration": 0.5},
		{"note": 2, "duration": 0.5}, {"note": 4, "duration": 0.5},
		{"note": 4, "duration": 0.75},{"note": 2, "duration": 0.25},
		{"note": 2, "duration": 1.0},
	],
	"两只老虎": [
		{"note": 0, "duration": 0.4}, {"note": 2, "duration": 0.4}, {"note": 4, "duration": 0.4}, {"note": 0, "duration": 0.4},
		{"note": 0, "duration": 0.4}, {"note": 2, "duration": 0.4}, {"note": 4, "duration": 0.4}, {"note": 0, "duration": 0.4},
		{"note": 4, "duration": 0.4}, {"note": 5, "duration": 0.4}, {"note": 7, "duration": 0.8},
		{"note": 4, "duration": 0.4}, {"note": 5, "duration": 0.4}, {"note": 7, "duration": 0.8},
		{"note": 7, "duration": 0.3}, {"note": 9, "duration": 0.3}, {"note": 7, "duration": 0.3}, {"note": 5, "duration": 0.3}, {"note": 4, "duration": 0.4}, {"note": 0, "duration": 0.4},
		{"note": 7, "duration": 0.3}, {"note": 9, "duration": 0.3}, {"note": 7, "duration": 0.3}, {"note": 5, "duration": 0.3}, {"note": 4, "duration": 0.4}, {"note": 0, "duration": 0.4},
		{"note": 2, "duration": 0.4}, {"note": -1, "duration": 0.1}, {"note": 7, "duration": 0.4}, {"note": 0, "duration": 0.8},
		{"note": 2, "duration": 0.4}, {"note": -1, "duration": 0.1}, {"note": 7, "duration": 0.4}, {"note": 0, "duration": 0.8},
	],
}

class Voice:
	var semitone:int
	var frequency:float
	var phase:float=0.0
	var is_releasing:bool=false
	var releaser_timer:float=0.0
	var amplitude:float=1.0
	var is_down:bool=true

var key_map:Dictionary={
	KEY_Z: 0,
	KEY_S: 1,
	KEY_X: 2,
	KEY_D: 3,
	KEY_C: 4,
	KEY_V: 5,
	KEY_G: 6,
	KEY_B: 7,
	KEY_H: 8,
	KEY_N: 9,
	KEY_J: 10,
	KEY_M: 11,
	KEY_Q: 12,
}
var voices:Dictionary={}
var playback:AudioStreamGeneratorPlayback=null
var current_wave:WaveType=WaveType.SAWTOOTH
var synth_bus_index=0
var reverb_enabled=false
var delay_enabled=false
var lowpassfilter_enabled=false
var octave_offset=0
var is_sustain_pressed=false
var is_playing_demo=false
var demo_cancelled=false
var current_demo_id=0
@export var wave_label:Label
@export var effect_label:Label
@export var octave_label:Label
@export var sustain_label:Label
@export var song_option_button:OptionButton

func _ready():
	play()
	playback=get_stream_playback()
	synth_bus_index=AudioServer.get_bus_index("SynthBus")   #godot音频系统用数组/列表管理所有音频总线
	_update_label()
	_init_song_option_button()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and not event.echo:
		#.echo内置属性，是否长按，下面的.keycode代表当前按键的逻辑键码
		if event.keycode==KEY_T and event.pressed:
			next_wave()
			return
		elif event.keycode==KEY_E and event.pressed:
			toggle_effect(1)
			return
		elif event.keycode==KEY_R and event.pressed:
			toggle_effect(2)
			return
		elif event.keycode==KEY_W and event.pressed:
			toggle_effect(0)
			return
		elif event.keycode==KEY_SPACE:
			set_sustain(event.pressed)
			return
		elif event.keycode==KEY_UP and event.pressed:
			change_octave(1)
			return
		elif event.keycode==KEY_DOWN and event.pressed:
			change_octave(-1)
			return
		elif event.keycode==KEY_ESCAPE:
			stop_demo()
			return
		
		if key_map.has(event.keycode) and is_playing_demo:
			stop_demo()
		
		var keycode=event.keycode
		if key_map.has(keycode):
			var semitone=key_map[keycode]
			if event.pressed:   #抬起也算是一个InputEventKey事件，所以加入.pressed进行判断
				note_on(semitone)
			else:
				note_off(semitone)

func note_on(semitone: int):
	var actual_semitone=semitone+(octave_offset*12)
	var frequency=ROOT_FREQUENCY*pow(2.0,actual_semitone/12.0)
	var voice=Voice.new()
	voice.semitone=actual_semitone
	voice.frequency=frequency
	voice.is_down=true
	voices[actual_semitone]=voice
	
func note_off(semitone: int):
	for pitch in voices:
		var voice=voices[pitch]
		if voice.is_down and (voice.semitone%12==semitone%12):
			voice.is_down=false
			if not is_sustain_pressed:
				voice.is_releasing=true

func _process(delta):
	if playback==null:
		return
	var frames_avaliable=playback.get_frames_available()
	if frames_avaliable==0:
		return

	var mix_rate=(stream as AudioStreamGenerator).mix_rate
	var sample_delta=1.0/mix_rate

	for i in frames_avaliable:
		var combined_sample:float=0.0
		var to_remove=[]

		for semitone in voices:
			var voice=voices[semitone]
			if voice.is_releasing:
				voice.releaser_timer+=sample_delta
				voice.amplitude=1-(voice.releaser_timer/RELEASE_TIME)
				if voice.amplitude<=0.0:
					to_remove.append(semitone)
					continue

			var step=voice.frequency/mix_rate
			voice.phase=fmod(step+voice.phase,1.0)
			var sample=0.0
			match current_wave:
				WaveType.SAWTOOTH:
					sample=sawtooth_wave(voice.phase)*voice.amplitude
				WaveType.SQUARE:
					sample=square_wave(voice.phase)*voice.amplitude
				WaveType.SINE:
					sample=sine_wave(voice.phase)*voice.amplitude
				WaveType.TRIANGLE:
					sample=triangle_wave(voice.phase)*voice.amplitude
			combined_sample+=sample

		for semitone in to_remove:
			voices.erase(semitone)

		if voices.size()>0:
			combined_sample/=max(1.0,sqrt(voices.size()))
			#防止剪切失真，在计算机音频处理中，数模转换器（DAC）能够处理的采样数值范围被限定在[-1.0, 1.0]之间，超过会被截断，根据均方根能量叠加法则：
			#当多个不相干（非同相位）的波形叠加在一起时，复合波形的实际有效能量大约是以sqrt{N}的比例增长的，而不是N倍。

		combined_sample*=0.65
		playback.push_frame(Vector2(combined_sample,combined_sample))

func sine_wave(phase:float):
	return sin(fmod(phase,1.0)*TAU)

func square_wave(phase:float):
	return 1.0 if(fmod(phase,1.0)<0.5) else -1

func sawtooth_wave(phase:float):
	return 2.0*fmod(phase,1.0)-1

func triangle_wave(phase):
	return 4.0*abs(fmod(phase,1.0)-0.5)-1.0

func next_wave():
	current_wave=((current_wave+1)%WaveType.size() as WaveType)
	_update_label()

func _update_label():
	if wave_label:   #防止为null，避免崩溃，下同
		wave_label.text="当前音色(T):"+WAVE_NAMES[current_wave]
	if effect_label:
		var rev_str="开" if reverb_enabled else "关"
		var del_str="开" if delay_enabled else "关"
		var low_str="开" if lowpassfilter_enabled else "关"
		effect_label.text="低通(W):"+low_str+"|  混响(E):"+rev_str+"  | 延迟(R):"+del_str
	if octave_label:
		var oct_str="八度(↑↓):%s%d" % ["+" if octave_offset>0 else "",octave_offset]
		#格式化字符串
		octave_label.text=oct_str
	if sustain_label:
		var sus_str="开" if is_sustain_pressed else "关"
		sustain_label.text="延音踏板(Space):"+sus_str

func toggle_effect(index:int):
	if synth_bus_index !=-1:
		var current_state=AudioServer.is_bus_effect_enabled(synth_bus_index,index)
		#询当前这个效果器是处于开启还是禁用状态，把结果存进current_state
		AudioServer.set_bus_effect_enabled(synth_bus_index,index,not current_state)
		
		if index==1:
			reverb_enabled=!current_state
		elif index==2:
			delay_enabled=!current_state
		elif index==0:
			lowpassfilter_enabled=!current_state
		
		_update_label()

func set_sustain(pressed:bool):
	is_sustain_pressed=pressed
	if not is_sustain_pressed:
		for pitch in voices:
			var voice=voices[pitch]
			if not voice.is_down:
				voice.is_releasing=true
	
	_update_label()

func change_octave(delta_octave:int):
	octave_offset=clamp(octave_offset+delta_octave,-3,3)
	_update_label()

func play_demo(song_name:String):
	if not DEMO_SONGS.has(song_name):
		return

	current_demo_id+=1
	var session_id=current_demo_id
	stop_demo()
	is_playing_demo=true
	demo_cancelled=false
	var notes=DEMO_SONGS[song_name]
	for item in notes:
		if demo_cancelled or current_demo_id!=session_id:
			break
		var semitone=item["note"]
		var duration=item["duration"]
		if semitone>=0:
			note_on(semitone)
			var gate_time=duration*0.96
			var rest_time=duration*0.04
			await get_tree().create_timer(gate_time).timeout
			if demo_cancelled or current_demo_id!=session_id:
				note_off(semitone)
				break
			note_off(semitone)
			await get_tree().create_timer(rest_time).timeout
		else:
			await get_tree().create_timer(duration).timeout
	
	if current_demo_id==session_id:
		is_playing_demo=false
		if song_option_button and not demo_cancelled:
			song_option_button.select(0)

func stop_demo():
	demo_cancelled=true
	is_playing_demo=false
	for pitch in voices.duplicate():
		var voice=voices[pitch]
		voice.is_down=false
		voice.is_releasing=true
	
	if song_option_button:
		song_option_button.select(0)

func _init_song_option_button():
	if song_option_button==null:
		return
	song_option_button.clear()
	song_option_button.add_item("选择自动播放曲目")
	for song_name in DEMO_SONGS.keys():
		song_option_button.add_item(song_name)

func _on_option_button_item_selected(index: int) -> void:
	if index==0:
		stop_demo()
		return
	var selected_song=song_option_button.get_item_text(index)
	play_demo(selected_song)
