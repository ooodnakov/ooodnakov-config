local colors = require("colors")

local function trim(value)
	return (value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function set_popup_label(item, value)
	item:set({
		label = {
			string = value,
			font = "MesloLGSDZ Nerd Font Mono:Regular:13.0",
		},
	})
end

local memory = sbar.add("item", "memory", {
	position = "e",
	update_freq = 10,
	icon = {
		string = "",
		font = "MesloLGSDZ Nerd Font Mono:Bold:20.0",
		padding_left = 8,
		color = colors.TEXT_ORANGE,
	},
	label = {
		font = "MesloLGSDZ Nerd Font Mono:Bold:13.0",
		padding_right = 8,
		color = colors.TEXT_ORANGE,
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

local used_item = sbar.add("item", {
	position = "popup." .. memory.name,
	icon = {
		string = "used",
		font = "MesloLGSDZ Nerd Font Mono:Bold:12.0",
	},
})

local wired_item = sbar.add("item", {
	position = "popup." .. memory.name,
	icon = {
		string = "wrd",
		font = "MesloLGSDZ Nerd Font Mono:Bold:12.0",
	},
})

local compressor_item = sbar.add("item", {
	position = "popup." .. memory.name,
	icon = {
		string = "cmp",
		font = "MesloLGSDZ Nerd Font Mono:Bold:12.0",
	},
})

local swap_item = sbar.add("item", {
	position = "popup." .. memory.name,
	icon = {
		string = "swp",
		font = "MesloLGSDZ Nerd Font Mono:Bold:12.0",
	},
})

local function refresh_memory()
	sbar.exec("top -l 1 | grep -E 'PhysMem|VM:'", function(result, exit_code)
		if exit_code ~= 0 then
			memory:set({
				label = { string = "--" },
			})
			set_popup_label(used_item, "Unavailable")
			set_popup_label(wired_item, "Unavailable")
			set_popup_label(compressor_item, "Unavailable")
			set_popup_label(swap_item, "Unavailable")
			return
		end

		local physmem = result:match("PhysMem:[^\r\n]+") or ""
		local vm = result:match("VM:[^\r\n]+") or ""
		local used = trim(physmem:match("([%d%.]+%a+ used)") or "")
		local wired = trim(physmem:match("([%d%.]+%a+ wired)") or "")
		local compressor = trim(physmem:match("([%d%.]+%a+ compressor)") or "")
		local swap = trim(vm:match("([%d%.]+[GMTK]?) swapins") or "")

		memory:set({
			label = {
				string = used ~= "" and used:gsub("%s+used$", "") or "--",
			},
		})

		set_popup_label(used_item, used ~= "" and used or "Unavailable")
		set_popup_label(wired_item, wired ~= "" and wired or "Unavailable")
		set_popup_label(compressor_item, compressor ~= "" and compressor or "Unavailable")
		set_popup_label(swap_item, swap ~= "" and (swap .. " swapins") or "Unavailable")
	end)
end

memory:subscribe({ "routine", "system_woke" }, function()
	refresh_memory()
end)

memory:subscribe("mouse.entered", function()
	memory:set({ popup = { drawing = true } })
end)

memory:subscribe("mouse.exited.global", function()
	memory:set({ popup = { drawing = false } })
end)

memory:subscribe("mouse.exited", function()
	memory:set({ popup = { drawing = false } })
end)

refresh_memory()
