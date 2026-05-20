extends Node
class_name MeshRandomizer

# Randomizes vertex positions on a mesh, similar to Blender's
# Mesh > Transform > Randomize operation.
#
# Parameters:
#   mesh         - The input Mesh (ArrayMesh or PrimitiveMesh). Returns a new ArrayMesh.
#   offset       - Maximum displacement magnitude (Blender's "Amount").
#   uniform      - 0.0 = fully random per-vertex direction; 1.0 = same random
#                  direction for all vertices (Blender's "Uniform").
#   normal       - 0.0 = ignore normals; 1.0 = displace strictly along the
#                  vertex normal (Blender's "Normal"). Mixed values blend.
#   seed_value   - RNG seed for reproducibility. -1 = randomize.
#   recalc_norms - If true, recomputes smooth normals after displacement.
#
# Returns: a new ArrayMesh with the displaced surfaces.
static func randomize_mesh(
		mesh: Mesh,
		offset: float = 0.1,
		uniform: float = 0.0,
		normal: float = 0.0,
		seed_value: int = -1,
		recalc_norms: bool = true
	) -> ArrayMesh:

	if mesh == null:
		push_error("MeshRandomizer: mesh is null.")
		return null

	var rng := RandomNumberGenerator.new()
	if seed_value < 0:
		rng.randomize()
	else:
		rng.seed = seed_value

	# Pre-compute the "uniform" shared direction once. When uniform == 1.0
	# every vertex moves the same way; when 0.0 each vertex gets its own.
	var shared_dir := _random_unit_vec(rng)

	var out_mesh := ArrayMesh.new()

	for surface_idx in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface_idx)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]

		var has_normals := norms != null and norms.size() == verts.size()
		if normal > 0.0 and not has_normals:
			push_warning("MeshRandomizer: surface %d has no normals; 'normal' factor ignored." % surface_idx)

		var new_verts := PackedVector3Array()
		new_verts.resize(verts.size())

		for i in verts.size():
			# Per-vertex random direction (used when uniform < 1.0).
			var rand_dir := _random_unit_vec(rng)
			# Blend per-vertex random with the shared direction.
			var dir := rand_dir.lerp(shared_dir, uniform).normalized()

			# Blend that direction with the vertex normal.
			if normal > 0.0 and has_normals:
				dir = dir.lerp(norms[i].normalized(), normal).normalized()

			# Random magnitude in [0, offset] gives a more natural,
			# Blender-like distribution than a fixed offset.
			var amount := rng.randf() * offset
			new_verts[i] = verts[i] + dir * amount

		arrays[Mesh.ARRAY_VERTEX] = new_verts

		# Optionally rebuild smooth normals so lighting stays consistent.
		if recalc_norms and has_normals:
			arrays[Mesh.ARRAY_NORMAL] = _recalculate_normals(
				new_verts,
				arrays[Mesh.ARRAY_INDEX]
			)

		out_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

		# Preserve the original material if any.
		var mat := mesh.surface_get_material(surface_idx)
		if mat:
			out_mesh.surface_set_material(surface_idx, mat)

	return out_mesh


# Returns a uniformly distributed random unit vector on the sphere.
static func _random_unit_vec(rng: RandomNumberGenerator) -> Vector3:
	var z := rng.randf_range(-1.0, 1.0)
	var t := rng.randf_range(0.0, TAU)
	var r := sqrt(1.0 - z * z)
	return Vector3(r * cos(t), r * sin(t), z)


# Smooth-normals recalculation by averaging adjacent face normals.
# Accepts a possibly-null index array (handles non-indexed meshes too).
static func _recalculate_normals(
		verts: PackedVector3Array,
		indices
	) -> PackedVector3Array:

	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for i in normals.size():
		normals[i] = Vector3.ZERO

	var idx_count := 0
	var has_indices = indices != null and indices.size() > 0
	idx_count = indices.size() if has_indices else verts.size()

	var i := 0
	while i < idx_count - 2:
		var a: int = indices[i]     if has_indices else i
		var b: int = indices[i + 1] if has_indices else i + 1
		var c: int = indices[i + 2] if has_indices else i + 2

		var face_n := (verts[b] - verts[a]).cross(verts[c] - verts[a])
		# Accumulate area-weighted normals; we normalize at the end.
		normals[a] += face_n
		normals[b] += face_n
		normals[c] += face_n
		i += 3

	for j in normals.size():
		if normals[j].length_squared() > 0.0:
			normals[j] = normals[j].normalized()
		else:
			normals[j] = Vector3.UP
	return normals
