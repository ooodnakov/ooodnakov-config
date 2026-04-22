local colors = require("colors")
local icon_map = require("helpers.icon_map")

local all_workspaces = {}
local workspace_states = {}
local spaces_ready = false

local function trim(value)
	return (value or ""):gsub("%s+$", "")
end

local function split_lines(value)
	local lines = {}
	for line in trim(value):gmatch("[^\r\n]+") do
		table.insert(lines, line)
	end
	return lines
end

local function shell_quote(value)
	return "'" .. tostring(value):gsub("'", [["'"']]) .. "'"
end

local function run(command, callback)
	sbar.exec(command, function(result, exit_code)
		if exit_code ~= 0 then
			callback("")
			return
		end

		callback(trim(result))
	end)
end

local function animate_space_popup(space, drawing)
	sbar.animate("tanh", 12, function()
		space:set({
			popup = {
				drawing = drawing,
			},
		})
	end)
end

local function icon_strip_for_windows(windows_raw)
	local icon_strip = " "

	for line in windows_raw:gmatch("[^\r\n]+") do
		local app_name = line:match("|%s*(.-)%s*|")
		if app_name then
			icon_strip = icon_strip .. " " .. icon_map(app_name)
		end
	end

	return icon_strip
end

local function app_names_for_windows(windows_raw)
	local app_names = {}

	for line in windows_raw:gmatch("[^\r\n]+") do
		local app_name = line:match("|%s*(.-)%s*|")
		if app_name then
			table.insert(app_names, app_name)
		end
	end

	if #app_names == 0 then
		return "Empty"
	end

	return table.concat(app_names, "   ")
end

local function app_icons_for_windows(windows_raw)
	local app_icons = {}

	for line in windows_raw:gmatch("[^\r\n]+") do
		local app_name = line:match("|%s*(.-)%s*|")
		if app_name then
			table.insert(app_icons, icon_map(app_name))
		end
	end

	if #app_icons == 0 then
		return ""
	end

	return table.concat(app_icons, " ")
end

local function states_equal(old, new)
	if (old == nil) ~= (new == nil) then
		return false
	end
	if old == nil then
		return true
	end

	return old.drawing == new.drawing
		and old.display == new.display
		and old.label_string == new.label_string
		and old.popup_icons == new.popup_icons
		and old.popup_string == new.popup_string
		and old.icon_color == new.icon_color
end

local function build_current_state(callback)
	run("aerospace list-workspaces --focused", function(focused_workspace)
		run("aerospace list-monitors", function(monitors_raw)
			local state = {}
			local monitors = split_lines(monitors_raw)

			if #monitors == 0 then
					if focused_workspace ~= "" then
						local previous = workspace_states[focused_workspace]
						state[focused_workspace] = {
							drawing = "on",
							display = previous and previous.display or "1",
							label_string = "",
							popup_icons = "",
							popup_string = "Empty",
							icon_color = colors.TEXT_WHITE,
						}
					end

				callback(state)
				return
			end

			local pending_monitors = #monitors

			local function finish_monitor()
				pending_monitors = pending_monitors - 1
				if pending_monitors > 0 then
					return
				end

					if focused_workspace ~= "" and state[focused_workspace] == nil then
						local previous = workspace_states[focused_workspace]
						state[focused_workspace] = {
							drawing = "on",
							display = previous and previous.display or "1",
							label_string = "",
							popup_icons = "",
							popup_string = "Empty",
							icon_color = colors.TEXT_WHITE,
						}
					end

				callback(state)
			end

			for i, _ in ipairs(monitors) do
				run("aerospace list-workspaces --monitor " .. i .. " --empty no", function(workspaces_raw)
					local non_empty_workspaces = split_lines(workspaces_raw)

					if #non_empty_workspaces == 0 then
						finish_monitor()
						return
					end

					local pending_workspaces = #non_empty_workspaces

					local function finish_workspace()
						pending_workspaces = pending_workspaces - 1
						if pending_workspaces == 0 then
							finish_monitor()
						end
					end

					for _, sid in ipairs(non_empty_workspaces) do
						run("aerospace list-windows --workspace " .. shell_quote(sid), function(windows_raw)
							state[sid] = {
								drawing = "on",
								display = tostring(i),
								label_string = icon_strip_for_windows(windows_raw),
								popup_icons = app_icons_for_windows(windows_raw),
								popup_string = app_names_for_windows(windows_raw),
								icon_color = (sid == focused_workspace) and colors.TEXT_WHITE or colors.TEXT_GREY,
							}

							finish_workspace()
						end)
					end
				end)
			end
		end)
	end)
end

local function rebalance_empty_workspaces()
	run("aerospace list-monitors --count", function(monitors_count)
		if monitors_count ~= "2" then
			return
		end

		run("aerospace list-workspaces --monitor 2 --empty", function(workspaces_raw)
			for _, sid in ipairs(split_lines(workspaces_raw)) do
				sbar.exec("aerospace move-workspace-to-monitor --workspace " .. shell_quote(sid) .. " 1")
			end
		end)
	end)
end

local function update_all_workspaces()
	if not spaces_ready then
		return
	end

	build_current_state(function(new_state)
		sbar.begin_config()

		for _, sid in ipairs(all_workspaces) do
			local old_ws_state = workspace_states[sid]
			local new_ws_state = new_state[sid]

			if new_ws_state == nil then
				if old_ws_state.drawing == "on" then
					sbar.set("space." .. sid, {
						drawing = "off",
						label = { string = "", color = colors.TEXT_GREY },
						icon = { color = colors.TEXT_GREY },
						background = {
							color = colors.TRANSPARENT,
							border_color = colors.TEXT_WHITE,
						},
					})

					sbar.set("space.popup." .. sid, {
						icon = { string = "" },
						label = { string = "Empty" },
					})

					workspace_states[sid].drawing = "off"
					workspace_states[sid].label_string = ""
					workspace_states[sid].popup_icons = ""
					workspace_states[sid].popup_string = "Empty"
					workspace_states[sid].icon_color = colors.TEXT_GREY
				end
			else
				if not states_equal(old_ws_state, new_ws_state) then
					local is_focused = (new_ws_state.icon_color == colors.TEXT_WHITE)

					sbar.animate("sin", 10, function()
						sbar.set("space." .. sid, {
							display = new_ws_state.display,
							drawing = new_ws_state.drawing,
							label = {
								string = new_ws_state.label_string,
								color = is_focused and colors.TEXT_WHITE or colors.TEXT_GREY,
							},
							icon = { color = new_ws_state.icon_color },
							background = {
								color = is_focused and colors.HIGHLIGHT_BACKGROUND or colors.TRANSPARENT,
								border_color = is_focused and colors.TEXT_GREY or colors.TEXT_WHITE,
							},
						})
					end)

					sbar.set("space.popup." .. sid, {
						icon = {
							string = new_ws_state.popup_icons,
						},
						label = {
							string = new_ws_state.popup_string,
						},
					})

					workspace_states[sid] = new_ws_state
				end
			end
		end

		sbar.end_config()
		rebalance_empty_workspaces()
	end)
end

local function initialize_spaces()
	run("aerospace list-workspaces --all", function(workspaces_raw)
		all_workspaces = split_lines(workspaces_raw)

		for _, sid in ipairs(all_workspaces) do
			local space = sbar.add("item", "space." .. sid, {
				position = "left",
				display = 1,
				drawing = "off",
				popup = {
					background = {
						color = colors.BACKGROUND,
						border_width = 2,
						border_color = colors.TEXT_GREY,
						corner_radius = 10,
					},
					y_offset = 5,
				},
				background = {
					corner_radius = 5,
					drawing = "on",
					border_width = 1,
					border_color = colors.TEXT_WHITE,
					height = 23,
					padding_right = 5,
					padding_left = 5,
				},
				icon = {
					string = sid,
					shadow = { drawing = "off" },
					padding_left = 10,
				},
				label = {
					font = "sketchybar-app-font:Regular:16.0",
					padding_right = 20,
					padding_left = 0,
					y_offset = -1,
					shadow = { drawing = "off" },
				},
				click_script = "aerospace workspace " .. sid,
			})

			sbar.add("item", "space.popup." .. sid, {
				position = "popup." .. space.name,
				y_offset = 0,
				height = 24,
				icon = {
					string = "",
					font = "sketchybar-app-font:Regular:14.0",
					color = colors.TEXT_WHITE,
					padding_left = 6,
					padding_right = 8,
				},
				label = {
					string = "Empty",
					font = "MesloLGSDZ Nerd Font Mono:Regular:12.0",
					color = colors.TEXT_WHITE,
					align = "left",
					max_chars = 36,
					y_offset = 0,
					padding_left = 0,
					padding_right = 6,
					scroll_texts = true,
				},
				width = 160,
				background = {
					drawing = "off",
				},
			})

			space:subscribe("mouse.entered", function()
				animate_space_popup(space, true)
			end)

			space:subscribe("mouse.exited.global", function()
				animate_space_popup(space, false)
			end)

			space:subscribe("mouse.exited", function()
				animate_space_popup(space, false)
			end)

			workspace_states[sid] = {
				drawing = "off",
				display = "1",
				label_string = "",
				popup_icons = "",
				popup_string = "Empty",
				icon_color = colors.TEXT_GREY,
			}
		end

		sbar.add("event", "aerospace_workspace_change")
		sbar.add("event", "aerospace_monitor_change")

		local observer = sbar.add("item", "spaces_observer", {
			position = "q",
			drawing = "off",
			background = { drawing = "off" },
		})

		observer:subscribe("aerospace_workspace_change", function()
			update_all_workspaces()
		end)

		observer:subscribe("space_windows_change", function()
			update_all_workspaces()
		end)

		observer:subscribe("front_app_switched", function()
			update_all_workspaces()
		end)

		observer:subscribe("aerospace_monitor_change", function(env)
			if env.FOCUSED_WORKSPACE and env.TARGET_MONITOR then
				sbar.set("space." .. env.FOCUSED_WORKSPACE, {
					display = env.TARGET_MONITOR,
				})

				if workspace_states[env.FOCUSED_WORKSPACE] then
					workspace_states[env.FOCUSED_WORKSPACE].display = tostring(env.TARGET_MONITOR)
				end
			end
		end)

		local space_names = {}
		for _, sid in ipairs(all_workspaces) do
			table.insert(space_names, "space." .. sid)
		end

		sbar.add("bracket", "spaces", space_names, {
			background = {
				color = colors.BACKGROUND,
				corner_radius = 10,
				height = 30,
			},
		})

		spaces_ready = true
		update_all_workspaces()
	end)
end

initialize_spaces()
