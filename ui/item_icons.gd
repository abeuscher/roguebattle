class_name ItemIcons
## Item and status icons (playtest round 18): data/item_icons/<item id>.svg for every item
## and supply in items.json, data/status_icons/<status>.svg for every battle status;
## 64 × 64, full colour. Drawn by tools/item_icons.py.

const ITEMS := "res://data/item_icons/"
const STATUSES := "res://data/status_icons/"

static var _cache := {}  # path|px -> Texture2D, or null when there's no icon


## An item's or supply's icon at px × px; null if it has none.
static func item(id: String, px: int) -> Texture2D:
	return _load(ITEMS + id + ".svg", px)


## A battle status's icon at px × px; null if it has none.
static func status(id: String, px: int) -> Texture2D:
	return _load(STATUSES + id + ".svg", px)


## A TextureRect of an item's icon, for a row or a list; an empty one if it has none.
static func rect(id: String, px: int) -> TextureRect:
	var r := TextureRect.new()
	r.texture = item(id, px)
	r.custom_minimum_size = Vector2(px, px)
	r.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func _load(path: String, px: int) -> Texture2D:
	var key := "%s|%d" % [path, px]
	if not _cache.has(key):
		_cache[key] = null
		if FileAccess.file_exists(path):
			var img := Image.new()
			if img.load_svg_from_string(FileAccess.get_file_as_string(path), px / 64.0) == OK:
				img.generate_mipmaps()
				_cache[key] = ImageTexture.create_from_image(img)
	return _cache[key]
