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
		max_chars = 16,
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
		align = "center",
		y_offset = 5,
	},
})

local img = sbar.add("item", {
	position = "popup." .. ncspot.name,
	y_offset = 0,
	height = 180,
	background = {
		drawing = "on",
		image = {
			drawing = "on",
			corner_radius = 10,
			scale = 0.55,
		},
		corner_radius = 10,
	},
})

local function show_ncspot_popup()
	sbar.animate("tanh", 12, function()
		ncspot:set({ popup = { drawing = true } })
	end)
end

local function hide_ncspot_popup()
	sbar.animate("tanh", 12, function()
		ncspot:set({ popup = { drawing = false } })
	end)
end

ncspot:subscribe("mouse.entered", function()
	show_ncspot_popup()
	img:set({ background = { image = { string = "/tmp/ncspot-controller-cover.jpg" } } })
end)

ncspot:subscribe("mouse.exited.global", function()
	hide_ncspot_popup()
	img:set({ background = { image = { string = "" } } })
end)

ncspot:subscribe("mouse.exited", function()
	hide_ncspot_popup()
	img:set({ background = { image = { string = "" } } })
end)
