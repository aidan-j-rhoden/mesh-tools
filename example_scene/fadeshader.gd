extends MeshInstance3D
# Attach this to the MeshInstance3D that uses melted_metal_fade.gdshader.
# It copies your target StandardMaterial3D's properties into the shader,
# waits `fade_delay` seconds, then fades over `fade_duration` seconds.
# Driving the fade from a Tween (instead of the shader's own TIME clock)
# keeps the timing exact and works no matter when the object spawns.

## The material to end up as.
@export var target_material: StandardMaterial3D
## Seconds to hold the molten look before fading.
@export var fade_delay: float = 3.0
## Seconds the cross-fade takes.
@export var fade_duration: float = 10.0
## Give each instance its own material so they don't all fade together.
@export var unique_material: bool = true

var _mat: ShaderMaterial

func activate_fade() -> void:
	_mat = get_active_material(1) as ShaderMaterial
	if _mat == null:
		push_warning("MeltFader: no ShaderMaterial found on surface 1.")
		return
	if unique_material:
		_mat = _mat.duplicate()
		set_surface_override_material(1, _mat)

	_copy_target_into_shader()

	# Hand control of `fade` to this script rather than the shader's TIME.
	_mat.set_shader_parameter("auto_fade", false)
	_mat.set_shader_parameter("fade", 0.0)

	var tween := create_tween()
	tween.tween_interval(fade_delay)
	tween.tween_property(_mat, "shader_parameter/fade", 1.0, fade_duration)


func _copy_target_into_shader() -> void:
	if target_material == null:
		push_warning("MeltFader: target_material is not set; using shader defaults.")
		return

	_mat.set_shader_parameter("target_albedo", target_material.albedo_color)
	_mat.set_shader_parameter("target_metallic", target_material.metallic)
	_mat.set_shader_parameter("target_roughness", target_material.roughness)

	if target_material.albedo_texture != null:
		_mat.set_shader_parameter("target_albedo_tex", target_material.albedo_texture)
		_mat.set_shader_parameter("target_use_albedo_tex", true)
	else:
		_mat.set_shader_parameter("target_use_albedo_tex", false)

	if target_material.emission_enabled:
		_mat.set_shader_parameter("target_emission", target_material.emission)
		_mat.set_shader_parameter("target_emission_energy", target_material.emission_energy_multiplier)
	else:
		_mat.set_shader_parameter("target_emission", Color(0, 0, 0, 1))
		_mat.set_shader_parameter("target_emission_energy", 0.0)
