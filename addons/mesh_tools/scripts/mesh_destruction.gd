## Utility for slicing a Mesh with a plane defined by a MeshInstance3D.  Assumes the cutting plane fully intersects the target mesh.
## [param plane_mi] should use a PlaneMesh (orientation is respected).
## The plane is evaluated in the local space of [param target_mesh] (i.e. [param plane_mi].transform is treated as relative to the mesh origin).
## Returns an Array of two Meshes: [negative-side, positive-side] (relative to the plane normal).  Either entry may be null if a side is empty.
static func slice_mesh(
	plane_mi: MeshInstance3D,
	target_mesh: Mesh,
	cut_material: Material = null
) -> Array:
	# ---- Build a Transform3D whose +Z axis is the cutting-plane normal ----
	var normal: Vector3 = _get_plane_normal(plane_mi)
	var origin: Vector3 = plane_mi.transform.origin

	# Construct an orthonormal basis with Z = normal
	var up: Vector3 = Vector3.UP
	if absf(normal.dot(up)) > 0.999:
		up = Vector3.RIGHT
	var x_axis: Vector3 = up.cross(normal).normalized()
	var y_axis: Vector3 = normal.cross(x_axis).normalized()
	var basis: Basis = Basis(x_axis, y_axis, normal)
	var slice_transform: Transform3D = Transform3D(basis, origin)

	return _slice_with_csg(slice_transform, target_mesh, cut_material)


static func check_penetration(slicing_plane: MeshInstance3D, target_mesh: Mesh) -> bool:
	var triangle_mesh: TriangleMesh = target_mesh.generate_triangle_mesh()

	for v in slicing_plane.mesh.get

	var result: Dictionary = triangle_mesh.intersect_segment(from, to)

	if not result.is_empty():
		var hit_position: Vector3 = result.position
		var hit_normal: Vector3 = result.normal
		var face_index: int = result.face_index
		return true

	return Turds


## Internal implementation using Godot's CSG system (handles concave meshes, preserves UVs from the original surfaces, produces sharp cut-face normals).
static func _slice_with_csg(
	slice_transform: Transform3D,
	mesh: Mesh,
	cut_material: Material
) -> Array:
	var root: Window = Engine.get_main_loop().root as Window

	var combiner: CSGCombiner3D = CSGCombiner3D.new()
	var obj_csg: CSGMesh3D = CSGMesh3D.new()
	obj_csg.mesh = mesh

	var slicer_csg: CSGMesh3D = CSGMesh3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.material = cut_material
	slicer_csg.mesh = box

	root.add_child(combiner)
	combiner.add_child(obj_csg)
	combiner.add_child(slicer_csg)
	slicer_csg.transform = slice_transform

	# Expand the cutting box so it completely covers one half-space of the mesh.
	var max_at: Vector3 = Vector3(-INF, -INF, -INF)
	var min_at: Vector3 = Vector3(INF, INF, INF)
	var faces: PackedVector3Array = mesh.get_faces()
	for v: Vector3 in faces:
		var lv: Vector3 = slicer_csg.to_local(v)
		max_at = max_at.max(lv)
		min_at = min_at.min(lv)

	# Slight padding guarantees a clean intersection.
	max_at += Vector3(0.1, 0.1, 0.1)
	min_at -= Vector3(0.1, 0.1, 0.1)
	min_at.z = 0.0  # plane sits at local Z = 0

	slicer_csg.position = slicer_csg.to_global((max_at + min_at) * 0.5)
	box.size = max_at - min_at

	# Produce the two halves
	var out_neg: Mesh = null
	var out_pos: Mesh = null

	slicer_csg.operation = CSGShape3D.OPERATION_SUBTRACTION
	combiner._update_shape()
	var meshes: Array = combiner.get_meshes()
	if meshes.size() > 1 and meshes[1] is Mesh:
		out_neg = meshes[1]

	slicer_csg.operation = CSGShape3D.OPERATION_INTERSECTION
	combiner._update_shape()
	meshes = combiner.get_meshes()
	if meshes.size() > 1 and meshes[1] is Mesh:
		out_pos = meshes[1]

	# Cleanup
	combiner.queue_free()

	return [out_neg, out_pos]


## Extracts the outward normal from a MeshInstance3D that holds a PlaneMesh (falls back to local +Y if the mesh is not a PlaneMesh).
static func _get_plane_normal(plane_mi: MeshInstance3D) -> Vector3:
	var pm: PlaneMesh = plane_mi.mesh as PlaneMesh
	var n: Vector3
	if pm != null:
		match pm.orientation:
			PlaneMesh.Orientation.FACE_X:
				n = plane_mi.transform.basis.x
			PlaneMesh.Orientation.FACE_Y:
				n = plane_mi.transform.basis.y
			PlaneMesh.Orientation.FACE_Z:
				n = plane_mi.transform.basis.z
			_:
				n = plane_mi.transform.basis.y
	else:
		n = plane_mi.transform.basis.y
	return n.normalized()
