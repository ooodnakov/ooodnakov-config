local colors = require("colors")

local function trim(value)
	return (value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function set_popup_label(item, value)
	item:set({
		label = {
			string = value,
			font = "MesloLGSDZ Nerd Font Mono:Regular:12.0",
			color = colors.TEXT_WHITE,
			padding_left = 8,
		},
	})
end

local cpu = sbar.add("item", "cpu", {
	position = "e",
	update_freq = 10,
	icon = {
		string = "",
		font = "MesloLGSDZ Nerd Font Mono:Bold:20.0",
		padding_left = 8,
		color = colors.TEXT_RED,
	},
	label = {
		font = "MesloLGSDZ Nerd Font Mono:Bold:12.0",
		padding_right = 8,
		color = colors.TEXT_RED,
	},
	background = {
		corner_radius = 10,
		color = colors.BACKGROUND_DARK,
		height = 30,
	},
	drawing = "on",
	click_script = "open -a 'Activity Monitor'",
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

local user_item = sbar.add("item", {
	position = "popup." .. cpu.name,
	icon = {
		string = "User",
		font = "MesloLGSDZ Nerd Font Mono:Bold:12.0",
		width = 46,
		align = "left",
		color = colors.TEXT_GREY,
	},
})

local system_item = sbar.add("item", {
	position = "popup." .. cpu.name,
	icon = {
		string = "System",
		font = "MesloLGSDZ Nerd Font Mono:Bold:12.0",
		width = 46,
		align = "left",
		color = colors.TEXT_GREY,
	},
})

local idle_item = sbar.add("item", {
	position = "popup." .. cpu.name,
	icon = {
		string = "Idle",
		font = "MesloLGSDZ Nerd Font Mono:Bold:12.0",
		width = 46,
		align = "left",
		color = colors.TEXT_GREY,
	},
})

local function refresh_cpu()
	sbar.exec("top -l 1 | grep 'CPU usage'", function(result, exit_code)
		if exit_code ~= 0 then
			cpu:set({
				label = { string = "--" },
			})
			set_popup_label(user_item, "Unavailable")
			set_popup_label(system_item, "Unavailable")
			set_popup_label(idle_item, "Unavailable")
			return
		end

		local user = trim(result:match("([%d%.]+)%% user") or "")
		local system = trim(result:match("([%d%.]+)%% sys") or "")
		local idle = trim(result:match("([%d%.]+)%% idle") or "")
		local total = tonumber(user) and tonumber(system) and (tonumber(user) + tonumber(system)) or nil

		cpu:set({
			label = {
				string = total and string.format("%2d%%", math.floor(total + 0.5)) or "--",
			},
		})

		set_popup_label(user_item, (user ~= "" and user or "--") .. "%")
		set_popup_label(system_item, (system ~= "" and system or "--") .. "%")
		set_popup_label(idle_item, (idle ~= "" and idle or "--") .. "%")
	end)
end

cpu:subscribe({ "routine", "system_woke" }, function()
	refresh_cpu()
end)

cpu:subscribe("mouse.entered", function()
	cpu:set({ popup = { drawing = true } })
end)

cpu:subscribe("mouse.exited.global", function()
	cpu:set({ popup = { drawing = false } })
end)

cpu:subscribe("mouse.exited", function()
	cpu:set({ popup = { drawing = false } })
end)

refresh_cpu()
