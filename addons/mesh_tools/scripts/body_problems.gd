enum CollisionType {
	SPHERE,   # Bounding sphere (encloses the mesh AABB)
	CUBE,     # Axis-aligned bounding box
	CONVEX,   # Convex hull generated from the mesh (recommended for most situations)
	MESH      # Original mesh as a concave trimesh (most accurate but expensive)
}

## Creates and returns a new RigidBody3D with the given mesh and physics properties.
## The visual MeshInstance3D and appropriate CollisionShape3D are added as children.
static func create_rigid_body_from_mesh(
	mesh: Mesh,
	friction: float = 1.0,
	bounciness: float = 0.1,
	collision_type: CollisionType = CollisionType.CONVEX,
) -> RigidBody3D:
	if mesh == null:
		push_error("create_rigid_body_from_mesh: mesh is null")
		return null

	var rigid_body := RigidBody3D.new()

	# Visual representation
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	rigid_body.add_child(mesh_instance)

	# Create the collision
	rigid_body.add_child(_create_collision(mesh, collision_type))

	# Physics material (friction + bounciness)
	var phys_mat := PhysicsMaterial.new()
	phys_mat.friction = friction
	phys_mat.bounce = bounciness
	rigid_body.physics_material_override = phys_mat

	return rigid_body


static func create_static_body_from_mesh(
	mesh: Mesh,
	friction: float = 1.0,
	bounciness: float = 0.1,
	collision_type : CollisionType = CollisionType.CONVEX
) -> StaticBody3D:
	if mesh == null:
		push_error("create_static_body_from_mesh: mesh is null")
		return null

	var static_body := StaticBody3D.new()

	# Visual representation
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	static_body.add_child(mesh_instance)

	# Create the collision
	static_body.add_child(_create_collision(mesh, collision_type))

	# Physics material (friction + bounciness)
	var phys_mat := PhysicsMaterial.new()
	phys_mat.friction = friction
	phys_mat.bounce = bounciness
	static_body.physics_material_override = phys_mat

	return static_body


static func create_csg_body_from_mesh(
	mesh: Mesh,
	use_collision: bool = false,
	operation:CSGShape3D.Operation = CSGShape3D.Operation.OPERATION_UNION
) -> CSGMesh3D:
	if mesh == null:
		push_warning("create_csg_mesh: Received null mesh")
		return null

	var csg := CSGMesh3D.new()
	csg.mesh = mesh
	csg.operation = operation
	csg.use_collision = use_collision

	# Optional: sensible defaults when collision is enabled
	if use_collision:
		csg.collision_layer = 0x3
		csg.collision_mask = 1
		csg.collision_priority = 1.0

	return csg





## This sets the center of mass of the [RigidBody3D], by using the AABB bounding box, or calculating it by volume.
static func set_center_of_mass(rigid_body: RigidBody3D, fancy: bool):
	# Get the body's mesh (sloppy but good enough)
	var mesh: Mesh
	for child in rigid_body.get_children():
		if child is MeshInstance3D:
			mesh = child.mesh
			break
	# Set center point for physics
	rigid_body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	var mesh_local_center: Vector3
	var com_offset: Vector3
	if not fancy:
		mesh_local_center = mesh.get_aabb().get_center()
		com_offset = mesh_local_center
	else:
		com_offset = _get_mesh_centroid(mesh, true)
	rigid_body.center_of_mass = com_offset


## Helper: Gets the center of a given mesh, either by average (fast), or by the physical volume (very accurate)
static func _get_mesh_centroid(mesh: Mesh, volumetric: bool = false):
	if not mesh:
		return Vector3.ZERO

	if not volumetric:
		var sum := Vector3.ZERO
		var count := 0

		var faces: PackedVector3Array = mesh.get_faces()
		if faces.is_empty():
			return Vector3.ZERO

		for v in faces:
			sum += v

		print("This works")
		return sum / faces.size()
	else:
		return _get_mesh_volumetric_center(mesh)


## Calculates the volume of a closed triangular mesh.
## Returns the absolute volume (in mesh units³).
## [br][br]
## Assumptions:
## [br]    The mesh is closed and manifold (watertight).
## [br]    Triangles have consistent winding order (clockwise or counterclockwise).
## [br]    Surfaces use [Mesh].PRIMITIVE_TRIANGLES.
## [br]    Non-closed or self-intersecting meshes may give inaccurate results.
static func calculate_mesh_volume(mesh: Mesh) -> float:
	if mesh == null:
		return 0.0

	var total_volume: float = 0.0

	for surface_idx in mesh.get_surface_count():
		var primitive = mesh.surface_get_primitive_type(surface_idx)
		if primitive != Mesh.PRIMITIVE_TRIANGLES:
			# Only triangle lists are supported for simplicity
			continue

		var arrays := mesh.surface_get_arrays(surface_idx)
		if arrays.is_empty():
			continue

		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if vertices.is_empty():
			continue

		var indices: PackedInt32Array = PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] != null:
			indices = arrays[Mesh.ARRAY_INDEX]

		if indices.is_empty():
			# Non-indexed mesh (vertices listed in groups of 3)
			for i in range(0, vertices.size() - 2, 3):
				var v0 := vertices[i]
				var v1 := vertices[i + 1]
				var v2 := vertices[i + 2]
				total_volume += _signed_tetra_volume(v0, v1, v2)
		else:
			# Indexed mesh
			for i in range(0, indices.size() - 2, 3):
				var idx0 := indices[i]
				var idx1 := indices[i + 1]
				var idx2 := indices[i + 2]

				if idx0 >= vertices.size() or idx1 >= vertices.size() or idx2 >= vertices.size():
					continue

				var v0 := vertices[idx0]
				var v1 := vertices[idx1]
				var v2 := vertices[idx2]
				total_volume += _signed_tetra_volume(v0, v1, v2)

	return abs(total_volume)


## Helper: signed volume of a tetrahedron formed by origin + triangle
static func _signed_tetra_volume(v0: Vector3, v1: Vector3, v2: Vector3) -> float:
	return v0.dot(v1.cross(v2)) / 6.0


## Helper: Returns the volumetric center (center of mass) of a [Mesh] in its local space.
## [br]Assumes the mesh is closed, triangulated, and consistently oriented.
## [br]Returns [Vector3].ZERO on invalid/empty mesh.
static func _get_mesh_volumetric_center(mesh: Mesh) -> Vector3:
	if mesh == null:
		push_warning("get_mesh_volumetric_center: mesh is null")
		return Vector3.ZERO

	var faces: PackedVector3Array = mesh.get_faces()
	if faces.size() == 0 or faces.size() % 3 != 0:
		push_warning("get_mesh_volumetric_center: invalid face data (not triangulated or empty)")
		return Vector3.ZERO

	var total_volume: float = 0.0
	var weighted_sum: Vector3 = Vector3.ZERO

	for i in range(0, faces.size(), 3):
		var v1: Vector3 = faces[i]
		var v2: Vector3 = faces[i + 1]
		var v3: Vector3 = faces[i + 2]

		# Signed volume of tetrahedron formed by origin + triangle
		# (positive if winding is consistent with outward normals)
		var vol: float = v1.dot(v2.cross(v3)) / 6.0
		total_volume += vol

		# Centroid of this tetrahedron = average of its 4 vertices (origin + v1,v2,v3)
		var tet_centroid: Vector3 = (v1 + v2 + v3) / 4.0
		weighted_sum += tet_centroid * vol

	if abs(total_volume) < 1e-8:
		push_warning("get_mesh_volumetric_center: mesh has zero or near-zero volume")
		return Vector3.ZERO

	return weighted_sum / total_volume


## Helper: Create a [CollisionShape3D] based on the mesh and collision_type given, and return that node.
##[br]Allowed collision types are:
##[br]    SPHERE
##[br]    CUBE
##[br]    CONVEX
##[br]    MESH
##[br][br]
##WARNING: Using MESH as a collision option only works with [StaticBody3D], Godot does not support collison trimesh with [RigidBody3D].
static func _create_collision(mesh: Mesh, collision_type) -> CollisionShape3D:
	var collision_shape := CollisionShape3D.new()
	var aabb := mesh.get_aabb()
	var center := aabb.get_center()
	var shape: Shape3D

	match collision_type:
		CollisionType.SPHERE:
			var sphere := SphereShape3D.new()
			sphere.radius = aabb.size.length() / 2.0   # enclosing sphere
			shape = sphere
			collision_shape.position = center
		CollisionType.CUBE:
			var box := BoxShape3D.new()
			box.size = aabb.size
			shape = box
			collision_shape.position = center
		CollisionType.CONVEX:
			shape = mesh.create_convex_shape()
		CollisionType.MESH: # WARNING: Only supported by StaticBody3D
			push_warning("Using a trimesh for collision is only supported by StaticBody3D")
			shape = mesh.create_trimesh_shape()
	collision_shape.shape = shape
	return collision_shape
