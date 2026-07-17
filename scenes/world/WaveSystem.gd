"""
Dark murky ocean simulation for nautical horror game.
Multi-octave Gerstner waves with natural group formation.
"""

extends Node

@export var wave_height: float = 2.5
@export var wave_speed: float = 1.2
@export var wavelength_scale: float = 1.0

@export var dominant_direction: float = PI * 0.8
@export var wind_speed: float = 1.0
@export var direction_noise: float = 0.3

@export var num_octaves: int = 4
@export var amplitude_falloff: float = 0.55
@export var frequency_mult: float = 2.2

@export var group_size: int = 2
@export var group_strength: float = 0.6
@export var group_frequency: float = 0.15

class WaveOctave:
    var amplitude: float
    var frequency: float
    var direction: float
    var phase_offset: float

var wave_octaves: Array = []
var time: float = 0.0

func _ready() -> void:
    initialize_wave_octaves()

func _process(delta: float) -> void:
    time += delta * wave_speed

func initialize_wave_octaves() -> void:
    wave_octaves.clear()
    
    var current_amplitude: float = wave_height
    var current_frequency: float = 1.0 / (wavelength_scale * 8.0)
    
    for i in range(num_octaves):
        var octave: WaveOctave = WaveOctave.new()
        
        octave.amplitude = current_amplitude
        octave.frequency = current_frequency
        octave.direction = dominant_direction + sin(time * 0.5 + float(i) * 0.8) * direction_noise
        octave.phase_offset = float(i) * 0.6
        
        wave_octaves.append(octave)
        
        current_amplitude *= amplitude_falloff
        current_frequency *= frequency_mult

func get_wave_height_at_position(pos: Vector3) -> float:
    var height: float = 0.0
    
    var group_pos: Vector2 = Vector2(pos.x, pos.z)
    var group_phase: float = (group_pos.angle_to(Vector2(1, 0)) + time * 0.1) / (group_frequency * PI * 2)
    
    for i in range(min(wave_octaves.size(), 3)):
        var octave: WaveOctave = wave_octaves[i]
        
        var group_envelope: float = 1.0
        if i < group_size:
            var group_effect: float = sin(group_phase - float(i) * 0.5) * 0.5 + 0.5
            group_envelope = 1.0 - group_effect * (1.0 - group_strength)
        
        var wave_amplitude: float = octave.amplitude * group_envelope
        var k: float = 2.0 * PI / octave.frequency
        var c: float = sqrt(9.8 / k) / wind_speed
        
        var theta: float = k * (cos(octave.direction) * pos.x + sin(octave.direction) * pos.z) + octave.phase_offset + c * time
        height += wave_amplitude * sin(theta)
    
    return height

func set_wave_height(value: float) -> void:
    wave_height = value
    reinitialize_waves()

func set_wind_direction(direction: float) -> void:
    dominant_direction = direction
    reinitialize_waves()

func set_wavelength_scale(value: float) -> void:
    wavelength_scale = value
    reinitialize_waves()

func reinitialize_waves() -> void:
    initialize_wave_octaves()
