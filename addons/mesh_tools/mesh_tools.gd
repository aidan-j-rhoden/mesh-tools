class_name MeshTools


## Islands has the methods:
## [br]separate_mesh_islands
## [br]    Takes a [param mesh], and returns an array of all the floating mesh islands separated out of it.
## [br]calculate_mesh_volume
## [br]    Returns the given [param mesh]'s volume, in the cubed unit of said mesh. (typically cubic meters) It is assumed the mesh is watertight.
const Islands = preload("res://addons/mesh_tools/scripts/island_separate.gd")

## CleanUp has the methods:
## [br]rebuild_csg_node
## [br]    Bakes any CSG node and all it's children into one new [CSGMesh3D].  The children are then removed after.
## [br]merge_by_distance
## [br]    Takes a [param mesh] and performs a merge by distance operation on it, useful after a CSG operation.
const CleanUp = preload("res://addons/mesh_tools/scripts/mesh_cleanup.gd")

## BodyProblems has the methods:
## [br]create_rigid_body_from_mesh
## [br]    Creates a [RigidBody3D] from a given mesh, and defaults to reasonable physics parameters if none are given.
## [br]create_static_body_from_mesh
## [br]    Creates a [StaticBody3D] from a given mesh, and defaults to reasonable physics parameters if none are given.
## [br]create_csg_body_from_mesh
## [br]    Creates a [CSGMesh3D] from a given mesh, and does not use collision by default.
## [br]set_center_of_mass
## [br]    A function that is almost mandatory to run on [RigidBody3D]s generated from create_rigid_body_from_mesh
const BodyProblems = preload("res://addons/mesh_tools/scripts/body_problems.gd")
