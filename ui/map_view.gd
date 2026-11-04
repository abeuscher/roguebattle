class_name MapView
extends Node2D
## The battlemap's drawing (SPEC §5.1): textured hexes in chunks (off-screen
## parts are culled), a short drop under the south edge of raised land, roads,
## then upright objects (trees, peaks, buildings) drawn top to bottom so lower
## ones overlap higher ones. Debug overlays and the hex grid sit under the objects.

const HEX_SIZE := 32.0  # world units, center to corner
const TEXTURE_HEX_SIZE := 48.0  # texels, so tiles stay sharp when zoomed in
const CHUNK := 64  # hexes per chunk side
const STRIP_ROWS := 2  # objects are batched in full-width strips this many rows tall
const ICON_SCALE := 2.0  # icons stand about two hexes tall
const ICON_MIN_SCREEN := 0.5  # icons never shrink below this fraction of their size at zoom 1
const RELIEF_EARTH := Color("#5a4632")
const OBJECT_SHADER := """
shader_type canvas_item;
uniform float cells = 4.0;
void vertex() {
	UV.x = (UV.x + INSTANCE_CUSTOM.r) / cells;  // pick this instance's cell in the atlas
}
"""

var show_secrets := false:  # all hidden sites and lairs (debug viewing); otherwise only revealed ones show
	set(value):
		show_secrets = value
		for h in _secret_at:
			_secret_at[h].visible = value or _revealed.has(h)
var overlay := "":
	set(value):
		overlay = value
		_build_overlay()
var show_grid := false:
	set(value):
		show_grid = value
		if value and _grid_layer.get_child_count() == 0 and _map:
			_build_grid()
		_grid_layer.visible = value

var paths := PathView.new()  # routes, drawn over everything else
var _map: MapData
var _data: GameData
var _tiles: Array[Texture2D] = []
var _bridge: Texture2D
var _road: Array[Texture2D] = []
var _relief: Array[Texture2D] = []  # lower-right short, lower-left short, lower-right deep, lower-left deep
var _objects: Texture2D
var _object_material: ShaderMaterial
var _hex_fill: Texture2D
var _hex_ring: Texture2D
var _icons := {}
var _quad: ArrayMesh
var _relief_quad: ArrayMesh
var _object_quad: ArrayMesh
var _impassable := PackedByteArray()
var _water := PackedByteArray()  # water or air: what raised land drops toward
var _terrain_layer := Node2D.new()
var _relief_layer := Node2D.new()
var _road_layer := Node2D.new()
var _overlay_layer := Node2D.new()
var _grid_layer := Node2D.new()
var _object_layer := Node2D.new()
var _strips: Array[Node2D] = []
var _icon_sprites: Array[Sprite2D] = []
var _secret_at := {}  # hex -> hidden site or lair icon
var _revealed := {}  # hexes whose secret icon a squad has seen


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_object_layer.y_sort_enabled = true
	_grid_layer.visible = false
	for layer in [_terrain_layer, _relief_layer, _road_layer, _overlay_layer, _grid_layer, _object_layer, paths]:
		add_child(layer)


func show_map(map: MapData, data: GameData) -> void:
	_map = map
	_data = data
	for layer in [_terrain_layer, _relief_layer, _road_layer, _overlay_layer, _grid_layer, _object_layer]:
		for child in layer.get_children():
			child.queue_free()
	_strips.clear()
	_icon_sprites.clear()
	_secret_at.clear()
	_revealed.clear()
	if _tiles.is_empty():
		_load_art(data)
	_terrain_layer.add_child(_underlay(map, data))
	for cy in range(0, map.height, CHUNK):
		for cx in range(0, map.width, CHUNK):
			_build_chunk(map, cx, cy)
	_build_objects(map)
	_build_overlay()
	if show_grid:
		_build_grid()


## Adds a map object (such as a squad token) to the layer sorted by screen Y.
## Cleared by show_map().
func add_object(node: Node2D) -> void:
	_object_layer.add_child(node)


## World position of a hex's center.
static func hex_center(map: MapData, i: int) -> Vector2:
	return Hex.to_pixel(map.hex_at(i), HEX_SIZE)


## Keeps icons readable when zoomed far out.
func set_zoom(zoom: float) -> void:
	var s := HEX_SIZE / TEXTURE_HEX_SIZE * ICON_SCALE * maxf(1.0, ICON_MIN_SCREEN / zoom)
	for icon in _icon_sprites:
		icon.scale = Vector2(s, s)
	paths.zoom = zoom
	paths.queue_redraw()


## World-space size of the whole map.
static func world_size(map: MapData) -> Vector2:
	return Vector2(HEX_SIZE * Hex.SQRT3 * (map.width + 0.5), HEX_SIZE * (1.5 * map.height + 0.5))


func _load_art(data: GameData) -> void:
	var s := TEXTURE_HEX_SIZE
	_tiles = TerrainTiles.build(data, s)
	_bridge = TerrainTiles.bridge(Color(data.mapgen["bridge_color"]), s)
	_road = TerrainTiles.road_pieces(Color(data.mapgen["road_color"]), s)
	for depth in [TerrainTiles.RELIEF_SHORT, TerrainTiles.RELIEF_DEEP]:
		for side in 2:
			_relief.append(TerrainTiles.relief(s, side, depth))
	_objects = TerrainTiles.objects(s)
	var shader := Shader.new()
	shader.code = OBJECT_SHADER
	_object_material = ShaderMaterial.new()
	_object_material.shader = shader
	_object_material.set_shader_parameter("cells", float(TerrainTiles.OBJECT_CELLS))
	_hex_fill = TerrainTiles.hex_shape(s, false)
	_hex_ring = TerrainTiles.hex_shape(s, true)
	_icons = BuildingIcons.build(s)
	_impassable = MapGen.terrain_flags(data, "impassable")
	_water = MapGen.terrain_flags(data, "water")
	_water[data.terrain_ids["air_gap"]] = 1
	var world := HEX_SIZE / s
	_quad = _make_quad(Vector2(TerrainTiles.tile_size(s)) * world)
	_relief_quad = _make_quad(Vector2(TerrainTiles.relief_size(s)) * world)
	_object_quad = _make_quad(Vector2(TerrainTiles.object_cell(s)) * world)


## A flat-color copy under the tiles, so no gaps show between hexes when zoomed far out.
func _underlay(map: MapData, data: GameData) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(MinimapImage.build(map, data))
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.centered = false
	sprite.scale = Vector2(HEX_SIZE * Hex.SQRT3 / 2.0, HEX_SIZE * 0.75)
	sprite.position = -sprite.scale
	return sprite


func _center(col: int, row: int) -> Vector2:
	return Hex.to_pixel(Hex.from_offset(Vector2i(col, row)), HEX_SIZE)


func _build_chunk(map: MapData, cx: int, cy: int) -> void:
	var by_terrain := {}
	var bridges := PackedVector2Array()
	var roads: Array[PackedVector2Array] = []
	for k in 7:
		roads.append(PackedVector2Array())
	var relief_points: Array[PackedVector2Array] = []
	var relief_colors: Array[PackedColorArray] = []
	for k in 4:
		relief_points.append(PackedVector2Array())
		relief_colors.append(PackedColorArray())
	var air: int = _data.terrain_ids["air_gap"]
	var cliff_id: int = _data.terrain_ids["cliff"]
	for row in range(cy, mini(cy + CHUNK, map.height)):
		for col in range(cx, mini(cx + CHUNK, map.width)):
			var i := row * map.width + col
			var t := map.terrain[i]
			var p := _center(col, row)
			if not by_terrain.has(t):
				by_terrain[t] = PackedVector2Array()
			by_terrain[t].append(p)
			# Raised land: a face under each lower edge that meets water, air, or (for cliffs) lower ground.
			if not _water[t]:
				var cliff := t == cliff_id
				for side in 2:
					var n := map.neighbors[i * 6 + (5 if side == 0 else 4)]
					if n < 0:
						continue
					var nt := map.terrain[n]
					if _water[nt] or (cliff and nt != t):
						var deep := 2 if nt == air else 0
						relief_points[side + deep].append(p)
						relief_colors[side + deep].append(Color(_data.terrains[t]["color"]).lerp(RELIEF_EARTH, 0.55).darkened(0.1))
			if not map.road[i]:
				continue
			if _impassable[t]:
				bridges.append(p)
			roads[6].append(p)
			for k in 6:
				if map.road[i] & (1 << k):
					roads[k].append(p)
	for t in by_terrain:
		_add_instances(_terrain_layer, _quad, by_terrain[t], _tiles[t])
	if not bridges.is_empty():
		_add_instances(_terrain_layer, _quad, bridges, _bridge)
	for k in 4:
		if not relief_points[k].is_empty():
			_add_instances(_relief_layer, _relief_quad, relief_points[k], _relief[k], relief_colors[k])
	for k in 7:
		if not roads[k].is_empty():
			_add_instances(_road_layer, _quad, roads[k], _road[k])


## Trees, peaks and building icons, sorted by screen Y so lower ones draw in front.
## Trees and peaks share an atlas and are batched per strip of rows; buildings are sprites.
func _build_objects(map: MapData) -> void:
	var occupied := {}
	var icons: Array = []
	for b in map.buildings:
		occupied[b["hex"]] = true
		icons.append([b["hex"], b["type"]])
	for l in map.lairs:
		occupied[l["hex"]] = true
		icons.append([l["hex"], "lair"])
	var forest: int = _data.terrain_ids["forest"]
	var mountain: int = _data.terrain_ids["mountain"]
	for top in range(0, map.height, STRIP_ROWS):
		var bottom := mini(top + STRIP_ROWS, map.height) - 1
		# The strip sorts just above its bottom row, so a building on the bottom row draws over
		# the strip and one on a higher row draws under the trees in front of it.
		var origin := Vector2(0, _center(0, bottom).y - 1.0)
		var points := PackedVector2Array()
		var cells := PackedFloat32Array()
		for row in range(top, bottom + 1):
			for col in map.width:
				var i := row * map.width + col
				var t := map.terrain[i]
				if (t != forest and t != mountain) or occupied.has(i):
					continue
				var h := (i * 2654435761) & 0xffff  # stable per-hex variety
				var jitter := Vector2(float(h & 0xff) / 255.0 - 0.5, float(h >> 8) / 255.0 - 0.5) * HEX_SIZE * 0.25
				points.append(_center(col, row) + jitter - origin)
				cells.append(float((0 if t == forest else 2) + (h & 1)))
		if points.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.use_custom_data = true
		mm.mesh = _object_quad
		mm.instance_count = points.size()
		for j in points.size():
			mm.set_instance_transform_2d(j, Transform2D(0.0, points[j]))
			mm.set_instance_custom_data(j, Color(cells[j], 0, 0, 0))
		var strip := MultiMeshInstance2D.new()
		strip.multimesh = mm
		strip.texture = _objects
		strip.material = _object_material
		strip.position = origin
		strip.visible = overlay == ""
		_object_layer.add_child(strip)
		_strips.append(strip)
	var ground := 12.0 * TEXTURE_HEX_SIZE / 32.0  # icons are drawn standing 12 units below their center
	for entry in icons:
		var icon := Sprite2D.new()
		icon.texture = _icons[entry[1]]
		icon.offset = Vector2(0, -ground)
		icon.position = Hex.to_pixel(map.hex_at(entry[0]), HEX_SIZE)
		if entry[1] in ["hidden_site", "lair"]:
			icon.visible = show_secrets
			_secret_at[entry[0]] = icon
		_object_layer.add_child(icon)
		_icon_sprites.append(icon)


## Moves, shows or hides a building's icon (nomads) and sets its marker: the owner's
## flag (transparent for none) and liberation progress. `i` indexes map.buildings.
func update_building(i: int, hex: int, shown: bool, flag: Color, progress: float) -> void:
	var icon := _icon_sprites[i]
	icon.position = Hex.to_pixel(_map.hex_at(hex), HEX_SIZE)
	if icon not in _secret_at.values():
		icon.visible = shown
	var marker: BuildingMarker = icon.get_node_or_null("Marker")
	if marker == null and (flag.a > 0.0 or progress > 0.0):
		var unit := TEXTURE_HEX_SIZE / 32.0
		marker = BuildingMarker.new()
		marker.name = "Marker"
		marker.position = icon.offset  # the icon image's center
		marker.unit = unit
		marker.top = BuildingIcons.TOPS.get(_map.buildings[i]["type"], Vector2.ZERO) * unit
		icon.add_child(marker)
	if marker:
		marker.flag = flag
		marker.progress = progress


## Shows a hidden site or lair icon once a squad has seen it.
func reveal(hex: int) -> void:
	_revealed[hex] = true
	if _secret_at.has(hex):
		_secret_at[hex].visible = true


func _build_overlay() -> void:
	for child in _overlay_layer.get_children():
		child.queue_free()
	for strip in _strips:
		strip.visible = overlay == ""  # trees and peaks would hide the overlay
	if overlay == "" or _map == null:
		return
	var colors := MapOverlay.colors(overlay, _map, _data)
	var per_chunk := func(points: PackedVector2Array, indices: PackedInt32Array) -> void:
		var shown := PackedVector2Array()
		var tints := PackedColorArray()
		for j in points.size():
			var c := colors[indices[j]]
			if c.a > 0.0:
				shown.append(points[j])
				tints.append(c)
		if not shown.is_empty():
			_add_instances(_overlay_layer, _quad, shown, _hex_fill, tints)
	_each_chunk(per_chunk)


func _build_grid() -> void:
	var line := Color(0, 0, 0, 0.3)
	var per_chunk := func(points: PackedVector2Array, _indices: PackedInt32Array) -> void:
		var tints := PackedColorArray()
		tints.resize(points.size())
		tints.fill(line)
		_add_instances(_grid_layer, _quad, points, _hex_ring, tints)
	_each_chunk(per_chunk)


## Calls f(centers, hex indices) once per chunk.
func _each_chunk(f: Callable) -> void:
	for cy in range(0, _map.height, CHUNK):
		for cx in range(0, _map.width, CHUNK):
			var points := PackedVector2Array()
			var indices := PackedInt32Array()
			for row in range(cy, mini(cy + CHUNK, _map.height)):
				for col in range(cx, mini(cx + CHUNK, _map.width)):
					points.append(_center(col, row))
					indices.append(row * _map.width + col)
			f.call(points, indices)


func _add_instances(layer: Node2D, quad: ArrayMesh, points: PackedVector2Array, texture: Texture2D,
		tints := PackedColorArray()) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = not tints.is_empty()
	mm.mesh = quad
	mm.instance_count = points.size()
	for i in points.size():
		mm.set_instance_transform_2d(i, Transform2D(0.0, points[i]))
		if not tints.is_empty():
			mm.set_instance_color(i, tints[i])
	var inst := MultiMeshInstance2D.new()
	inst.multimesh = mm
	inst.texture = texture
	layer.add_child(inst)


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
