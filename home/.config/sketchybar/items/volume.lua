local colors = require("colors")

local VOLUME_POPUP_HIDE_DELAY = 0.25

local volume = sbar.add("item", "volume", {
	position = "right",
	popup = {
		background = {
			color = colors.BACKGROUND,
			border_width = 2,
			border_color = colors.TEXT_GREY,
			corner_radius = 10,
		},
		y_offset = 5,
	},
})

local volume_popup_hovered = false
local volume_hide_token = 0

local volume_slider = sbar.add("slider", "volume.slider", 90, {
	position = "popup." .. volume.name,
	icon = {
		drawing = "off",
	},
	label = {
		drawing = "off",
	},
	slider = {
		percentage = 0,
		highlight_color = colors.TEXT_WHITE,
		background = {
			height = 6,
			corner_radius = 3,
			color = colors.BACKGROUND_DARKER,
		},
		knob = {
			string = "󰀁",
			font = "MesloLGSDZ Nerd Font Mono:Regular:12.0",
			color = colors.TEXT_WHITE,
		},
	},
	background = {
		drawing = "off",
	},
})

local function refresh_volume(volume_info)
	local icon = "󰖀"
	if volume_info == 0 then
		icon = "󰖁"
	elseif volume_info > 50 then
		icon = "󰕾"
	end

	volume:set({
		icon = {
			string = icon,
			font = "MesloLGSDZ Nerd Font Mono:Regular:13.0",
		},
		label = {
			string = string.format("%d%%", volume_info),
			font = "MesloLGSDZ Nerd Font Mono:Regular:13.0",
		},
	})

	volume_slider:set({
		slider = {
			percentage = volume_info,
		},
	})
end

local function show_volume_popup()
	volume_popup_hovered = true
	volume_hide_token = volume_hide_token + 1
	sbar.animate("tanh", 12, function()
		volume:set({ popup = { drawing = true } })
	end)
end

local function schedule_volume_popup_hide()
	volume_popup_hovered = false
	volume_hide_token = volume_hide_token + 1
	local hide_token = volume_hide_token

	sbar.exec("sleep " .. VOLUME_POPUP_HIDE_DELAY, function()
		if volume_popup_hovered or hide_token ~= volume_hide_token then
			return
		end

		sbar.animate("tanh", 12, function()
			volume:set({ popup = { drawing = false } })
		end)
	end)
end

volume:subscribe("volume_change", function(env)
	local volume_info = tonumber(env.INFO) or 0
	refresh_volume(volume_info)
end)

volume_slider:subscribe("mouse.clicked", function(env)
	local percentage = math.max(0, math.min(100, math.floor((tonumber(env.PERCENTAGE) or 0) + 0.5)))

	sbar.exec("osascript -e 'set volume output volume " .. percentage .. "'", function()
		refresh_volume(percentage)
	end)
	schedule_volume_popup_hide()
end)

volume:subscribe("mouse.entered", function()
	show_volume_popup()
end)

volume_slider:subscribe("mouse.entered", function()
	show_volume_popup()
end)

volume:subscribe("mouse.exited.global", function()
	schedule_volume_popup_hide()
end)

volume_slider:subscribe("mouse.exited.global", function()
	schedule_volume_popup_hide()
end)

sbar.trigger("volume_change")
