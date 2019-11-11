# MIT License
#
# Copyright (c) 2019 Robert B. Colton
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

extends Spatial

signal subdivision_level_changed
signal rotation_changed
signal scale_changed

onready var meshNode = $DisplayMesh
var controlMesh
var subdivisionLevel = 0

onready var facesNode = $Control/StatePanel/HBoxContainer/PropsGrid/FacesState

func read_obj_mesh(filename):
	var f = File.new()
	f.open(filename, File.READ)
	var surfTool = SurfaceTool.new()

	surfTool.begin(Mesh.PRIMITIVE_TRIANGLES)
	surfTool.add_smooth_group(true)
	while not f.eof_reached():
		var line = f.get_line()
		if line.empty() or line.begins_with('#'): continue
		var args = line.split(' ', false)

		if args[0] == 'v':
			surfTool.add_vertex(Vector3(float(args[1]), float(args[2]), float(args[3])))
		elif args[0] == 'vt':
			surfTool.add_uv(Vector2(float(args[1]), float(args[2])))
		elif args[0] == 'vn':
			surfTool.add_normal(Vector3(float(args[1]), float(args[2]), float(args[3])))
		elif args[0] == 'f':
			for i in range(args.size()-1, 0, -1):
				surfTool.add_index(int(args[i]) - 1)

	f.close()
	return surfTool

func get_vertex_edge_neighbor(mdt, vi, ei):
	var evi1 = mdt.get_edge_vertex(ei, 0)
	var evi2 = mdt.get_edge_vertex(ei, 1)

	return evi1 if evi1 != vi else evi2

func surface_tool_index_face(surfaceTool, i1, i2, i3):
	surfaceTool.add_index(i1)
	surfaceTool.add_index(i2)
	surfaceTool.add_index(i3)

func loop_subdivide(mesh, repeat):
	var mdt = MeshDataTool.new()
	for si in range(mesh.get_surface_count()):
		for sd in range(repeat):
			mdt.create_from_surface(mesh, 0)
			var surfTool = SurfaceTool.new()

			surfTool.begin(Mesh.PRIMITIVE_TRIANGLES)
			surfTool.add_smooth_group(true)

			# update even vertices
			for vi in range(mdt.get_vertex_count()):
				var oldv = mdt.get_vertex(vi)
				var edges = mdt.get_vertex_edges(vi)

				var n = edges.size()
				var beta = 3.0 / (8.0 * n) if n > 3 else 3.0/16.0

				var nvs = Vector3.ZERO
				for ei in edges:
					var nvi = get_vertex_edge_neighbor(mdt, vi, ei)
					nvs += mdt.get_vertex(nvi)

				var newv = oldv * (1.0 - n * beta) + nvs * beta
				surfTool.add_vertex(newv)

			# add odd vertices
			var oddEdges = {}
			for ei in range(mdt.get_edge_count()):
				var ef = mdt.get_edge_faces(ei)

				var evi1 = mdt.get_edge_vertex(ei, 0)
				var evi2 = mdt.get_edge_vertex(ei, 1)

				var newEdgeVertex = 0
				var evs = mdt.get_vertex(evi1) + mdt.get_vertex(evi2)
				if (ef.size() > 1): # interior
					var efvi1 = mdt.get_face_vertex(ef[0], 0)
					var efvi2 = mdt.get_face_vertex(ef[1], 1)
					var avs = mdt.get_vertex(efvi1) + mdt.get_vertex(efvi2)
					newEdgeVertex = (3.0/8.0) * evs + (1.0/8.0) * avs
				elif ef.size() == 1: # boundary
					newEdgeVertex = evs / 2

				surfTool.add_vertex(newEdgeVertex)
				var newIndex = mdt.get_vertex_count() + ei
				oddEdges[ei] = newIndex

			# reconnect faces
			for fi in range(mdt.get_face_count()):
				var e1 = mdt.get_face_edge(fi, 0)
				var e2 = mdt.get_face_edge(fi, 1)
				var e3 = mdt.get_face_edge(fi, 2)

				var e1o = oddEdges[e1]
				var e2o = oddEdges[e2]
				var e3o = oddEdges[e3]

				var fe1 = mdt.get_face_vertex(fi, 0)
				var fe2 = mdt.get_face_vertex(fi, 1)
				var fe3 = mdt.get_face_vertex(fi, 2)

				surface_tool_index_face(surfTool, e1o, e2o, e3o)
				surface_tool_index_face(surfTool, e1o, fe2, e2o)
				surface_tool_index_face(surfTool, e3o, e2o, fe3)
				surface_tool_index_face(surfTool, fe1, e1o, e3o)

			mesh.surface_remove(0)
			surfTool.generate_normals()
			surfTool.commit(mesh)

func set_mesh_node_mesh(mesh):
	meshNode.mesh = mesh
	facesNode.text = str(meshNode.mesh.get_faces().size()/3)

func _ready():
	#var surfTool = SurfaceTool.new()
	#surfTool.create_from(meshNode.mesh, 0)
	var surfTool = read_obj_mesh("res://bunny.obj")
	surfTool.generate_normals()
	set_mesh_node_mesh(surfTool.commit())
	controlMesh = meshNode.mesh.duplicate()

func _on_LoadButton_pressed():
	var fileDialog = $"Control/FileDialog"
	fileDialog.popup_centered_ratio()

func _on_CubeButton_pressed():
	set_mesh_node_mesh(SphereMesh.new())
	controlMesh = meshNode.mesh.duplicate()

func _on_SubdivisionLevel_value_changed(value):
	var smoothMesh = meshNode.mesh
	if value == 0 or value < subdivisionLevel:
		smoothMesh = controlMesh.duplicate()

	var delta = value
	if value > subdivisionLevel: delta = value - subdivisionLevel

	if delta > 0: loop_subdivide(smoothMesh, delta)

	set_mesh_node_mesh(smoothMesh)
	subdivisionLevel = value

func _on_RotationXState_value_changed(value):
	meshNode.rotation.x = value

func _on_RotationYState_value_changed(value):
	meshNode.rotation.y = value

func _on_RotationZState_value_changed(value):
	meshNode.rotation.z = value

func _on_ScaleState_value_changed(value):
	meshNode.scale.x = value
	meshNode.scale.y = value
	meshNode.scale.z = value

func _on_Wireframe_toggled(button_pressed):
	VisualServer.set_debug_generate_wireframes(button_pressed)
	get_viewport().debug_draw = Viewport.DEBUG_DRAW_WIREFRAME if button_pressed else Viewport.DEBUG_DRAW_DISABLED
	meshNode.mesh = meshNode.mesh.duplicate()
