extends MeshInstance3D
# Attach this to any MeshInstance3D that may receive the melted_metal shader.
# Supports multiple independent fading surfaces under a single node.
#
# Typical use after a CSG / custom slice:
#   1. The slicer appends the molten ShaderMaterial as the last surface.
#   2. Call activate_fade() (or activate_fade(surface_idx, target)) on the new piece.
#   3. When a piece that is already fading is sliced again, read get_fade_state(),
#      hand the dictionary to the two children, then call apply_fade_state() on each.
#   4. Finished surfaces are automatically replaced by the pure StandardMaterial3D
#      and merged when two or more share the same material.

## Default material to fade into (can be overridden per-surface).
@export var target_material: StandardMaterial3D
## Seconds to hold the molten look before the cross-fade begins.
@export var fade_delay: float = 3.0
## Seconds the cross-fade takes.
@export var fade_duration: float = 10.0
## Force a unique ShaderMaterial instance so pieces don't share fade progress.
@export var unique_material: bool = true

# surface_idx -> {
#   "mat": ShaderMaterial,
#   "target": StandardMaterial3D,
#   "delay_left": float,
#   "fade": float,          # 0..1
#   "duration": float
# }
var _active_fades: Dictionary = {}

func _ready() -> void:
	set_process(false)

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Start a new fade on a surface (defaults to the last surface – the one the
## slicer just appended).
func activate_fade(surface_idx: int = -1, p_target: StandardMaterial3D = null) -> void:
	if mesh == null:
		push_warning("MeltFader: no mesh.")
		return
	if surface_idx < 0:
		surface_idx = mesh.get_surface_count() - 1
	if surface_idx < 0 or surface_idx >= mesh.get_surface_count():
		push_warning("MeltFader: invalid surface %d." % surface_idx)
		return

	var tgt: StandardMaterial3D = p_target if p_target else target_material
	if tgt == null:
		push_warning("MeltFader: no target material given.")
		return

	var mat := get_active_material(surface_idx) as ShaderMaterial
	if mat == null:
		push_warning("MeltFader: surface %d is not a ShaderMaterial." % surface_idx)
		return

	if unique_material:
		mat = mat.duplicate() as ShaderMaterial

	_assign_material_to_surface(surface_idx, mat)
	_copy_target_into_shader(mat, tgt)
	mat.set_shader_parameter("auto_fade", false)
	mat.set_shader_parameter("fade", 0.0)

	_active_fades[surface_idx] = {
		"mat": mat,
		"target": tgt,
		"delay_left": fade_delay,
		"fade": 0.0,
		"duration": fade_duration
	}
	set_process(true)

## Snapshot that can be handed to the two children after a slice.
func get_fade_state() -> Dictionary:
	var state: Dictionary = {}
	for surf in _active_fades:
		var info: Dictionary = _active_fades[surf]
		state[surf] = {
			"fade": info.fade,
			"delay_left": info.delay_left,
			"duration": info.duration,
			"target": info.target
		}
	return state

## Resume fades on a freshly spawned half.  The slicer is responsible for
## mapping old surface indices → new surface indices (or for making the
## materials unique so the indices still line up).
func apply_fade_state(state: Dictionary) -> void:
	if state.is_empty():
		return
	for surf in state:
		var s: Dictionary = state[surf]
		var mat := get_active_material(surf) as ShaderMaterial
		if mat == null:
			push_warning("MeltFader: apply_fade_state – surface %d has no ShaderMaterial." % surf)
			continue

		if unique_material:
			mat = mat.duplicate() as ShaderMaterial

		_assign_material_to_surface(surf, mat)
		_copy_target_into_shader(mat, s.target)
		mat.set_shader_parameter("auto_fade", false)
		mat.set_shader_parameter("fade", s.fade)

		_active_fades[surf] = {
			"mat": mat,
			"target": s.target,
			"delay_left": s.delay_left,
			"fade": s.fade,
			"duration": s.duration
		}
	if not _active_fades.is_empty():
		set_process(true)

# ---------------------------------------------------------------------------
# Internal – drive the fades
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _active_fades.is_empty():
		set_process(false)
		return

	var to_finish: Array[int] = []
	for surf in _active_fades.keys():
		# Safety: surface may have disappeared after an external mesh rebuild
		if mesh == null or surf >= mesh.get_surface_count():
			to_finish.append(surf)
			continue
		var info: Dictionary = _active_fades[surf]
		if get_active_material(surf) != info.mat:
			to_finish.append(surf)
			continue

		if info.delay_left > 0.0:
			info.delay_left -= delta
			if info.delay_left < 0.0:
				info.delay_left = 0.0
		else:
			info.fade += delta / info.duration
			if info.fade >= 1.0:
				info.fade = 1.0
				info.mat.set_shader_parameter("fade", 1.0)
				to_finish.append(surf)
			else:
				info.mat.set_shader_parameter("fade", info.fade)

	for surf in to_finish:
		_finish_fade(surf)

func _finish_fade(surf: int) -> void:
	if not _active_fades.has(surf):
		return
	var info: Dictionary = _active_fades[surf]
	var tgt: StandardMaterial3D = info.target

	# Replace shader with the final StandardMaterial3D
	_assign_material_to_surface(surf, tgt)
	_active_fades.erase(surf)

	# Try to collapse any surfaces that now share this exact material
	_try_merge_materials(tgt)

	if _active_fades.is_empty():
		set_process(false)

# ---------------------------------------------------------------------------
# Material assignment helper (keeps everything on the ArrayMesh itself)
# ---------------------------------------------------------------------------

func _assign_material_to_surface(surf: int, mat: Material) -> void:
	set_surface_override_material(surf, null)		# clear any override
	if mesh is ArrayMesh:
		(mesh as ArrayMesh).surface_set_material(surf, mat)
	else:
		# Fallback for non-ArrayMesh (ImmediateMesh, etc.)
		set_surface_override_material(surf, mat)

# ---------------------------------------------------------------------------
# Merge logic
# ---------------------------------------------------------------------------

func _try_merge_materials(mat: Material) -> void:
	if not (mesh is ArrayMesh):
		return
	var am := mesh as ArrayMesh
	var to_merge: Array[int] = []
	for i in range(am.get_surface_count()):
		if am.surface_get_material(i) == mat:
			to_merge.append(i)
	if to_merge.size() < 2:
		return
	_merge_surfaces(to_merge, mat)

func _merge_surfaces(indices: Array[int], mat: Material) -> void:
	indices.sort()
	var am := mesh as ArrayMesh
	var surface_count := am.get_surface_count()

	var other_surfaces: Array[Dictionary] = []
	var merge_arrays: Array = []

	for i in range(surface_count):
		var arrays := am.surface_get_arrays(i)
		if i in indices:
			merge_arrays.append(arrays)
		else:
			other_surfaces.append({
				"old_idx": i,
				"arrays": arrays,
				"mat": am.surface_get_material(i)
			})

	# Build the new mesh – non-merged surfaces keep their relative order
	var new_am := ArrayMesh.new()
	var old_to_new: Dictionary = {}
	var new_idx := 0

	for other in other_surfaces:
		new_am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, other.arrays)
		new_am.surface_set_material(new_idx, other.mat)
		old_to_new[other.old_idx] = new_idx
		new_idx += 1

	if not merge_arrays.is_empty():
		var combined := _combine_surface_arrays(merge_arrays)
		new_am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, combined)
		new_am.surface_set_material(new_idx, mat)

	mesh = new_am

	# Remap any still-active fades whose indices moved
	var new_active: Dictionary = {}
	for old_surf in _active_fades:
		if old_to_new.has(old_surf):
			new_active[old_to_new[old_surf]] = _active_fades[old_surf]
	_active_fades = new_active

	# Make sure no stale overrides remain
	for i in range(new_am.get_surface_count()):
		set_surface_override_material(i, null)

func _combine_surface_arrays(arrays_list: Array) -> Array:
	if arrays_list.is_empty():
		return []

	var result: Array = []
	result.resize(Mesh.ARRAY_MAX)
	var first: Array = arrays_list[0]

	# Allocate empty containers matching the first surface
	for array_idx in range(Mesh.ARRAY_MAX):
		if first[array_idx] == null:
			continue
		match array_idx:
			Mesh.ARRAY_INDEX:
				result[array_idx] = PackedInt32Array()
			Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL:
				result[array_idx] = PackedVector3Array()
			Mesh.ARRAY_TANGENT:
				result[array_idx] = PackedFloat32Array()
			Mesh.ARRAY_COLOR:
				result[array_idx] = PackedColorArray()
			Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2:
				result[array_idx] = PackedVector2Array()
			Mesh.ARRAY_BONES:
				result[array_idx] = PackedInt32Array()
			Mesh.ARRAY_WEIGHTS:
				result[array_idx] = PackedFloat32Array()
			_:
				# CUSTOM0-3 etc. – copy type then clear
				result[array_idx] = first[array_idx].duplicate()
				result[array_idx].clear()

	var vertex_offset := 0
	for arrs in arrays_list:
		var num_verts := 0
		if arrs[Mesh.ARRAY_VERTEX] != null:
			num_verts = arrs[Mesh.ARRAY_VERTEX].size()

		for array_idx in range(Mesh.ARRAY_MAX):
			if result[array_idx] == null or arrs[array_idx] == null:
				continue
			if array_idx == Mesh.ARRAY_INDEX:
				var indices: PackedInt32Array = arrs[array_idx]
				for idx in indices:
					result[array_idx].append(idx + vertex_offset)
			else:
				result[array_idx].append_array(arrs[array_idx])

		vertex_offset += num_verts

	return result

# ---------------------------------------------------------------------------
# Shader parameter copy (unchanged logic, now takes explicit mat + target)
# ---------------------------------------------------------------------------

func _copy_target_into_shader(mat: ShaderMaterial, tgt: StandardMaterial3D) -> void:
	if tgt == null:
		push_warning("MeltFader: target is null; using shader defaults.")
		return

	mat.set_shader_parameter("target_albedo", tgt.albedo_color)
	mat.set_shader_parameter("target_metallic", tgt.metallic)
	mat.set_shader_parameter("target_roughness", tgt.roughness)

	if tgt.albedo_texture != null:
		mat.set_shader_parameter("target_albedo_tex", tgt.albedo_texture)
		mat.set_shader_parameter("target_use_albedo_tex", true)
	else:
		mat.set_shader_parameter("target_use_albedo_tex", false)

	if tgt.emission_enabled:
		mat.set_shader_parameter("target_emission", tgt.emission)
		mat.set_shader_parameter("target_emission_energy", tgt.emission_energy_multiplier)
	else:
		mat.set_shader_parameter("target_emission", Color(0, 0, 0, 1))
		mat.set_shader_parameter("target_emission_energy", 0.0)
