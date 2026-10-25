## Neon Arcade theme for the menus built in main.gd.
## Use the "TitleLabel" type variation for the big glowing screen titles.
extends RefCounted

const Palette := preload("res://scripts/vfx/palette.gd")


static func build() -> Theme:
	var t := Theme.new()

	t.set_color("font_color", "Label", Palette.UI_TEXT)
	t.set_type_variation("TitleLabel", "Label")
	t.set_color("font_color", "TitleLabel", Palette.hdr(Palette.P1, 1.6))
	t.set_color("font_shadow_color", "TitleLabel", Color(Palette.P2, 0.55))
	t.set_constant("shadow_offset_x", "TitleLabel", 6)
	t.set_constant("shadow_offset_y", "TitleLabel", 6)

	t.set_stylebox("normal", "Button", _box(Palette.UI_PANEL, Palette.UI_LINE, 2))
	t.set_stylebox("hover", "Button", _box(Palette.UI_PANEL, Palette.P1.darkened(0.3), 2))
	t.set_stylebox("pressed", "Button", _box(Color(Palette.ACCENT, 0.18), Palette.ACCENT, 3))
	t.set_stylebox("disabled", "Button", _box(Palette.UI_PANEL, Palette.UI_LINE, 2))
	var focus := _box(Color(0, 0, 0, 0), Palette.hdr(Palette.ACCENT, 1.5), 3)
	focus.draw_center = false
	t.set_stylebox("focus", "Button", focus)
	t.set_color("font_color", "Button", Palette.UI_TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_focus_color", "Button", Palette.ACCENT)
	t.set_color("font_pressed_color", "Button", Palette.ACCENT)
	t.set_color("font_hover_pressed_color", "Button", Palette.ACCENT)

	var track := StyleBoxFlat.new()
	track.bg_color = Palette.UI_LINE
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	track.set_corner_radius_all(4)
	t.set_stylebox("slider", "HSlider", track)
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = Palette.hdr(Palette.P1, 1.2)
	t.set_stylebox("grabber_area", "HSlider", fill)
	var fill_focus := track.duplicate() as StyleBoxFlat
	fill_focus.bg_color = Palette.hdr(Palette.ACCENT, 1.2)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill_focus)
	var slider_focus := _box(Color(0, 0, 0, 0), Palette.ACCENT, 2)
	slider_focus.draw_center = false
	slider_focus.expand_margin_left = 10
	slider_focus.expand_margin_right = 10
	t.set_stylebox("focus", "HSlider", slider_focus)
	return t


static func _box(bg: Color, border: Color, width: int) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = border
	b.set_border_width_all(width)
	b.set_corner_radius_all(4)
	b.content_margin_left = 24
	b.content_margin_right = 24
	b.content_margin_top = 10
	b.content_margin_bottom = 10
	return b
