@tool
class_name WaveCascadeParameters extends Resource

signal scale_changed

@export var tile_length := Vector2(50, 50) :
	set(value): tile_length = value; should_generate_spectrum = true; _tile_length = [value.x, value.y]; scale_changed.emit()
@export_range(0, 2) var displacement_scale := 1.0 :
	set(value): displacement_scale = value; _displacement_scale = [displacement_scale]; scale_changed.emit()
@export_range(0, 2) var normal_scale := 1.0 :
	set(value): normal_scale = value; _normal_scale = [normal_scale]; scale_changed.emit()

@export var wind_speed := 20.0 :
	set(value): wind_speed = max(0.0001, value); should_generate_spectrum = true; _wind_speed = [wind_speed]
@export_range(-360, 360) var wind_direction := 0.0 :
	set(value): wind_direction = value; should_generate_spectrum = true; _wind_direction = [deg_to_rad(value)]
@export var fetch_length := 500.0 :
	set(value): fetch_length = max(0.0001, value); should_generate_spectrum = true; _fetch_length = [fetch_length]
@export_range(0, 2) var swell := 0.8 :
	set(value): swell = value; should_generate_spectrum = true; _swell = [value]
@export_range(0, 1) var spread := 0.55 :
	set(value): spread = value; should_generate_spectrum = true; _spread = [value]
@export_range(0, 1) var detail := 1.0 :
	set(value): detail = value; should_generate_spectrum = true; _detail = [value]

@export_range(0, 2) var whitecap := 0.50 :
	set(value): whitecap = value; should_generate_spectrum = true; _whitecap = [value]
@export_range(0, 10) var foam_amount := 6.0 :
	set(value): foam_amount = value; should_generate_spectrum = true; _foam_amount = [value]

var spectrum_seed := Vector2i.ZERO
var should_generate_spectrum := true

var time : float
var foam_grow_rate : float
var foam_decay_rate : float

var _tile_length := [tile_length.x, tile_length.y]
var _displacement_scale := [displacement_scale]
var _normal_scale := [normal_scale]
var _wind_speed := [wind_speed]
var _wind_direction := [deg_to_rad(wind_direction)]
var _fetch_length := [fetch_length]
var _swell := [swell]
var _detail := [detail]
var _spread := [spread]
var _whitecap := [whitecap]
var _foam_amount := [foam_amount]
