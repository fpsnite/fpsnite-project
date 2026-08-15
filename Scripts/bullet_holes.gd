class_name BulletHoles
extends Node3D
## Pooled Decal bullet holes. `spawn(at, normal)` reuses the next decal from
## a fixed pool: it orients along the surface normal, rotates randomly so
## repeated hits don't align, and fades it out over FADE_TIME after
## BULLET_HOLE_LIFE. The albedo texture is generated at runtime (a soft-edged
## dark scorch), so no image assets are needed.

const POOL_SIZE := 24
const DECAL_SIZE := Vector3(0.12, 0.12, 0.5)
## How far the decal hovers off the surface (z-fighting avoidance).
const SURFACE_OFFSET := 0.03
const BULLET_HOLE_LIFE := 6.0
const FADE_TIME := 1.2

var _holes: Array[Decal] = []
var _index := 0
var _texture: Texture2D

func _ready() -> void:
	_texture = _make_hole_texture()
	for i in POOL_SIZE:
		var decal := Decal.new()
		decal.texture_albedo = _texture
		decal.size = DECAL_SIZE
		decal.modulate = Color(1, 1, 1, 0)
		decal.visible = false
		add_child(decal)
		_holes.append(decal)

## Places the next pooled hole at the impact point, facing the surface.
func spawn(at: Vector3, normal: Vector3) -> void:
	if normal.is_zero_approx():
		return
	var decal := _holes[_index]
	_index = (_index + 1) % _holes.size()
	# Reusing a hole: kill its pending fade so it resets to full alpha.
	if decal.has_meta("fade_tween") and (decal.get_meta("fade_tween") as Tween).is_valid():
		(decal.get_meta("fade_tween") as Tween).kill()
	decal.visible = true
	decal.modulate = Color(1, 1, 1, 1)
	decal.global_position = at + normal * SURFACE_OFFSET
	var up := Vector3.UP
	if absf(normal.dot(up)) > 0.99:
		up = Vector3.RIGHT
	decal.look_at(at + normal, up)
	decal.rotate_object_local(Vector3.FORWARD, randf() * TAU)
	var tween := create_tween()
	decal.set_meta("fade_tween", tween)
	tween.tween_interval(BULLET_HOLE_LIFE)
	tween.tween_property(decal, "modulate:a", 0.0, FADE_TIME)
	tween.tween_callback(func() -> void: decal.visible = false)

## Soft-edged dark scorch on transparent background - no asset file needed.
func _make_hole_texture() -> Texture2D:
	var size := 64
	var half := size / 2.0
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in size:
		for x in size:
			var d: float = Vector2(x - half + 0.5, y - half + 0.5).length() / half
			if d >= 1.0:
				continue
			var alpha := 0.9 * (1.0 - smoothstep(0.55, 0.98, d))
			if d > 0.82:
				alpha *= 0.5
			image.set_pixel(x, y, Color(0.04, 0.035, 0.03, alpha))
	return ImageTexture.create_from_image(image)
