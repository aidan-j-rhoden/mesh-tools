extends Node3D

func _ready() -> void:
	await get_tree().create_timer(5).timeout
	the_test()


# Called when the node enters the scene tree for the first time.
func the_test() -> void:
	await MeshTools.CleanUp.rebuild_csg_node($CSGBox3D/CSGSphere3D5, true) # Compile the CSG node tree, and ALL it's children into one CSGMesh node
	print("first one finished")

	$CSGBox3D.mesh = await ThreadRunner.run_async(MeshTools.CleanUp.merge_by_distance, [$CSGBox3D.mesh, 0.02])
	print("second one finished")

	var separated_meshes = await ThreadRunner.run_async(MeshTools.Islands.separate_mesh_islands, [$CSGBox3D.mesh, true])
	print("third one finished")
	for m in separated_meshes:
		var mi = MeshTools.BodyProblems.create_rigid_body_from_mesh(
			m, # The mesh
			1.0, # Friction
			0.3, # Bounciness
			MeshTools.BodyProblems.CollisionType.CUBE, # Type of collision mesh generated
		)
		add_child(mi)
		mi.global_position = $CSGBox3D.global_position
		MeshTools.BodyProblems.set_center_of_mass(mi, true)
		#print(MeshTools.BodyProblems.calculate_mesh_volume(m))
	print("forth one finished")
	$CSGBox3D.queue_free()

	MeshTools.BodyProblems.set_center_of_mass($RigidBody3D, true)
	var new_thing = MeshTools.BodyProblems.create_csg_body_from_mesh($RigidBody3D/MeshInstance3D.mesh, true)
	add_child(new_thing)
	new_thing.position = $RigidBody3D.position


func _input(_event: InputEvent) -> void:
	if Input.is_action_just_pressed("quit"):
		get_tree().quit()
