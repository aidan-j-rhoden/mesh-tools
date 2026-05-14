static func separate_mesh_islands(mesh: Mesh, merge_overlapping: bool = false) -> Array[Mesh]:
	# Separates a mesh into disconnected islands.
	#
	# - Only separates based on actual geometric connectivity (shared vertices via faces).
	# - Materials are preserved (multi-surface output meshes are created when an island uses multiple original surfaces).
	# - When merge_overlapping = true: vertices at the exact same position (even across surfaces or without shared edges) are treated as connected.
	# - Non-triangle surfaces are kept whole (not internally split).

	if mesh == null:
		return []
	if not mesh is ArrayMesh:
		push_warning("separate_mesh_islands currently only supports ArrayMesh. Returning original mesh.")
		return [mesh]

	var array_mesh := mesh as ArrayMesh
	var surface_count := array_mesh.get_surface_count()
	if surface_count == 0:
		return []

	# --- Collect per-surface data ---
	var surface_materials: Array[Material] = []
	var surface_arrays_list: Array = []
	var surface_primitive_types: Array[int] = []
	var surface_vertex_starts: Array[int] = []
	var surface_vertex_counts: Array[int] = []
	var global_vertex_count := 0

	for s in range(surface_count):
		surface_materials.append(array_mesh.surface_get_material(s))
		var arrs := array_mesh.surface_get_arrays(s)
		surface_arrays_list.append(arrs)
		surface_primitive_types.append(array_mesh.surface_get_primitive_type(s))

		var vcount := 0
		if arrs[Mesh.ARRAY_VERTEX] != null:
			vcount = arrs[Mesh.ARRAY_VERTEX].size()
		surface_vertex_counts.append(vcount)
		surface_vertex_starts.append(global_vertex_count)
		global_vertex_count += vcount

	if global_vertex_count == 0:
		return [mesh]

	# --- Union-Find setup ---
	var parent := PackedInt32Array()
	var rank := PackedInt32Array()
	parent.resize(global_vertex_count)
	rank.resize(global_vertex_count)
	for i in global_vertex_count:
		parent[i] = i
		rank[i] = 0

	# Simple find (iterative, no recursion)
	var find := func(v: int) -> int:
		var current := v
		while parent[current] != current:
			current = parent[current]
		return current

	var union_sets := func(a: int, b: int):
		var pa := find.call(a)
		var pb := find.call(b)
		if pa == pb:
			return
		if rank[pa] < rank[pb]:
			parent[pa] = pb
		elif rank[pa] > rank[pb]:
			parent[pb] = pa
		else:
			parent[pb] = pa
			rank[pa] += 1

	# --- 1. Connect vertices via faces (within each surface) ---
	for s in range(surface_count):
		var start_id := surface_vertex_starts[s]
		var arrs = surface_arrays_list[s]
		var prim := surface_primitive_types[s]

		if prim != Mesh.PRIMITIVE_TRIANGLES:
			# Keep entire non-triangle surface as one unit
			var vc := surface_vertex_counts[s]
			for j in range(1, vc):
				union_sets.call(start_id, start_id + j)
			continue

		var indices = arrs[Mesh.ARRAY_INDEX]
		if indices == null or indices.is_empty():
			# Non-indexed triangles
			var vc = arrs[Mesh.ARRAY_VERTEX].size() if arrs[Mesh.ARRAY_VERTEX] != null else 0
			for i in range(0, vc, 3):
				if i + 2 < vc:
					union_sets.call(start_id + i, start_id + i + 1)
					union_sets.call(start_id + i + 1, start_id + i + 2)
			continue

		# Indexed triangles
		for i in range(0, indices.size(), 3):
			if i + 2 < indices.size():
				var gv0 = start_id + indices[i]
				var gv1 = start_id + indices[i + 1]
				var gv2 = start_id + indices[i + 2]
				union_sets.call(gv0, gv1)
				union_sets.call(gv1, gv2)

	# --- 2. Optional: connect by overlapping vertex positions (across surfaces) ---
	if merge_overlapping:
		var pos_to_verts := {}
		for s in range(surface_count):
			var start := surface_vertex_starts[s]
			var verts: PackedVector3Array = surface_arrays_list[s][Mesh.ARRAY_VERTEX]
			if verts == null:
				continue
			for local_v in range(verts.size()):
				var pos: Vector3 = verts[local_v]
				var gvid := start + local_v
				if not pos_to_verts.has(pos):
					pos_to_verts[pos] = PackedInt32Array()
				pos_to_verts[pos].append(gvid)

		for pos in pos_to_verts:
			var vlist: PackedInt32Array = pos_to_verts[pos]
			if vlist.size() > 1:
				var first := vlist[0]
				for k in range(1, vlist.size()):
					union_sets.call(first, vlist[k])

	# --- 3. Collect faces per component ---
	var comp_to_surf_tris := {}      # root -> {surf_idx: Array[Array[int]] }  (list of [v0,v1,v2])
	var comp_to_full_surfs := {}     # root -> Array[int]  (list of surf indices for non-triangle surfaces)

	for s in range(surface_count):
		var start := surface_vertex_starts[s]
		var arrs = surface_arrays_list[s]
		var prim := surface_primitive_types[s]

		if prim != Mesh.PRIMITIVE_TRIANGLES:
			if surface_vertex_counts[s] > 0:
				var root := find.call(start)
				if not comp_to_full_surfs.has(root):
					comp_to_full_surfs[root] = []
				comp_to_full_surfs[root].append(s)
			continue

		# Triangle surface
		var indices = arrs[Mesh.ARRAY_INDEX]
		var has_indices = indices != null and not indices.is_empty()
		var vc = arrs[Mesh.ARRAY_VERTEX].size() if arrs[Mesh.ARRAY_VERTEX] != null else 0
		var num_tris = (indices.size() / 3) if has_indices else (vc / 3)

		for t in range(num_tris):
			var v0_local: int
			var v1_local: int
			var v2_local: int
			if has_indices:
				v0_local = indices[t * 3]
				v1_local = indices[t * 3 + 1]
				v2_local = indices[t * 3 + 2]
			else:
				v0_local = t * 3
				v1_local = t * 3 + 1
				v2_local = t * 3 + 2

			var gv0 := start + v0_local
			var root := find.call(gv0)

			if not comp_to_surf_tris.has(root):
				comp_to_surf_tris[root] = {}
			if not comp_to_surf_tris[root].has(s):
				comp_to_surf_tris[root][s] = []
			comp_to_surf_tris[root][s].append([v0_local, v1_local, v2_local])

	# --- 4. Build output meshes ---
	var separated_meshes: Array[Mesh] = []
	var processed_roots := {}

	# Process components that have triangle faces
	for root in comp_to_surf_tris:
		if processed_roots.has(root):
			continue
		processed_roots[root] = true

		var new_mesh := ArrayMesh.new()

		# --- Triangle surfaces in this component ---
		if comp_to_surf_tris.has(root):
			var surf_tris_dict: Dictionary = comp_to_surf_tris[root]
			for surf_idx in surf_tris_dict:
				var tris: Array = surf_tris_dict[surf_idx]
				if tris.is_empty():
					continue

				# Collect used local vertices
				var used_set := {}
				for tri in tris:
					used_set[tri[0]] = true
					used_set[tri[1]] = true
					used_set[tri[2]] = true

				var used_local_verts: Array = used_set.keys()
				used_local_verts.sort()

				var num_used := used_local_verts.size()
				var local_to_new := {}
				for i in num_used:
					local_to_new[used_local_verts[i]] = i

				var orig_arrs: Array = surface_arrays_list[surf_idx]
				var orig_verts: PackedVector3Array = orig_arrs[Mesh.ARRAY_VERTEX]
				var mat := surface_materials[surf_idx]

				# Build new arrays for this surface
				var new_arrs := Array()
				new_arrs.resize(Mesh.ARRAY_MAX)
				for i in range(Mesh.ARRAY_MAX):
					new_arrs[i] = null

				# Copy vertex attributes (handles stride for tangent/bones/weights/custom)
				var attr_list := [
					Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT,
					Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2,
					Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS,
					Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3
				]

				var orig_vert_count := orig_verts.size() if orig_verts != null else 0

				for attr in attr_list:
					if orig_arrs[attr] == null:
						continue
					var orig_data = orig_arrs[attr]
					var stride := 1
					if attr in [Mesh.ARRAY_TANGENT, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
						stride = 4
					elif attr in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
						if orig_vert_count > 0 and orig_data.size() > 0:
							stride = orig_data.size() / orig_vert_count

					match typeof(orig_data):
						TYPE_PACKED_VECTOR3_ARRAY:
							var nd := PackedVector3Array()
							nd.resize(num_used)
							for i in num_used:
								nd[i] = orig_data[used_local_verts[i]]
							new_arrs[attr] = nd
						TYPE_PACKED_VECTOR2_ARRAY:
							var nd := PackedVector2Array()
							nd.resize(num_used)
							for i in num_used:
								nd[i] = orig_data[used_local_verts[i]]
							new_arrs[attr] = nd
						TYPE_PACKED_COLOR_ARRAY:
							var nd := PackedColorArray()
							nd.resize(num_used)
							for i in num_used:
								nd[i] = orig_data[used_local_verts[i]]
							new_arrs[attr] = nd
						TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_BYTE_ARRAY:
							var nd
							if typeof(orig_data) == TYPE_PACKED_FLOAT32_ARRAY:
								nd = PackedFloat32Array()
							elif typeof(orig_data) == TYPE_PACKED_INT32_ARRAY:
								nd = PackedInt32Array()
							else:
								nd = PackedByteArray()
							nd.resize(num_used * stride)
							for i in num_used:
								var old_base = used_local_verts[i] * stride
								var new_base := i * stride
								for k in range(stride):
									nd[new_base + k] = orig_data[old_base + k]
							new_arrs[attr] = nd

				# Indices
				var new_indices := PackedInt32Array()
				new_indices.resize(tris.size() * 3)
				var idx := 0
				for tri in tris:
					new_indices[idx] = local_to_new[tri[0]]; idx += 1
					new_indices[idx] = local_to_new[tri[1]]; idx += 1
					new_indices[idx] = local_to_new[tri[2]]; idx += 1
				new_arrs[Mesh.ARRAY_INDEX] = new_indices

				# Add surface
				new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, new_arrs)
				var new_s_idx := new_mesh.get_surface_count() - 1
				if mat != null:
					new_mesh.surface_set_material(new_s_idx, mat)

		# --- Full (non-triangle) surfaces in this component ---
		if comp_to_full_surfs.has(root):
			for surf_idx in comp_to_full_surfs[root]:
				var orig_arrs: Array = surface_arrays_list[surf_idx]
				var prim := surface_primitive_types[surf_idx]
				var mat := surface_materials[surf_idx]

				new_mesh.add_surface_from_arrays(prim, orig_arrs)
				var new_s_idx := new_mesh.get_surface_count() - 1
				if mat != null:
					new_mesh.surface_set_material(new_s_idx, mat)

		if new_mesh.get_surface_count() > 0:
			separated_meshes.append(new_mesh)

	# Process any remaining full-surface-only components
	for root in comp_to_full_surfs:
		if processed_roots.has(root):
			continue
		processed_roots[root] = true

		var new_mesh := ArrayMesh.new()
		for surf_idx in comp_to_full_surfs[root]:
			var orig_arrs: Array = surface_arrays_list[surf_idx]
			var prim := surface_primitive_types[surf_idx]
			var mat := surface_materials[surf_idx]

			new_mesh.add_surface_from_arrays(prim, orig_arrs)
			var new_s_idx := new_mesh.get_surface_count() - 1
			if mat != null:
				new_mesh.surface_set_material(new_s_idx, mat)

		if new_mesh.get_surface_count() > 0:
			separated_meshes.append(new_mesh)

	return separated_meshes
