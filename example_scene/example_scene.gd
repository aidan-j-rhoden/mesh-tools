extends Node3D

func _ready() -> void:
	await get_tree().create_timer(5).timeout
	the_test()


# Called when the node enters the scene tree for the first time.
func the_test() -> void:
	await MeshTools.CleanUp.rebuild_csg_node($CSGBox3D/CSGSphere3D5, true) # Compile the CSG node tree, and ALL it's children into one CSGMesh node
	print("first one finished")

	# Merge the newly compiled mesh by distance, cleaning up geometry by removing doubled vertices.
	$CSGBox3D.mesh = await ThreadRunner.run_async(MeshTools.CleanUp.merge_by_distance, [$CSGBox3D.mesh, 0.02])
	print("second one finished")

	# Separate the big mesh by floating islands
	var separated_meshes = await ThreadRunner.run_async(MeshTools.Islands.separate_mesh_islands, [$CSGBox3D.mesh, true])
	print("third one finished")

	# For each separated mesh, create a new rigid body and add it to the scene
	for m in separated_meshes:
		var mi = MeshTools.BodyProblems.create_rigid_body_from_mesh(
			m, # The mesh
			1.0, # Friction
			0.3, # Bounciness
			MeshTools.BodyProblems.CollisionType.CUBE, # Type of collision mesh generated
		)
		add_child(mi)
		mi.global_position = $CSGBox3D.global_position
		# Make sure to set the center of mass of any new mass, as it defaults to the mesh origin, and these all have the same origin.  If left unalterd, physics will be comedically wrong.
		MeshTools.BodyProblems.set_center_of_mass(mi, true)
		# Perhaps you want to make sure we're not preserving any islands that are too small?  This checks the volume.
		print(MeshTools.Islands.calculate_mesh_volume(m))
	print("forth one finished")
	$CSGBox3D.queue_free() # We don't need this anymore, but only delete it after everything else is done for visuals.  This runs in one go, and therefore doesn't matter, but it's good practice.

	# Random tests on the random sphere
	MeshTools.BodyProblems.set_center_of_mass($RigidBody3D, true)
	var new_thing = MeshTools.BodyProblems.create_csg_body_from_mesh($RigidBody3D/MeshInstance3D.mesh, true)
	add_child(new_thing)
	new_thing.position = $RigidBody3D.position


func _input(_event: InputEvent) -> void:
	if Input.is_action_just_pressed("quit"):
		get_tree().quit()
