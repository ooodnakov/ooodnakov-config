local colors = require("colors")

local ncspot = sbar.add("item", "ncspot", {
	position = "right",
	drawing = "off",
	icon = {
		string = "",
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
	click_script = "ncspot-controller playpause",
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

local ncspot_popup_hovered = false
local ncspot_hide_token = 0

local function make_control(name, icon, command)
	return sbar.add("item", name, {
		position = "popup." .. ncspot.name,
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

local previous = make_control("ncspot.prev", "󰒮", "ncspot-controller previous")
local playpause = make_control("ncspot.playpause", "󰐊", "ncspot-controller playpause")
local next_track = make_control("ncspot.next", "󰒭", "ncspot-controller next")

local function show_ncspot_popup()
	ncspot_popup_hovered = true
	ncspot_hide_token = ncspot_hide_token + 1
	sbar.animate("tanh", 12, function()
		ncspot:set({ popup = { drawing = true } })
	end)
end

local function schedule_ncspot_popup_hide()
	ncspot_popup_hovered = false
	ncspot_hide_token = ncspot_hide_token + 1
	local hide_token = ncspot_hide_token

	sbar.exec("sleep 0.25", function()
		if ncspot_popup_hovered or hide_token ~= ncspot_hide_token then
			return
		end

		sbar.animate("tanh", 12, function()
			ncspot:set({ popup = { drawing = false } })
		end)
	end)
end

local function hide_ncspot_popup()
	schedule_ncspot_popup_hide()
end

ncspot:subscribe("mouse.entered", function()
	show_ncspot_popup()
end)

ncspot:subscribe("mouse.exited.global", function()
	hide_ncspot_popup()
end)

ncspot:subscribe("mouse.exited", function()
	hide_ncspot_popup()
end)

previous:subscribe("mouse.entered", show_ncspot_popup)
previous:subscribe("mouse.exited.global", hide_ncspot_popup)
previous:subscribe("mouse.exited", hide_ncspot_popup)

playpause:subscribe("mouse.entered", show_ncspot_popup)
playpause:subscribe("mouse.exited.global", hide_ncspot_popup)
playpause:subscribe("mouse.exited", hide_ncspot_popup)

next_track:subscribe("mouse.entered", show_ncspot_popup)
next_track:subscribe("mouse.exited.global", hide_ncspot_popup)
next_track:subscribe("mouse.exited", hide_ncspot_popup)
