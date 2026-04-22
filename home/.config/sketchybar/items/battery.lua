local colors = require("colors")

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

local battery = sbar.add("item", "battery", {
	position = "right",
	update_freq = 120,
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

local percent_item = sbar.add("item", {
	position = "popup." .. battery.name,
	icon = {
		string = "Charge",
		font = "MesloLGSDZ Nerd Font Mono:Bold:12.0",
		width = 60,
		align = "left",
		color = colors.TEXT_GREY,
	},
})

local source_item = sbar.add("item", {
	position = "popup." .. battery.name,
	icon = {
		string = "Source",
		font = "MesloLGSDZ Nerd Font Mono:Bold:12.0",
		width = 60,
		align = "left",
		color = colors.TEXT_GREY,
	},
})

local eta_item = sbar.add("item", {
	position = "popup." .. battery.name,
	icon = {
		string = "ETA",
		font = "MesloLGSDZ Nerd Font Mono:Bold:12.0",
		width = 60,
		align = "left",
		color = colors.TEXT_GREY,
	},
})

local draw_item = sbar.add("item", {
	position = "popup." .. battery.name,
	icon = {
		string = "Draw",
		font = "MesloLGSDZ Nerd Font Mono:Bold:12.0",
		width = 60,
		align = "left",
		color = colors.TEXT_GREY,
	},
})

local health_item = sbar.add("item", {
	position = "popup." .. battery.name,
	icon = {
		string = "Health",
		font = "MesloLGSDZ Nerd Font Mono:Bold:12.0",
		width = 60,
		align = "left",
		color = colors.TEXT_GREY,
	},
})

local cycle_item = sbar.add("item", {
	position = "popup." .. battery.name,
	icon = {
		string = "Cycles",
		font = "MesloLGSDZ Nerd Font Mono:Bold:12.0",
		width = 60,
		align = "left",
		color = colors.TEXT_GREY,
	},
})

local function show_battery_popup()
	sbar.animate("tanh", 12, function()
		battery:set({ popup = { drawing = true } })
	end)
end

local function hide_battery_popup()
	sbar.animate("tanh", 12, function()
		battery:set({ popup = { drawing = false } })
	end)
end

local function refresh_battery()
	sbar.exec("pmset -g batt", function(batt_info, exit_code)
		if exit_code ~= 0 then
			battery:set({
				label = {
					string = "--",
				},
			})
			set_popup_label(percent_item, "n/a")
			set_popup_label(source_item, "n/a")
			set_popup_label(eta_item, "n/a")
			set_popup_label(draw_item, "n/a")
			set_popup_label(health_item, "n/a")
			set_popup_label(cycle_item, "n/a")
			return
		end

		local percentage = batt_info:match("(%d+)%%")
		local charging = batt_info:match("AC Power") ~= nil
		local time_remaining = batt_info:match("; (%d+:%d+)[; ]")
		local no_estimate = batt_info:match("no estimate") ~= nil

		if not percentage then
			return
		end

		local percent_num = tonumber(percentage)
		local icon = ""
		local colour = colors.TEXT_GREY

		if percent_num >= 90 then
			icon = ""
		elseif percent_num >= 60 then
			icon = ""
		elseif percent_num >= 30 then
			icon = ""
			colour = colors.TEXT_ORANGE
		elseif percent_num >= 10 then
			icon = ""
			colour = colors.TEXT_RED
		else
			icon = ""
			colour = colors.TEXT_RED
		end

		if charging then
			icon = ""
		end

		battery:set({
			icon = {
				string = icon,
				color = colour,
				font = "MesloLGSDZ Nerd Font Mono:Regular:13.0",
			},
			label = {
				string = percentage .. "%",
				color = colour,
				font = "MesloLGSDZ Nerd Font Mono:Regular:13.0",
			},
		})

		set_popup_label(percent_item, percentage .. "%")
		set_popup_label(source_item, charging and "AC power" or "Battery")

		if no_estimate then
			set_popup_label(eta_item, "n/a")
		else
			set_popup_label(eta_item, time_remaining or "n/a")
		end

		sbar.exec(
			[[ioreg -r -c AppleSmartBattery -l | awk -F'= ' '/"InstantAmperage" =/ { amp=$2 } /"Voltage" =/ && !volt { volt=$2 } END { gsub(/ /, "", amp); gsub(/ /, "", volt); if (amp == "" || volt == "") exit 1; if (amp > 9223372036854775807) amp = amp - 18446744073709551616; watts = (amp * volt) / 1000000; if (watts < 0) watts = -watts; printf "%.1fW\n", watts; }']],
			function(draw_info, draw_exit_code)
				if draw_exit_code ~= 0 then
					set_popup_label(draw_item, "n/a")
					return
				end

				local draw = draw_info:match("([%d%.]+W)")
				set_popup_label(draw_item, draw or "n/a")
			end
		)

		sbar.exec(
			[[ioreg -r -c AppleSmartBattery -l | awk -F'= ' '/"AppleRawMaxCapacity" =/ { max=$2 } /"DesignCapacity" =/ { design=$2 } /"CycleCount" =/ { cycle=$2 } END { gsub(/ /, "", max); gsub(/ /, "", design); gsub(/ /, "", cycle); if (max == "" || design == "") { print "n/a|n/a"; exit 0 } health = (max / design) * 100; printf "%.0f%%|%s\n", health, (cycle == "" ? "n/a" : cycle); }']],
			function(health_info, health_exit_code)
				if health_exit_code ~= 0 then
					set_popup_label(health_item, "n/a")
					set_popup_label(cycle_item, "n/a")
					return
				end

				local health, cycles = health_info:match("([^|]+)|(.+)")
				set_popup_label(health_item, health or "n/a")
				set_popup_label(cycle_item, cycles or "n/a")
			end
		)
	end)
end

battery:subscribe({ "routine", "system_woke", "power_source_change" }, function()
	refresh_battery()
end)

battery:subscribe("mouse.entered", function()
	show_battery_popup()
end)

battery:subscribe("mouse.exited.global", function()
	hide_battery_popup()
end)

battery:subscribe("mouse.exited", function()
	hide_battery_popup()
end)

refresh_battery()
