/*
	Original Wall Shield Shader by KINOMOTO Yui
	Modified by Silderán for Godot 4.4

	MIT License
*/

shader_type spatial;
render_mode unshaded, depth_draw_never, world_vertex_coords;

// set the width and height of the mesh. So que hexagons will be rendered fine.
uniform float width = 15.0;
uniform float height = 15.0;
// The densoty of hex on the barrier.
uniform float density = 5.0;
// Set it to false and the grid will only be visible along with background.
uniform bool hex_allways_visible = true;

uniform float line_speed = 0.5;
uniform float ripple_speed = 1.0;

uniform vec4 line_color : source_color = vec4( 0.2, 1.0, 1.0, 1.0 );
uniform vec4 ripple_color : source_color = vec4( 0.6, 0.7, 1.0, 0.7 );
uniform vec4 surface_color : source_color = vec4( 0.01, 0.18, 0.7, 0.4 );

// This must be set to the number of global positions set in the poss[] array in GDScript
uniform int cant_poss : hint_range(0, 64, 1);
// This is the vec3 array for the global possitions of the objects that will interact with the barrier.
// the length of the array must be harcoded. There os no option to set it dinamically
uniform vec3 poss[64];

varying vec3 world_vertex;

float hex_cells( vec2 uv )
{
	float x = uv.x * width * density;
	float y = mod( floor(x), 2.0 ) * 0.5 + ( uv.y * height ) * density;

	vec2 base_chip = abs( vec2( 0.5 ) - mod( vec2( x, y ), 1.0 ) );
	return abs( max( base_chip.x * 1.5 + base_chip.y, base_chip.y * 2.0 ) - 1.0 );
}
void vertex()
{
	world_vertex = VERTEX;
}

void fragment( )
{
	float hex = hex_cells( UV );

	vec3 final_line_color = clamp( line_color.rgb + ( fract( length( UV * min(height, width) * 0.5 ) + TIME * line_speed ) * 2.0 - 1.0 ), vec3( 0.0 ), vec3( 1.0 ) );

	float ripple = float( abs( hex - mod( -TIME * ripple_speed, 1.0 ) ) * 5.0 < 0.2 );

	vec4 final = mix(
		mix(
			surface_color
		,	ripple_color
		,	ripple
		)
	,	vec4( final_line_color, 1.0 )
	,	float( hex < 0.02 )
	);

	if( !hex_allways_visible || (hex > 0.01) )
	{
		float newAlpha = 0.0;
		for( int i = min(cant_poss, poss.length())-1; i >= 0; i--)
		{
			float dist = length(world_vertex - poss[i]);
			newAlpha = max(newAlpha, clamp(1.0 - dist * 0.3, 0.0, 1.0) * 1.3);
		}
		ALPHA = newAlpha;
	}
	ALBEDO = final.rgb;
}