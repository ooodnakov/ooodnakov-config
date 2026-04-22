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
})
