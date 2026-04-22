local colors = require("colors")

local cpu = sbar.add("item", "cpu", {
	position = "e",
	update_freq = 10,
	icon = { 
		string = "", 
		font = "MesloLGSDZ Nerd Font Mono:Bold:20.0", 
		padding_left = 8, 
		color = colors.TEXT_RED 
	},
	label = {
		font = "MesloLGSDZ Nerd Font Mono:Bold:13.0",
		padding_right = 8,
		color = colors.TEXT_RED,
	},
	background = {
		corner_radius = 10,
		color = colors.BACKGROUND_DARK,
		height = 30,
	},
	drawing = "off",
	click_script = "open -a 'Activity Monitor'",
})

cpu:subscribe({ "routine", "system_woke" }, function(env)
	sbar.exec("top -l 1 | grep 'CPU usage' | awk '{print $5}'", function(result)
		result = result:match("^%d*").. "%"
        cpu:set({
            drawing = "on",
            label = {
                string = result,
            },
        })
	end)
end)
