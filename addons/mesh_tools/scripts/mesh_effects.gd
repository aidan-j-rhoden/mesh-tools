extends Node

# Randomizes the vertices of a mesh similar to Blender's Mesh > Transform > Randomize.
# Preserves mesh topology (no splits) by merging duplicate vertices, applying the same
# offset to all coincident vertices, then recalculating normals with correct outward winding.
#
# Parameters:
#   mesh         - The input Mesh to randomize.
#   amount       - The maximum displacement distance (in local units).
#   uniform      - 0.0 = each axis randomized independently (per-vertex jitter on x, y, z).
#                  1.0 = same scalar random factor on all axes (vertex moves uniformly).
#                  Values in between blend the two.
#   along_normal - 0.0 = displacement is in a random direction.
#                  1.0 = displacement is purely along the vertex normal.
#                  Values in between blend the two.
#   seed         - Optional RNG seed for reproducible results. -1 = use a random seed.
#
# Returns: a new ArrayMesh with randomized vertices and recomputed outward normals.
static func randomize_mesh(
	mesh: Mesh,
	amount: float = 0.1,
	uniform: float = 0.0,
	along_normal: float = 0.0,
	seed: int = -1
) -> ArrayMesh:
	if mesh == null:
		push_error("randomize_mesh: input mesh is null")
		return null

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	if seed >= 0:
		rng.seed = seed
	else:
		rng.randomize()

	var result: ArrayMesh = ArrayMesh.new()

	for surface_idx in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface_idx)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]

		# If the surface isn't indexed, build an index array so we can deduplicate.
		# Without this, faces would split apart because each face would jitter
		# its own copies of shared vertices independently.
		if indices.is_empty():
			indices = PackedInt32Array()
			indices.resize(verts.size())
			for i in range(verts.size()):
				indices[i] = i

		# Build a map from position -> list of vertex indices that share that position.
		# This lets us apply ONE random offset per unique location, keeping the mesh welded.
		var position_groups: Dictionary = {}
		for i in range(verts.size()):
			# Quantize position slightly so floating-point noise doesn't separate
			# vertices that should be considered identical.
			var key: String = _quantize_key(verts[i])
			if not position_groups.has(key):
				position_groups[key] = []
			position_groups[key].append(i)

		# Determine per-unique-position normals (average of all shared vertices' normals)
		# so the "along normal" displacement matches the surface direction even at seams.
		var group_normals: Dictionary = {}
		if not normals.is_empty():
			for key in position_groups.keys():
				var n_sum: Vector3 = Vector3.ZERO
				for i in position_groups[key]:
					n_sum += normals[i]
				if n_sum.length_squared() > 0.0:
					group_normals[key] = n_sum.normalized()
				else:
					group_normals[key] = Vector3.UP

		# Compute and apply one offset per unique position.
		var new_verts: PackedVector3Array = PackedVector3Array()
		new_verts.resize(verts.size())

		for key in position_groups.keys():
			var indices_at_pos: Array = position_groups[key]
			var base_pos: Vector3 = verts[indices_at_pos[0]]

			# Random vector with independent components in [-1, 1].
			var rand_vec: Vector3 = Vector3(
				rng.randf_range(-1.0, 1.0),
				rng.randf_range(-1.0, 1.0),
				rng.randf_range(-1.0, 1.0)
			)

			# Uniform scalar in [-1, 1] applied equally to all axes.
			var uniform_scalar: float = rng.randf_range(-1.0, 1.0)
			var uniform_vec: Vector3 = Vector3(uniform_scalar, uniform_scalar, uniform_scalar)

			# Blend between independent-axis and uniform-axis random vectors.
			var offset_dir: Vector3 = rand_vec.lerp(uniform_vec, clamp(uniform, 0.0, 1.0))

			# Blend between random direction and the vertex's normal direction.
			if along_normal > 0.0 and group_normals.has(key):
				var normal: Vector3 = group_normals[key]
				# Use a signed scalar so vertices can move inward or outward along the normal.
				var signed_scalar: float = rng.randf_range(-1.0, 1.0)
				var normal_offset: Vector3 = normal * signed_scalar
				offset_dir = offset_dir.lerp(normal_offset, clamp(along_normal, 0.0, 1.0))

			var offset: Vector3  = offset_dir * amount
			var new_pos: Vector3 = base_pos + offset

			# Write the same new position back to every vertex that shared this location.
			for i in indices_at_pos:
				new_verts[i] = new_pos

		# Recalculate normals based on face geometry so they point outward correctly.
		var new_normals: PackedVector3Array = _recalculate_normals(new_verts, indices)

		# Rebuild the surface arrays, preserving extra channels (UVs, colors, etc.).
		var new_arrays: Array = arrays.duplicate()
		new_arrays[Mesh.ARRAY_VERTEX] = new_verts
		new_arrays[Mesh.ARRAY_NORMAL] = new_normals
		new_arrays[Mesh.ARRAY_INDEX] = indices

		# Tangents become invalid after we move things; clear them so Godot can
		# regenerate or the material can fall back gracefully.
		if Mesh.ARRAY_TANGENT < new_arrays.size():
			new_arrays[Mesh.ARRAY_TANGENT] = null

		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, new_arrays)

		# Carry over the material from the original surface.
		var mat: Material = mesh.surface_get_material(surface_idx)
		if mat:
			result.surface_set_material(surface_idx, mat)

	return result


# Quantizes a position into a string key so near-identical vertices group together.
# 1e5 gives ~5 decimal places of precision, which is more than enough to weld
# shared edges without collapsing legitimately distinct vertices.
static func _quantize_key(v: Vector3) -> String:
	var q: float = 100000.0
	return "%d,%d,%d" % [
		int(round(v.x * q)),
		int(round(v.y * q)),
		int(round(v.z * q))
	]


# Recalculates vertex normals by averaging the face normals of all faces touching
# each vertex. Uses the original winding order so normals point outward (assuming
# the source mesh was wound correctly to begin with — Godot uses clockwise winding
# when viewed from outside, so cross(b - a, c - a) gives the outward face normal).
static func _recalculate_normals(verts: PackedVector3Array, indices: PackedInt32Array) -> PackedVector3Array:
	var normals: PackedVector3Array = PackedVector3Array()
	normals.resize(verts.size())
	for i in range(normals.size()):
		normals[i] = Vector3.ZERO

	# Accumulate face normals onto each of the face's three vertices.
	# We weight by the un-normalized cross product so larger faces contribute more,
	# which gives smoother results on irregular meshes.
	var tri_count: int = indices.size() / 3
	for t in range(tri_count):
		var i0: int = indices[t * 3 + 0]
		var i1: int = indices[t * 3 + 1]
		var i2: int = indices[t * 3 + 2]

		var a: Vector3 = verts[i0]
		var b: Vector3 = verts[i1]
		var c: Vector3 = verts[i2]

		# Godot's default winding for surface tools is clockwise as seen from outside,
		# so this cross product yields the outward-facing normal.
		var face_normal: Vector3 = (b - a).cross(c - a)

		normals[i0] += face_normal
		normals[i1] += face_normal
		normals[i2] += face_normal

	# Normalize the accumulated vectors. Fall back to UP for degenerate cases.
	for i in range(normals.size()):
		if normals[i].length_squared() > 0.0:
			normals[i] = normals[i].normalized()
		else:
			normals[i] = Vector3.UP

	return normals
