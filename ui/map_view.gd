class_name MapView
extends Node2D
## Draws a map as textured hexes, in chunks so off-screen parts are culled.

const HEX_SIZE := 32.0  # world units, center to corner
const TEXTURE_HEX_SIZE := 48.0  # texels, so tiles stay sharp when zoomed in
const CHUNK := 64  # hexes per chunk side

var _tiles: Array[Texture2D] = []
var _bridge: Texture2D
var _quad: ArrayMesh
var _impassable: Array[bool] = []


func show_map(map: MapData, data: GameData) -> void:
	for child in get_children():
		child.queue_free()
	if _tiles.is_empty():
		_tiles = TerrainTiles.build(data, TEXTURE_HEX_SIZE)
		_bridge = TerrainTiles.bridge(Color(data.mapgen["bridge_color"]), TEXTURE_HEX_SIZE)
		for t in data.terrains:
			_impassable.append(t.get("impassable", false))
		_quad = _make_quad(Vector2(TerrainTiles.tile_size(TEXTURE_HEX_SIZE)) * HEX_SIZE / TEXTURE_HEX_SIZE)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(_underlay(map, data))
	for cy in range(0, map.height, CHUNK):
		for cx in range(0, map.width, CHUNK):
			_build_chunk(map, cx, cy)


## World-space size of the whole map.
static func world_size(map: MapData) -> Vector2:
	return Vector2(HEX_SIZE * Hex.SQRT3 * (map.width + 0.5), HEX_SIZE * (1.5 * map.height + 0.5))


## A flat-color copy under the tiles, so no gaps show between hexes when zoomed far out.
func _underlay(map: MapData, data: GameData) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(MinimapImage.build(map, data))
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.centered = false
	sprite.scale = Vector2(HEX_SIZE * Hex.SQRT3 / 2.0, HEX_SIZE * 0.75)
	sprite.position = -sprite.scale
	return sprite


func _build_chunk(map: MapData, cx: int, cy: int) -> void:
	var by_terrain := {}
	var bridges := PackedVector2Array()
	for row in range(cy, mini(cy + CHUNK, map.height)):
		for col in range(cx, mini(cx + CHUNK, map.width)):
			var i := row * map.width + col
			var t := map.terrain[i]
			var p := Hex.to_pixel(Hex.from_offset(Vector2i(col, row)), HEX_SIZE)
			if not by_terrain.has(t):
				by_terrain[t] = PackedVector2Array()
			by_terrain[t].append(p)
			if map.road[i] and _impassable[t]:
				bridges.append(p)
	for t in by_terrain:
		_add_instances(by_terrain[t], _tiles[t])
	if not bridges.is_empty():
		_add_instances(bridges, _bridge)


func _add_instances(points: PackedVector2Array, texture: Texture2D) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.mesh = _quad
	mm.instance_count = points.size()
	for i in points.size():
		mm.set_instance_transform_2d(i, Transform2D(0.0, points[i]))
	var inst := MultiMeshInstance2D.new()
	inst.multimesh = mm
	inst.texture = texture
	add_child(inst)


static func _make_quad(size: Vector2) -> ArrayMesh:
	var h := size / 2.0
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([-h, Vector2(h.x, -h.y), h, Vector2(-h.x, h.y)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
