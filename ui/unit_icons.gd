class_name UnitIcons
## Unit icons: data/unit_icons/svg/<class>.svg, full-colour figures (folk) and heads
## (monsters) on a transparent 256 × 256 square, feet on a common baseline at 95% of the
## height. Drawn by tools/unit_icons_humans.py and tools/unit_icons_creatures.py from the
## sheet's Icon columns (user's set, 2026-11-14).

const DIR := "res://data/unit_icons/svg/"
const ART := 256.0  # the icons' own size
const FEET := 0.95  # the baseline, down the icon

static var _cache := {}  # "class|px|trim" -> Texture2D, or null when there's no icon
static var _feet := {}  # class -> where its feet stand across the icon, 0..1


## The icon at px × px, rasterized once per size and mipmapped so a zoomed-out map stays
## smooth. `trim`: the empty margin cut away and the figure fitted to the square, for small
## places (a 28 px drawer row, a list) where the full square would leave it tiny.
static func texture(unit_class: String, px: int, trim := false) -> Texture2D:
	var key := "%s|%d|%s" % [unit_class, px, trim]
	if not _cache.has(key):
		_cache[key] = null
		var path := DIR + file_name(unit_class) + ".svg"
		if FileAccess.file_exists(path):
			var img := Image.new()
			var draw_px := px * 2 if trim else px  # trimmed: drawn larger, then cut and shrunk
			if img.load_svg_from_string(FileAccess.get_file_as_string(path), draw_px / ART) == OK:
				if trim:
					img = _trimmed(img, px)
				img.generate_mipmaps()
				_cache[key] = ImageTexture.create_from_image(img)
	return _cache[key]


## The figure without its empty margin, centred in a square px wide.
static func _trimmed(img: Image, px: int) -> Image:
	var used := img.get_used_rect()
	if used.size.x <= 0:
		return img
	var side := maxi(used.size.x, used.size.y)
	var square := Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
	img.convert(Image.FORMAT_RGBA8)
	square.blit_rect(img, used, Vector2i(Vector2(Vector2i(side, side) - used.size) / 2.0))
	square.resize(px, px, Image.INTERPOLATE_LANCZOS)
	return square


## How far across the icon the figure's feet stand (0.5 is the middle), from the solid
## pixels just above its baseline: the art doesn't centre every figure on its feet.
static func feet_x(unit_class: String) -> float:
	if not _feet.has(unit_class):
		_feet[unit_class] = 0.5
		var tex := texture(unit_class, 128)
		if tex:
			var img := tex.get_image()
			var sum := 0.0
			var n := 0
			for y in range(114, 122):
				for x in 128:
					if img.get_pixel(x, y).a > 0.5:
						sum += x
						n += 1
			if n > 0:
				_feet[unit_class] = sum / n / 128.0
	return _feet[unit_class]


## "Standard-Bearer" -> "standard_bearer", as the generators name the files.
static func file_name(unit_class: String) -> String:
	var re := RegEx.create_from_string("[^a-z0-9]+")
	return re.sub(unit_class.to_lower(), "_", true).lstrip("_").rstrip("_")
