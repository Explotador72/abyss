@tool
class_name WindSystem
extends Node
## Lightweight wind provider that can be used by ocean, particles, clouds,
## boats, or gameplay code without depending on any other plugin.

signal wind_changed

@export_group("Wind")
## Base wind speed in meters per second. Gusts are added on top when enabled.
@export_range(0.0, 100.0, 0.1) var wind_speed := 10.0 :
	set(value):
		wind_speed = maxf(0.0, value)
		wind_changed.emit()

## Compass-like wind heading in degrees. 0 points along +Z; 90 points along +X.
@export_range(0, 360.0, 1.0) var wind_direction := 20.0 :
	set(value):
		wind_direction = value
		wind_changed.emit()
		set_arrow_rotation()
		if direction_slew_rate >= 180.0:
			_slewed_direction = value


@export var sprite_arrow : Sprite3D

@export var show_arrow_in_game := true

@export_group("Slew")
## How gradually the wind direction changes. 0 = extremely slow (0.5°/s),
## 180 = instant. Middle values give proportional slew rates.
@export_range(0.0, 180.0, 0.1) var direction_slew_rate := 90.0 :
	set(value):
		direction_slew_rate = value
		if value >= 180.0:
			_slewed_direction = wind_direction

@export_group("Gusts")
## Maximum additional gust speed in meters per second. Set to 0 for steady wind.
@export_range(0.0, 100.0, 0.1) var gust_strength := 0.0 :
	set(value):
		gust_strength = maxf(0.0, value)
		wind_changed.emit()

## Gust cycles per second. Higher values make wind speed change faster.
@export_range(0.0, 10.0, 0.01) var gust_frequency := 0.1 :
	set(value):
		gust_frequency = maxf(0.0, value)
		wind_changed.emit()

var _elapsed_time := 0.0
var _slewed_direction := 20.0


func _ready() -> void:
	if sprite_arrow:
		sprite_arrow.visible = show_arrow_in_game
	_slewed_direction = wind_direction


func _process(delta : float) -> void:
	if Engine.is_editor_hint():
		return
	_elapsed_time += delta
	if direction_slew_rate >= 180.0:
		_slewed_direction = wind_direction
	else:
		var t : float = direction_slew_rate / 180.0
		var actual_rate : float = lerp(0.5, 180.0, t)
		var step : float = actual_rate * delta
		_slewed_direction = _move_toward_degrees(_slewed_direction, wind_direction, step)


func get_wind_speed() -> float:
	return maxf(0.0, wind_speed + get_gust_offset())


func get_base_wind_speed() -> float:
	return wind_speed


func get_gust_offset() -> float:
	if gust_strength <= 0.0 or gust_frequency <= 0.0:
		return 0.0
	var phase := _elapsed_time * gust_frequency * TAU
	var layered_gust := (
		sin(phase) * 0.55
		+ sin(phase * 2.17 + 1.7) * 0.30
		+ sin(phase * 0.41 + 3.1) * 0.15
	)
	return layered_gust * gust_strength


func get_wind_direction() -> float:
	return _slewed_direction


func get_wind_vector_2d() -> Vector2:
	var radians := deg_to_rad(_slewed_direction)
	return Vector2(sin(radians), cos(radians)) * get_wind_speed()


func get_wind_vector_3d() -> Vector3:
	var wind := get_wind_vector_2d()
	return Vector3(wind.x, 0.0, wind.y)

func set_arrow_rotation():
	if sprite_arrow:
		sprite_arrow.rotation.y = deg_to_rad(wind_direction+90)



static func _move_toward_degrees(from : float, to : float, max_delta : float) -> float:
	var delta := wrapf(to - from + 180.0, 0.0, 360.0) - 180.0
	if abs(delta) <= max_delta:
		return to
	return from + sign(delta) * max_delta
