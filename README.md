# Mesh Tools
This is a bunch of helper functions that I've created for one of my projects.
<br>It suffered from the worst scope creep imaginable.

## Clean Up:
- <br>rebuild_csg_node
 <br>    Bakes any CSG node and all it's children into one new CSGMesh3D.  The children are then removed after.
 <br>merge_by_distance
 <br>    Takes a mesh and performs a merge by distance operation on it, useful after a CSG operation. 

## Body Problems:
- BodyProblems has the methods:
<br>create_rigid_body_from_mesh
<br>    Creates a RigidBody3D from a given mesh, and defaults to reasonable physics parameters if none are given.
<br>create_static_body_from_mesh
<br>    Creates a StaticBody3D from a given mesh, and defaults to reasonable physics parameters if none are given.
<br>create_csg_body_from_mesh
<br>    Creates a CSGMesh3D from a given mesh, and does not use collision by default.
<br>set_center_of_mass
<br>    A function that is almost mandatory to run on RigidBody3Ds generated from create_rigid_body_from_mesh 

## Islands:
- yaada

There is an example scene and script that uses just about every function in the toolset.
<br>**Warning**: The demo scene is very intensive, and an extreme edge case way beyond realistic applications.

Hopefully you will find this helpful in some way or another.
