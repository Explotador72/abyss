@tool
"""
Wave parameters management for ocean simulation.
Centralized via autoload to ensure synchronized wave state across all components.
"""

extends Node

# Global ocean simulation state
class WaveState:
    var time: float = 0.0
    var height_scale: float = 1.0
    var wavelength_scale: float = 1.0
    var group_intensity: float = 0.6

# Singleton instance
static var instance: WaveState = null

func _init() -> void:
    if instance == null:
        instance = WaveState.new()

func _process(delta: float) -> void:
    instance.time += delta * 1.0

func get_time() -> float:
    return instance.time

func get_height_scale() -> float:
    return instance.height_scale

func get_wavelength_scale() -> float:
    return instance.wavelength_scale

func get_group_intensity() -> float:
    return instance.group_intensity

func set_height_scale(value: float) -> void:
    instance.height_scale = value

func set_wavelength_scale(value: float) -> void:
    instance.wavelength_scale = value

func set_group_intensity(value: float) -> void:
    instance.group_intensity = clamp(value, 0.2, 1.0)

func reset() -> void:
    instance.time = 0.0
    instance.height_scale = 1.0
    instance.wavelength_scale = 1.0
    instance.group_intensity = 0.6
