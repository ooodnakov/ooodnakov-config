local colors = require("colors")

local audio = sbar.add("graph", "audio", 128, {
	position = "right",
	graph = {
		color = colors.TEXT_ORANGE,
		fill_color = colors.BACKGROUND_DARK_ORANGE,
		line_width = 1.5,
	},
	background = {
		color = colors.BACKGROUND_DARK,
		border_width = 1,
		border_color = colors.BACKGROUND_DARKER,
		corner_radius = 10,
		height = 30,
	},
	padding_left = 4,
	padding_right = 4,
})

sbar.exec("bash " .. os.getenv("HOME") .. "/.config/sketchybar/plugins/cava_visualizer.sh audio >/dev/null 2>&1 &")

audio:subscribe("mouse.clicked", function()
	sbar.exec("pkill -USR1 cava")
end)
