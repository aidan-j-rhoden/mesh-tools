extends Node3D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	the_test()


func the_test() -> void:
	print("Started tests")
	await MeshTools.CleanUp.rebuild_csg_node($CSGBox3D/CSGSphere3D5, true) # Compile the CSG node tree, and ALL it's children into one CSGMesh node.  Important to use the await keyword, becuase this critically alters the structure of the mesh and nodes.
	print("Rebuilt CSG tree")

	# Merge the newly compiled mesh by distance, cleaning up geometry by removing doubled vertices.  We run it in a separate thread to not bog down the main loop, letting it calculate in the background.
	$CSGBox3D.mesh = await ThreadRunner.run_async(MeshTools.CleanUp.merge_by_distance, [$CSGBox3D.mesh, 0.02])
	print("Merged the mesh vertices by distance")

	# Separate the big mesh by floating islands
	var separated_meshes: Array[Mesh] = await ThreadRunner.run_async(MeshTools.Islands.separate_mesh_islands, [$CSGBox3D.mesh, true])
	print("Separated the mesh by islands")

	# For each separated mesh, create a new rigid body and add it to the scene
	for m in separated_meshes:
		# Perhaps you want to make sure we're not preserving any islands that are too small?  Run this before any other operations on the mesh to not waste time.  Why generate resourses that you're just going to delete anyway?
		# This checks the volume, in cubic meters.  A value of 0.6 here will elimate all the blue cubes but leave the white ones.
		if MeshTools.Islands.calculate_mesh_volume(m) <= 0.6:
			continue

		m = MeshTools.MeshEffects.shade_smooth_by_angle(m, 35.0) # Very important.  After welding, all the normals are wacked up.  This works exactly like Blender's shade auto-smooth.
		var mi: RigidBody3D = MeshTools.BodyProblems.create_rigid_body_from_mesh(
			m, # The mesh
			1.0, # Friction
			0.3, # Bounciness
			MeshTools.BodyProblems.CollisionType.CUBE, # Type of collision mesh generated.  We choose a cube here because that's literally perfect.  The other options are SPHERE, CONVEX, and MESH.  MESH only works with StaticBody3Ds.
		)
		add_child(mi)
		mi.global_position = $CSGBox3D.global_position
		# Make sure to set the center of mass of any new mass, as it defaults to the mesh origin, and these all have the same origin.  If left unalterd, physics will be comedically wrong.
		MeshTools.BodyProblems.set_center_of_mass(mi, true)
	print("Created rigid bodies from mesh islands")
	$CSGBox3D.queue_free() # We don't need this anymore, but only delete it after everything else is done, both to avoid potential visual stutter, and more importantly, dependency issues.

	# Random tests on the random sphere
	MeshTools.BodyProblems.set_center_of_mass($RigidBody3D, true)
	var new_mesh: Mesh = MeshTools.MeshEffects.randomize_mesh($RigidBody3D/MeshInstance3D.mesh, 0.01, 0.5, 0.8)
	$RigidBody3D/MeshInstance3D.mesh = new_mesh
	# For some reason the winding is reversed only for MeshInstance3D, (not the csg node) so we need to invert the normal vectors to get proper lighting.  Absolutely no clue why or how this happens.
	$RigidBody3D/MeshInstance3D.mesh = MeshTools.CleanUp.invert_normal_vectors($RigidBody3D/MeshInstance3D.mesh)
	#$RigidBody3D/MeshInstance3D.mesh = MeshTools.CleanUp.flip_face_normals($RigidBody3D/MeshInstance3D.mesh)
	var new_thing: CSGMesh3D = MeshTools.BodyProblems.create_csg_body_from_mesh(new_mesh, true)
	add_child(new_thing)
	new_thing.position = $RigidBody3D.position
	
	await get_tree().create_timer(2).timeout

	await MeshTools.CleanUp.rebuild_csg_node($CSGBox3D3)
	$CSGBox3D3.mesh = await ThreadRunner.run_async(MeshTools.CleanUp.merge_by_distance, [$CSGBox3D3.mesh, 0.01])
	$CSGBox3D3.mesh = MeshTools.MeshEffects.shade_smooth_by_angle($CSGBox3D3.mesh, 35.0)

	# TODO structure check here

	var cuts: Array = MeshTools.MeshDestruction.slice_mesh($ThisOneGetsIt/TheGiver, $ThisOneGetsIt.mesh, load("res://example_scene/cut.tres"))
	$ThisOneGetsIt.mesh = cuts[0]
	var base = MeshTools.BodyProblems.create_static_body_from_mesh(cuts[0], 0.7, 0.0, MeshTools.BodyProblems.CollisionType.CONVEX)
	base.collision_layer = 0b11
	$ThisOneGetsIt.add_child(base)
	var part: RigidBody3D = MeshTools.BodyProblems.create_rigid_body_from_mesh(cuts[1], 0.9)
	MeshTools.BodyProblems.set_center_of_mass(part, true)
	part.mass = 2000.0
	$ThisOneGetsIt.add_child(part)
	$ThisOneGetsIt.mesh = null
	$ThisOneGetsIt/TheGiver.queue_free()


func _input(_event: InputEvent) -> void:
	if Input.is_action_just_pressed("quit"):
		get_tree().quit()
