local gpu_adapters = require("utils.gpu-adapter")
local backdrops = require("utils.backdrops")
local colors = require("colors.custom")
local platform = require("utils.platform")

local initial_background = nil
const_window_background_opacity = 0.7
if platform.is_win then
	initial_background = backdrops:initial_options(false)
	const_window_background_opacity = 0
end

return {
	max_fps = 120,
	front_end = "WebGpu", ---@type 'WebGpu' | 'OpenGL' | 'Software'
	webgpu_power_preference = "HighPerformance",
	webgpu_preferred_adapter = gpu_adapters:pick_best(),
	-- webgpu_preferred_adapter = gpu_adapters:pick_manual('Dx12', 'IntegratedGpu'),
	-- webgpu_preferred_adapter = gpu_adapters:pick_manual('Gl', 'Other'),
	underline_thickness = "1.5pt",

	-- cursor
	animation_fps = 120,
	cursor_blink_ease_in = "EaseOut",
	cursor_blink_ease_out = "EaseOut",
	default_cursor_style = "BlinkingBlock",
	cursor_blink_rate = 650,

	-- color scheme
	colors = colors,

	background = initial_background,

	-- scrollbar
	enable_scroll_bar = true,

	-- tab bar
	enable_tab_bar = true,
	hide_tab_bar_if_only_one_tab = false,
	use_fancy_tab_bar = false,
	tab_max_width = 25,
	show_tab_index_in_tab_bar = false,
	switch_to_last_active_tab_when_closing_tab = true,

	-- command palette
	command_palette_fg_color = "#b4befe",
	command_palette_bg_color = "#11111b",
	command_palette_font_size = 12,
	command_palette_rows = 25,

	-- window
	window_padding = {
		left = '0.5cell',
		right = '0.5cell',
		top = '0.5cell',
		bottom = '1cell',
	},
	adjust_window_size_when_changing_font_size = false,
	window_close_confirmation = "NeverPrompt",
	window_frame = {
		active_titlebar_bg = "#090909",
		inactive_titlebar_bg = "#090909",
		border_left_width = '0cell',
		border_right_width = '0cell',
		border_bottom_height = '0cell',
		border_top_height = '0cell',
	},
	window_decorations = "NONE",
	window_background_opacity = const_window_background_opacity,
	macos_window_background_blur = 30,
	kde_window_background_blur = true,
	win32_system_backdrop = 'Acrylic',
	inactive_pane_hsb = {
		saturation = 1,
		brightness = 1,
	},

	visual_bell = {
		fade_in_function = "EaseIn",
		fade_in_duration_ms = 250,
		fade_out_function = "EaseOut",
		fade_out_duration_ms = 250,
		target = "CursorColor",
	},
}
