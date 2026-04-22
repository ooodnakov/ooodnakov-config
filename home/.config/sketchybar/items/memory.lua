local colors = require("colors")

local memory = sbar.add("item", "memory", {
	position = "e",
	update_freq = 10,
	icon = { 
		string = "", 
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

memory:subscribe({ "routine", "system_woke" }, function(env)
	sbar.exec("top -l 1 | grep -E 'PhysMem|memory' | awk '{print $2}'", function(result)
		result = result:match("^%s*(.*%S)%s*$")
		int_result = tonumber(result:match("^%d*"))
		if int_result <= 10 then
			memory:set({
				drawing = "off",
			})
		else
			memory:set({
				drawing = "on",
				label = {
					string = result,
				},
			})
		end
	end)
end)
