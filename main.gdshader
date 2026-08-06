shader_type canvas_item;

uniform vec4 shine_color=vec4(0.0, 0.7, 1.0, 1.0);
uniform float shine_speed:hint_range(0.0, 10.0)=1.0;
uniform float shine_width:hint_range(0.0, 1.0)=0.05;
uniform float shine_tilt:hint_range(-1.0, 1.0)=0.5;
uniform float shine_frequency:hint_range(0.1, 10.0)=3.0;
uniform float shine_softness:hint_range(0.0, 1.0)=0.5;
uniform float bg_brightness:hint_range(0.0, 2.0)=0.5;

void fragment(){
	vec4 old_color=texture(TEXTURE,UV);
	vec3 bg_color=old_color.rgb*bg_brightness;
	float time_cycle=mod(TIME*shine_speed,shine_frequency);
	float adjusted_time=(time_cycle*2.0)-1.0-(shine_width+abs(shine_tilt));
	float slope_pos=UV.x-adjusted_time+(UV.y*shine_tilt);
	float shine_factor=smoothstep(0.0,shine_softness,slope_pos)*(1.0-smoothstep(shine_width-shine_softness,shine_width,slope_pos));
	shine_factor=clamp(shine_factor,0.0,1.0);
	vec3 final_rgb=bg_color.rgb+(shine_color.rgb*shine_color.a*shine_factor*old_color.a);
	COLOR=vec4(final_rgb,old_color.a);
}