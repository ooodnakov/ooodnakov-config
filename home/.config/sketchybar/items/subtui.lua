local colors = require("colors")

local subtui = sbar.add("item", "subtui", {
	position = "right",
	drawing = "off",
	update_freq = 2,
	script = "$HOME/.config/sketchybar/plugins/subtui_controller_hook.sh",
	icon = {
		string = "󰎆",
		font = "MesloLGSDZ Nerd Font Mono:Regular:13.0",
		padding_left = 4,
		padding_right = 2,
		color = colors.TEXT_SPOTIFY_GREEN,
	},
	label = {
		font = "MesloLGSDZ Nerd Font Mono:Regular:13.0",
		color = colors.TEXT_WHITE,
		max_chars = 20,
		padding_left = 2,
		padding_right = 4,
	},
	scroll_texts = true,
	click_script = "$HOME/.config/sketchybar/plugins/subtui_media_control.sh playpause",
	popup = {
		background = {
			color = colors.BACKGROUND,
			border_width = 2,
			border_color = colors.TEXT_GREY,
			corner_radius = 10,
		},
		horizontal = true,
		align = "center",
		y_offset = 5,
	},
})

local subtui_popup_hovered = false
local subtui_hide_token = 0

local function make_control(name, icon, command)
	return sbar.add("item", name, {
		position = "popup." .. subtui.name,
		width = 34,
		icon = {
			string = icon,
			font = "MesloLGSDZ Nerd Font Mono:Regular:14.0",
			color = colors.TEXT_WHITE,
			padding_left = 8,
			padding_right = 6,
		},
		label = {
			drawing = "off",
		},
		background = {
			drawing = "off",
		},
		click_script = command,
	})
end

local previous = make_control("subtui.prev", "󰒮", "$HOME/.config/sketchybar/plugins/subtui_media_control.sh previous")
local playpause = make_control("subtui.playpause", "󰐊", "$HOME/.config/sketchybar/plugins/subtui_media_control.sh playpause")
local next_track = make_control("subtui.next", "󰒭", "$HOME/.config/sketchybar/plugins/subtui_media_control.sh next")

local function show_subtui_popup()
	subtui_popup_hovered = true
	subtui_hide_token = subtui_hide_token + 1
	sbar.animate("tanh", 12, function()
		subtui:set({ popup = { drawing = true } })
	end)
end

local function schedule_subtui_popup_hide()
	subtui_popup_hovered = false
	subtui_hide_token = subtui_hide_token + 1
	local hide_token = subtui_hide_token

	sbar.exec("sleep 0.25", function()
		if subtui_popup_hovered or hide_token ~= subtui_hide_token then
			return
		end

		sbar.animate("tanh", 12, function()
			subtui:set({ popup = { drawing = false } })
		end)
	end)
end

local function hide_subtui_popup()
	schedule_subtui_popup_hide()
end

subtui:subscribe("mouse.entered", function()
	show_subtui_popup()
end)

subtui:subscribe("mouse.exited.global", function()
	hide_subtui_popup()
end)

subtui:subscribe("mouse.exited", function()
	hide_subtui_popup()
end)

previous:subscribe("mouse.entered", show_subtui_popup)
previous:subscribe("mouse.exited.global", hide_subtui_popup)
previous:subscribe("mouse.exited", hide_subtui_popup)

playpause:subscribe("mouse.entered", show_subtui_popup)
playpause:subscribe("mouse.exited.global", hide_subtui_popup)
playpause:subscribe("mouse.exited", hide_subtui_popup)

next_track:subscribe("mouse.entered", show_subtui_popup)
next_track:subscribe("mouse.exited.global", hide_subtui_popup)
next_track:subscribe("mouse.exited", hide_subtui_popup)
