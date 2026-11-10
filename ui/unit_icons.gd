class_name UnitIcons
## Unit icons: data/unit_icons/<class>.svg, drawn by tools/unit_icons.py from the sheet's
## Icon base / hand / head / crest columns (DECISIONS session 041).
## Each icon uses two colors, ink and paper. The defaults are dark ink on parchment; for a
## colored card pass the card's color as paper and parchment as ink (UnitIcons.on_card).

const DIR := "res://data/unit_icons/"
const INK := "#1d1b1a"     # must match INK in tools/unit_icons.py
const PAPER := "#f4efe4"   # must match PAPER in tools/unit_icons.py
# The tile's frame(s), as tools/unit_icons.py writes them: the outer one, and the inner one on Large units.
const FRAME := "<rect x=\"(2|6\\.5)\" y=\"(2|6\\.5)\"[^>]*/>"

static var _cache := {}  # "class|px|paper|ink|frame" -> Texture2D, or null when there's no icon


## The icon at px × px. Rasterized once per size and colors. Without the frame, the figure
## sits on paper alone (map tokens draw their own ring). Mipmapped so a zoomed-out map stays smooth.
static func texture(unit_class: String, px: int, paper := Color(PAPER), ink := Color(INK), frame := true) -> Texture2D:
	var key := "%s|%d|%s|%s|%s" % [unit_class, px, paper.to_html(false), ink.to_html(false), frame]
	if not _cache.has(key):
		_cache[key] = null
		var path := DIR + file_name(unit_class) + ".svg"
		if FileAccess.file_exists(path):
			var svg := FileAccess.get_file_as_string(path)
			if not frame:
				svg = RegEx.create_from_string(FRAME).sub(svg, "", true)
			# Through a placeholder so swapping ink and paper doesn't undo itself.
			svg = svg.replace(INK, "#INK__").replace(PAPER, "#" + paper.to_html(false)).replace("#INK__", "#" + ink.to_html(false))
			var img := Image.new()
			if img.load_svg_from_string(svg, px / 64.0) == OK:
				img.generate_mipmaps()
				_cache[key] = ImageTexture.create_from_image(img)
	return _cache[key]


## Light-on-dark version for a unit card of the given color.
static func on_card(unit_class: String, px: int, card: Color) -> Texture2D:
	return texture(unit_class, px, card, Color(PAPER))


## For a map token: parchment figure on the token's own color, no frame.
static func on_token(unit_class: String, px: int, disc: Color) -> Texture2D:
	return texture(unit_class, px, disc, Color(PAPER), false)


## "Standard-Bearer" -> "standard_bearer", as the generator names the files.
static func file_name(unit_class: String) -> String:
	var re := RegEx.create_from_string("[^a-z0-9]+")
	return re.sub(unit_class.to_lower(), "_", true).lstrip("_").rstrip("_")
