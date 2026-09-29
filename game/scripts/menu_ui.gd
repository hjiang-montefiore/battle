class_name MenuUI
extends RefCounted
## The shell's look, in one place.
##
## The in-match HUD already has a palette -- dark slate panels with a lit
## edge -- and the menus are the same furniture seen from outside a match, so
## they borrow it rather than inventing a second theme. Nothing here draws;
## these are constructors the three shell scenes call.

const COL_PANEL := Color(0.055, 0.075, 0.095, 0.96)
const COL_PANEL_EDGE := Color(0.42, 0.62, 0.76, 0.85)
const COL_PLATE := Color(0.03, 0.05, 0.07, 0.86)
const COL_PLATE_EDGE := Color(0.34, 0.52, 0.64, 0.50)
const COL_TEXT := Color(0.90, 0.93, 0.95)
const COL_DIM := Color(0.58, 0.64, 0.70)
const COL_ACCENT := Color(1.00, 0.82, 0.35)
const COL_BAD := Color(1.00, 0.45, 0.38)
const COL_GOOD := Color(0.55, 0.88, 0.50)


static func panel_style(bg := COL_PANEL, edge := COL_PANEL_EDGE,
		border := 2, margin := 18) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(border)
	s.border_color = edge
	s.set_content_margin_all(margin)
	s.corner_radius_top_left = 3
	s.corner_radius_top_right = 3
	s.corner_radius_bottom_left = 3
	s.corner_radius_bottom_right = 3
	return s


static func panel(bg := COL_PANEL, edge := COL_PANEL_EDGE) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style(bg, edge))
	return p


static func heading(text: String, size := 22,
		col := COL_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	return l


## A single line. Deliberately NOT wrapped: a wrapping label inside an
## HBoxContainer with no width of its own shrinks to one character per line and
## grows until it pushes the rest of the screen off the bottom, which is
## exactly what the first build of the setup screen did.
static func body(text: String, size := 13, col := COL_DIM) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l


## A paragraph. Wraps, and therefore must be told how wide it is allowed to be.
static func para(text: String, size := 13, col := COL_DIM,
		min_width := 300.0) -> Label:
	var l := body(text, size, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(min_width, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## A plain push button in the shell's colours. Used for the small controls
## (Back, Start, Advanced); the big keyboard-driven lists use MenuList.
static func button(text: String, size := 14) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", COL_TEXT)
	b.add_theme_color_override("font_hover_color", COL_ACCENT)
	b.add_theme_stylebox_override("normal", panel_style(
		COL_PLATE, COL_PLATE_EDGE, 1, 8))
	b.add_theme_stylebox_override("hover", panel_style(
		Color(0.09, 0.13, 0.16, 0.95), COL_PANEL_EDGE, 1, 8))
	b.add_theme_stylebox_override("pressed", panel_style(
		Color(0.13, 0.19, 0.23, 0.98), COL_ACCENT, 1, 8))
	b.add_theme_stylebox_override("disabled", panel_style(
		Color(0.03, 0.04, 0.05, 0.75), Color(0.20, 0.24, 0.28, 0.6), 1, 8))
	b.add_theme_stylebox_override("focus", panel_style(
		Color(0, 0, 0, 0), COL_ACCENT, 1, 8))
	return b


static func option(size := 13) -> OptionButton:
	var o := OptionButton.new()
	o.add_theme_font_size_override("font_size", size)
	o.add_theme_color_override("font_color", COL_TEXT)
	o.add_theme_stylebox_override("normal", panel_style(
		COL_PLATE, COL_PLATE_EDGE, 1, 6))
	o.add_theme_stylebox_override("hover", panel_style(
		Color(0.09, 0.13, 0.16, 0.95), COL_PANEL_EDGE, 1, 6))
	o.add_theme_stylebox_override("pressed", panel_style(
		Color(0.13, 0.19, 0.23, 0.98), COL_ACCENT, 1, 6))
	o.add_theme_stylebox_override("focus", panel_style(
		Color(0, 0, 0, 0), COL_ACCENT, 1, 6))
	o.fit_to_longest_item = false
	o.clip_text = true
	return o


## A blurred, darkened copy of whatever is already on screen.
##
## The title runs a real match behind the menu, and a real match at full
## contrast fights the text in front of it. Blurring it is not decoration: it
## is what lets the backdrop be a LIVE battle instead of a still image, because
## a moving picture the eye cannot resolve does not compete for attention.
const BLUR_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float blur : hint_range(0.0, 6.0) = 2.6;
uniform float darken : hint_range(0.0, 1.0) = 0.46;
uniform vec3 tint = vec3(0.03, 0.05, 0.07);
void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, blur).rgb;
	COLOR = vec4(mix(c, tint, darken), 1.0);
}
"""


static func blur_rect(blur := 2.6, darken := 0.46) -> ColorRect:
	var sh := Shader.new()
	sh.code = BLUR_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("blur", blur)
	mat.set_shader_parameter("darken", darken)
	var r := ColorRect.new()
	r.material = mat
	r.color = Color(0, 0, 0, 1)
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## A flat scrim, for when there is no live scene worth blurring (headless,
## or a machine where the screen texture is unavailable).
static func scrim(alpha := 0.72) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0.02, 0.03, 0.04, alpha)
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## A left-hand wash, opaque under the text and gone by the middle of the
## screen. Menus laid over a picture always need one: the picture's brightness
## is whatever the picture happens to be doing that second, and text cannot
## have its contrast decided by where the camera drifted.
static func left_scrim(fade_at := 0.62, strength := 0.90) -> TextureRect:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([
		Color(0.015, 0.025, 0.035, strength),
		Color(0.015, 0.025, 0.035, strength * 0.72),
		Color(0.015, 0.025, 0.035, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(clampf(fade_at, 0.05, 1.0), 0)
	tex.width = 256
	tex.height = 8
	var r := TextureRect.new()
	r.texture = tex
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r
