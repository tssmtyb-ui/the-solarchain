class_name MapBoundaryFog
extends Node2D
## Renders an atmospheric isometric mist/fog boundary outside the playable grid.
##
## Every point inside the [0, grid_size] × [0, grid_size] isometric diamond has
## strictly 0.0 opacity so playable tiles, edge buildings, highlights, and
## tooltips remain 100% clear and interactive. Outside the perimeter, opacity
## smoothly ramps up over `fade_tiles` with subtle animated mist noise until the
## empty viewport void is completely obscured.

const DEFAULT_FADE_TILES: float = 4.5
const DEFAULT_NOISE_STRENGTH: float = 0.22
const DEFAULT_NOISE_SCALE: float = 0.38
const DEFAULT_WIND_VELOCITY: Vector2 = Vector2(0.18, 0.11)
const DEFAULT_INNER_FOG_COLOR: Color = Color(0.14, 0.19, 0.22, 0.94)
const DEFAULT_OUTER_FOG_COLOR: Color = Color(0.06, 0.08, 0.10, 1.0)
const OUTER_PADDING_TILES: float = 28.0

const BOUNDARY_FOG_SHADER_CODE: String = """
shader_type canvas_item;

uniform vec2 top_vertex = vec2(0.0, -128.0);
uniform vec2 basis_x = vec2(256.0, 128.0);
uniform vec2 basis_y = vec2(-256.0, 128.0);
uniform float grid_size = 30.0;
uniform float fade_tiles = 4.5;
uniform float noise_strength = 0.22;
uniform float noise_scale = 0.38;
uniform vec2 wind_velocity = vec2(0.18, 0.11);
uniform vec4 fog_color_inner : source_color = vec4(0.14, 0.19, 0.22, 0.94);
uniform vec4 fog_color_outer : source_color = vec4(0.06, 0.08, 0.10, 1.0);

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm_mist(vec2 p) {
	float v = 0.0;
	v += 0.65 * value_noise(p);
	v += 0.35 * value_noise(p * 2.03 + vec2(17.1, 9.7));
	return v;
}

void fragment() {
	vec2 rel = local_pos - top_vertex;
	float det = basis_x.x * basis_y.y - basis_x.y * basis_y.x;
	vec2 uv_grid = vec2(0.0);
	if (abs(det) > 0.0001) {
		uv_grid = vec2(
			(rel.x * basis_y.y - rel.y * basis_y.x) / det,
			(basis_x.x * rel.y - basis_x.y * rel.x) / det
		);
	}
	float dx = max(max(-uv_grid.x, uv_grid.x - grid_size), 0.0);
	float dy = max(max(-uv_grid.y, uv_grid.y - grid_size), 0.0);
	float outside_dist = length(vec2(dx, dy));

	if (outside_dist <= 0.0001) {
		COLOR = vec4(0.0);
	} else {
		float norm_dist = clamp(outside_dist / max(fade_tiles, 0.001), 0.0, 1.0);
		float base_fade = smoothstep(0.0, 1.0, norm_dist);
		vec2 mist_uv = uv_grid * noise_scale + TIME * wind_velocity;
		float mist_n = fbm_mist(mist_uv) - 0.5;
		float envelope = base_fade * (1.0 - base_fade) * 4.0;
		float alpha = clamp(base_fade + mist_n * noise_strength * envelope, 0.0, 1.0);
		vec3 fog_rgb = mix(fog_color_inner.rgb, fog_color_outer.rgb, smoothstep(0.0, 1.0, norm_dist));
		float fog_a = mix(fog_color_inner.a, fog_color_outer.a, base_fade) * alpha;
		COLOR = vec4(fog_rgb, fog_a);
	}
}
"""

var tilemap: TileMapLayer
var grid_size: int = 30
var fade_tiles: float = DEFAULT_FADE_TILES
var noise_strength: float = DEFAULT_NOISE_STRENGTH
var noise_scale: float = DEFAULT_NOISE_SCALE
var wind_velocity: Vector2 = DEFAULT_WIND_VELOCITY
var fog_color_inner: Color = DEFAULT_INNER_FOG_COLOR
var fog_color_outer: Color = DEFAULT_OUTER_FOG_COLOR

var _top_vertex: Vector2 = Vector2(0.0, -128.0)
var _basis_x: Vector2 = Vector2(256.0, 128.0)
var _basis_y: Vector2 = Vector2(-256.0, 128.0)
var _coverage_rect: Rect2 = Rect2()
var _fog_polygon: Polygon2D
var _shader_material: ShaderMaterial
var _is_configured: bool = false


func configure(
		world_tilemap: TileMapLayer,
		world_grid_size: int,
		camera: Camera2D = null) -> void:
	tilemap = world_tilemap
	grid_size = maxi(1, world_grid_size)
	if tilemap == null:
		push_error("MapBoundaryFog requires a valid TileMapLayer.")
		return

	position = tilemap.position
	# Render above ground/edge void but well below HoverLayer (z_index = 100) and UI.
	z_index = 5
	z_as_relative = false

	_compute_isometric_basis()
	_ensure_fog_polygon()
	_rebuild_geometry_and_uniforms(camera)
	_is_configured = true


func is_configured() -> bool:
	return _is_configured


func get_fog_polygon() -> Polygon2D:
	return _fog_polygon


func get_shader_material() -> ShaderMaterial:
	return _shader_material


func get_coverage_rect() -> Rect2:
	return _coverage_rect


## Converts a tilemap-local position into continuous [0, grid_size]² coordinates.
func local_to_grid_uv(local_pos: Vector2) -> Vector2:
	var rel: Vector2 = local_pos - _top_vertex
	var det: float = _basis_x.x * _basis_y.y - _basis_x.y * _basis_y.x
	if absf(det) <= 0.0001:
		return Vector2.ZERO
	return Vector2(
		(rel.x * _basis_y.y - rel.y * _basis_y.x) / det,
		(_basis_x.x * rel.y - _basis_x.y * rel.x) / det
	)


## Returns the Euclidean distance in tile units outside [0, grid_size]² (0.0 inside).
func outside_distance_in_tiles(local_pos: Vector2) -> float:
	var uv: Vector2 = local_to_grid_uv(local_pos)
	var dx: float = maxf(maxf(-uv.x, uv.x - float(grid_size)), 0.0)
	var dy: float = maxf(maxf(-uv.y, uv.y - float(grid_size)), 0.0)
	return Vector2(dx, dy).length()


## Evaluates the exact fog opacity at a tilemap-local position (matching the shader).
func get_fog_opacity_at_local(local_pos: Vector2, time_sec: float = 0.0) -> float:
	var outside_dist: float = outside_distance_in_tiles(local_pos)
	if outside_dist <= 0.0001:
		return 0.0
	var norm_dist: float = clampf(outside_dist / maxf(fade_tiles, 0.001), 0.0, 1.0)
	var base_fade: float = smoothstep(0.0, 1.0, norm_dist)
	var uv_grid: Vector2 = local_to_grid_uv(local_pos)
	var mist_uv: Vector2 = uv_grid * noise_scale + time_sec * wind_velocity
	var mist_n: float = _fbm_mist(mist_uv) - 0.5
	var envelope: float = base_fade * (1.0 - base_fade) * 4.0
	var alpha: float = clampf(base_fade + mist_n * noise_strength * envelope, 0.0, 1.0)
	return lerpf(fog_color_inner.a, fog_color_outer.a, base_fade) * alpha


## Convenience helper that evaluates fog opacity at the center of a grid cell.
func get_fog_opacity_at_cell(cell: Vector2i, time_sec: float = 0.0) -> float:
	if tilemap == null:
		return 0.0
	return get_fog_opacity_at_local(tilemap.map_to_local(cell), time_sec)


func _compute_isometric_basis() -> void:
	var c00: Vector2 = tilemap.map_to_local(Vector2i(0, 0))
	var c10: Vector2 = tilemap.map_to_local(Vector2i(1, 0))
	var c01: Vector2 = tilemap.map_to_local(Vector2i(0, 1))
	_basis_x = c10 - c00
	_basis_y = c01 - c00
	_top_vertex = c00 - 0.5 * _basis_x - 0.5 * _basis_y


func _ensure_fog_polygon() -> void:
	if _fog_polygon == null or not is_instance_valid(_fog_polygon):
		_fog_polygon = Polygon2D.new()
		_fog_polygon.name = "BoundaryFogPolygon"
		add_child(_fog_polygon)
	if _shader_material == null:
		var shader := Shader.new()
		shader.code = BOUNDARY_FOG_SHADER_CODE
		_shader_material = ShaderMaterial.new()
		_shader_material.shader = shader
	_fog_polygon.material = _shader_material


func _rebuild_geometry_and_uniforms(camera: Camera2D) -> void:
	var gs: float = float(grid_size)
	var corners: PackedVector2Array = PackedVector2Array([
		_top_vertex,
		_top_vertex + gs * _basis_x,
		_top_vertex + gs * _basis_x + gs * _basis_y,
		_top_vertex + gs * _basis_y,
	])
	var min_x: float = corners[0].x
	var max_x: float = corners[0].x
	var min_y: float = corners[0].y
	var max_y: float = corners[0].y
	for corner: Vector2 in corners:
		min_x = minf(min_x, corner.x)
		max_x = maxf(max_x, corner.x)
		min_y = minf(min_y, corner.y)
		max_y = maxf(max_y, corner.y)

	var tile_span_x: float = maxf(absf(_basis_x.x) + absf(_basis_y.x), 512.0)
	var tile_span_y: float = maxf(absf(_basis_x.y) + absf(_basis_y.y), 256.0)
	var pad_x: float = tile_span_x * OUTER_PADDING_TILES
	var pad_y: float = tile_span_y * OUTER_PADDING_TILES

	if camera != null:
		var cam_margin_x: float = absf(float(camera.limit_right - camera.limit_left)) * 0.5
		var cam_margin_y: float = absf(float(camera.limit_bottom - camera.limit_top)) * 0.5
		pad_x = maxf(pad_x, cam_margin_x)
		pad_y = maxf(pad_y, cam_margin_y)

	_coverage_rect = Rect2(
		Vector2(min_x - pad_x, min_y - pad_y),
		Vector2((max_x - min_x) + pad_x * 2.0, (max_y - min_y) + pad_y * 2.0)
	)

	_fog_polygon.polygon = PackedVector2Array([
		_coverage_rect.position,
		Vector2(_coverage_rect.end.x, _coverage_rect.position.y),
		_coverage_rect.end,
		Vector2(_coverage_rect.position.x, _coverage_rect.end.y),
	])
	_fog_polygon.color = Color(1.0, 1.0, 1.0, 1.0)

	_shader_material.set_shader_parameter("top_vertex", _top_vertex)
	_shader_material.set_shader_parameter("basis_x", _basis_x)
	_shader_material.set_shader_parameter("basis_y", _basis_y)
	_shader_material.set_shader_parameter("grid_size", gs)
	_shader_material.set_shader_parameter("fade_tiles", fade_tiles)
	_shader_material.set_shader_parameter("noise_strength", noise_strength)
	_shader_material.set_shader_parameter("noise_scale", noise_scale)
	_shader_material.set_shader_parameter("wind_velocity", wind_velocity)
	_shader_material.set_shader_parameter("fog_color_inner", fog_color_inner)
	_shader_material.set_shader_parameter("fog_color_outer", fog_color_outer)


func _hash21(p: Vector2) -> float:
	var q: Vector2 = Vector2(
		fposmod(p.x * 123.34, 1.0),
		fposmod(p.y * 456.21, 1.0)
	)
	var d: float = q.dot(q + Vector2(45.32, 45.32))
	q += Vector2(d, d)
	return fposmod(q.x * q.y, 1.0)


func _value_noise(p: Vector2) -> float:
	var i: Vector2 = p.floor()
	var f: Vector2 = p - i
	var u: Vector2 = f * f * (Vector2(3.0, 3.0) - 2.0 * f)
	var a: float = _hash21(i)
	var b: float = _hash21(i + Vector2(1.0, 0.0))
	var c: float = _hash21(i + Vector2(0.0, 1.0))
	var d: float = _hash21(i + Vector2(1.0, 1.0))
	return lerpf(lerpf(a, b, u.x), lerpf(c, d, u.x), u.y)


func _fbm_mist(p: Vector2) -> float:
	var v: float = 0.0
	v += 0.65 * _value_noise(p)
	v += 0.35 * _value_noise(p * 2.03 + Vector2(17.1, 9.7))
	return v


