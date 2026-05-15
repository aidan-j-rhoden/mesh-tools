# Mesh Tools
This is a bunch of helper functions that I've created for one of my projects.
<br>It suffered from the worst scope creep imaginable.

## Clean Up:
### `rebuild_csg_node`
- Bakes any CSG node and all it's children into one new CSGMesh3D.  The children are then removed after.
### `merge_by_distance`
- Takes a mesh and performs a merge by distance operation on it, useful after a CSG operation. 

## Body Problems:
### `create_rigid_body_from_mesh`
- Creates a RigidBody3D from a given mesh, and defaults to reasonable physics parameters if none are given.
### `create_static_body_from_mesh`
- Creates a StaticBody3D from a given mesh, and defaults to reasonable physics parameters if none are given.
### `create_csg_body_from_mesh`
- Creates a CSGMesh3D from a given mesh, and does not use collision by default.
### `set_center_of_mass`
- A function that is almost mandatory to run on RigidBody3Ds generated from create_rigid_body_from_mesh 

## Islands:
### `calculate_mesh_volume`
- Returns the given mesh's volume, in the cubed unit of said mesh. (typically cubic meters) It is assumed the mesh is watertight.
### `separate_mesh_islands`
- Takes a mesh, and returns an array of all the floating mesh islands separated out of it.

There is an example scene and script that uses just about every function in the toolset.
<br>**Warning**: The demo scene is very intensive, and an extreme edge case way beyond realistic applications.

Hopefully you will find this helpful in some way or another.
