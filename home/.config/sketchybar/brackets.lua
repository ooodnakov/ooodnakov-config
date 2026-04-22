local colors = require("colors")

-- Right items bracket
sbar.add("bracket", "rightItems", { "cpu", "memory", "volume", "battery", "wifi" }, {
	background = {
		color = colors.BACKGROUND,
		border_color = colors.BACKGROUND_DARK,
		border_width = 1,
		corner_radius = 12,
		height = 30,
	},
})
