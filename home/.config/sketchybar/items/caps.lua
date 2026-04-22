local colors = require("colors")

local kan = sbar.add("item", "kan", {
	position = "right",
	update_freq = 1,
	icon = {
		string = "",
		font = "MesloLGSDZ Nerd Font Mono:Regular:13.0",
		padding_left = 4,
		color = colors.TEXT_GREY,
	},
	label = {
		string = "en",
		font = "MesloLGSDZ Nerd Font Mono:Regular:13.0",
		padding_right = 4,
		color = colors.TEXT_GREY,
	},
	background = {
		drawing = "off",
	},
})

local caps_lock_state_cmd = [[swift -e 'import AppKit; print(NSEvent.modifierFlags.contains(.capsLock) ? "ru" : "en")']]
local toggle_caps_lock_cmd = [[osascript -e 'tell application "System Events" to key code 57']]

kan:subscribe({ "routine", "forced", "system_woke" }, function()
	sbar.exec(caps_lock_state_cmd, function(state)
		local normalized = tostring(state):gsub("%s+$", "")
		kan:set({
			label = { string = (normalized == "ru") and "ru" or "en" },
		})
	end)
end)

kan:subscribe("mouse.clicked", function()
	sbar.exec(toggle_caps_lock_cmd, function()
		sbar.trigger("forced")
	end)
end)

sbar.trigger("forced")
