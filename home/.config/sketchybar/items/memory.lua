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
			padding_left = 4,
		},
	})
end

local memory = sbar.add("item", "memory", {
	position = "right",
	update_freq = 10,
	icon = {
		string = "",
		font = "MesloLGSDZ Nerd Font Mono:Bold:20.0",
		padding_left = 4,
		color = colors.TEXT_ORANGE,
	},
	label = {
		font = "MesloLGSDZ Nerd Font Mono:Bold:12.0",
		padding_right = 4,
		color = colors.TEXT_ORANGE,
	},
	background = {
		drawing = "off",
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
		string = "Used",
		font = "MesloLGSDZ Nerd Font Mono:Bold:12.0",
		width = 54,
		align = "left",
		color = colors.TEXT_GREY,
		padding_left=5,
	},
})

local wired_item = sbar.add("item", {
	position = "popup." .. memory.name,
	icon = {
		string = "Wired",
		font = "MesloLGSDZ Nerd Font Mono:Bold:12.0",
		width = 54,
		align = "left",
		color = colors.TEXT_GREY,
		padding_left=5,
	},
})

local compressor_item = sbar.add("item", {
	position = "popup." .. memory.name,
	icon = {
		string = "Comp",
		font = "MesloLGSDZ Nerd Font Mono:Bold:12.0",
		width = 54,
		align = "left",
		color = colors.TEXT_GREY,
		padding_left=5,
	},
})

local swap_item = sbar.add("item", {
	position = "popup." .. memory.name,
	icon = {
		string = "Swap",
		font = "MesloLGSDZ Nerd Font Mono:Bold:12.0",
		width = 54,
		align = "left",
		color = colors.TEXT_GREY,
		padding_left=5,
	},
})

local function refresh_memory()
	sbar.exec("top -l 1 | grep -E 'PhysMem|VM:'", function(result, exit_code)
		if exit_code ~= 0 then
			memory:set({
				label = { string = "--" },
			})
			set_popup_label(used_item, "n/a")
			set_popup_label(wired_item, "n/a")
			set_popup_label(compressor_item, "n/a")
			set_popup_label(swap_item, "n/a")
			return
		end

		local physmem = result:match("PhysMem:[^\r\n]+") or ""
        local vm = result:match("VM:[^\r\n]+") or ""
        local used = trim(physmem:match("([%d%%.]+%a+ used)") or "")
        local wired = trim(physmem:match("([%d%%.]+%a+ wired)") or "")
		local compressor = trim(physmem:match("([%d%.]+%a+ compressor)") or "")
        -- Convert memory values to gigabytes if they are in megabytes
        local function format_to_gb(value)
            if value:match("(%d+%.?%d*)M") then
                local mb = tonumber(value:match("(%d+%.?%d*)"))
                local gb = mb / 1024
                if gb < 1 then
                    return string.format("%.1fM", mb)
                else
                    return string.format("%.1fG", gb)
                end
            end
            return value:gsub("%s+[a-zA-Z]+", "")
        end

        used = format_to_gb(used)
        wired = format_to_gb(wired)
		compressor = format_to_gb(compressor)
		local swap = trim(vm:match("(%d+)%b() swapins") or "")

		memory:set({
			label = {
				string = used ~= "" and used:gsub("%s+used$", ""):gsub("%.0([GMK])", "%1") or "--",
			},
		})

		set_popup_label(used_item, used ~= "" and used:gsub("%s+used$", "") or "n/a")
		set_popup_label(wired_item, wired ~= "" and wired:gsub("%s+wired$", "") or "n/a")
		set_popup_label(compressor_item, compressor ~= "" and compressor:gsub("%s+compressor$", "") or "n/a")
		set_popup_label(swap_item, swap ~= "" and swap or "n/a")
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
