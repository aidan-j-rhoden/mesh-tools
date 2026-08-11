extends Node3D

static var player_transform = null
static var camera_rotation = null
var melt_material: ShaderMaterial = ShaderMaterial.new()

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	melt_material.shader = preload("res://example_scene/melted_metal.gdshader")
	melt_material.set_shader_parameter("roughness", 0.5)
	melt_material.set_shader_parameter("noise_scale", 50.0)
	melt_material.set_shader_parameter("flow_speed", 0.0)
	melt_material.set_shader_parameter("fresnel_power", 6.0)
	melt_material.set_shader_parameter("edge_glow_strength", 10.0)
	melt_material.set_shader_parameter("vein_threshold", 0.377)
	melt_material.set_shader_parameter("vein_glow_strength", 5.2)
	melt_material.set_shader_parameter("pulse_speed", 2.0)
	melt_material.set_shader_parameter("displacement", 0.0)
 
	if player_transform != null:
		$Character.transform = player_transform
		$Character/Head.rotation = camera_rotation
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

	# Thickness tests
	await MeshTools.CleanUp.rebuild_csg_node($CSGBox3D3)
	$CSGBox3D3.mesh = await ThreadRunner.run_async(MeshTools.CleanUp.merge_by_distance, [$CSGBox3D3.mesh, 0.01])
	$CSGBox3D3.mesh = MeshTools.MeshEffects.shade_smooth_by_angle($CSGBox3D3.mesh, 35.0)
	# TODO structure check here

	# Slicing checks
	if not MeshTools.MeshDestruction.check_penetration($ThisOneGetsIt/TheUndersizedButVeryAveragelySizedGiver, $ThisOneGetsIt):
		$ThisOneGetsIt/TheUndersizedButVeryAveragelySizedGiver.queue_free() # It's just too small for the job, sorry king size does matter 😭

	var cuts: Array = MeshTools.MeshDestruction.slice_mesh($ThisOneGetsIt/TheGiver, $ThisOneGetsIt.mesh, melt_material)
	$ThisOneGetsIt.mesh = cuts[0]
	var base: StaticBody3D = MeshTools.BodyProblems.create_static_body_from_mesh(cuts[0], 0.7, 0.0, MeshTools.BodyProblems.CollisionType.CONVEX)
	base.collision_layer = 0b11 # This is just for this specific player controller system, not super important.
	$ThisOneGetsIt.add_child(base)
	var part: RigidBody3D = MeshTools.BodyProblems.create_rigid_body_from_mesh(cuts[1], 0.9)
	MeshTools.BodyProblems.set_center_of_mass(part, true)
	part.mass = 2000.0
	$ThisOneGetsIt.add_child(part)
	$ThisOneGetsIt.mesh = null # Clear the original mesh
	$ThisOneGetsIt/TheGiver.queue_free()


func _input(_event: InputEvent) -> void:
	if Input.is_action_just_pressed("quit"):
		get_tree().quit()
	if Input.is_action_just_pressed("restart"):
		player_transform = $Character.transform
		camera_rotation = $Character/Head.rotation
		get_tree().reload_current_scene()
