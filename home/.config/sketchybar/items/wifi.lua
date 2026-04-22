local colors = require("colors")

local PUBLIC_IP_REFRESH_SECONDS = 300

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

local function refresh_public_ip(item, force)
	local now = os.time()
	local should_refresh = force
		or wifi_state.public_ip == nil
		or wifi_state.last_public_ip_refresh == nil
		or (now - wifi_state.last_public_ip_refresh) >= PUBLIC_IP_REFRESH_SECONDS

	if not should_refresh then
		set_popup_label(item, wifi_state.public_ip)
		return
	end

	sbar.exec("curl -fsS https://ipinfo.io/ip", function(result, exit_code)
		if exit_code == 0 then
			wifi_state.public_ip = trim(result)
			wifi_state.last_public_ip_refresh = now
		elseif wifi_state.public_ip == nil then
			wifi_state.public_ip = "Unavailable"
		end

		set_popup_label(item, wifi_state.public_ip or "Unavailable")
	end)
end

local wifi_state = {
	connected = false,
	ssid = "Disconnected",
	private_ip = "Unavailable",
	router = "Unavailable",
	public_ip = nil,
	last_public_ip_refresh = nil,
}

local wifi = sbar.add("item", "wifi", {
	position = "right",
	update_freq = 30,
	icon = {
		string = "",
	},
	label = {
		font = "MesloLGSDZ Nerd Font Mono:Italic:12.0",
		max_chars = 12,
	},
	scroll_texts = true,
	click_script = "open 'x-apple.systempreferences:com.apple.NetworkSettings'",
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

local ssid_item = sbar.add("item", {
	position = "popup." .. wifi.name,
	icon = {
		string = "󰖩",
		font = "MesloLGSDZ Nerd Font Mono:Regular:13.0",
	},
})

local private_ip_item = sbar.add("item", {
	position = "popup." .. wifi.name,
	icon = {
		string = "󰌗",
		font = "MesloLGSDZ Nerd Font Mono:Regular:13.0",
	},
})

local router_item = sbar.add("item", {
	position = "popup." .. wifi.name,
	icon = {
		string = "󰒓",
		font = "MesloLGSDZ Nerd Font Mono:Regular:13.0",
	},
})

local public_ip_item = sbar.add("item", {
	position = "popup." .. wifi.name,
	icon = {
		string = "󰖟",
		font = "MesloLGSDZ Nerd Font Mono:Regular:13.0",
	},
})

local function apply_popup_state()
	set_popup_label(ssid_item, wifi_state.ssid)
	set_popup_label(private_ip_item, wifi_state.private_ip)
	set_popup_label(router_item, wifi_state.router)
	set_popup_label(public_ip_item, wifi_state.public_ip or "Refreshing...")
end

local function update_summary()
	wifi:set({
		icon = {
			string = wifi_state.connected and "" or "",
			color = wifi_state.connected and colors.TEXT_WHITE or colors.TEXT_GREY,
		},
		label = {
			string = wifi_state.ssid,
			color = wifi_state.connected and colors.TEXT_WHITE or colors.TEXT_GREY,
		},
	})
end

local function refresh_wifi()
	sbar.exec("networksetup -getinfo Wi-Fi", function(local_info, exit_code)
		if exit_code ~= 0 then
			wifi_state.connected = false
			wifi_state.ssid = "Wi-Fi error"
			wifi_state.private_ip = "Unavailable"
			wifi_state.router = "Unavailable"
			update_summary()
			apply_popup_state()
			return
		end

		local ipv4 = trim(local_info:match("IP address:%s*([^\r\n]+)") or "")
		local router = trim(local_info:match("Router:%s*([^\r\n]+)") or "")
		local is_connected = ipv4 ~= "" and ipv4 ~= "none"

		wifi_state.connected = is_connected
		wifi_state.private_ip = is_connected and ipv4 or "Unavailable"
		wifi_state.router = (router ~= "" and router ~= "none") and router or "Unavailable"

		if not is_connected then
			wifi_state.ssid = "Disconnected"
			update_summary()
			apply_popup_state()
			return
		end

		sbar.exec("networksetup -getairportnetwork en0", function(airport_info, airport_exit_code)
			if airport_exit_code == 0 then
				local ssid = trim(airport_info:match(": (.+)$") or "")
				wifi_state.ssid = ssid ~= "" and ssid or "Connected"
			else
				wifi_state.ssid = "Connected"
			end

			update_summary()
			apply_popup_state()
		end)
	end)
end

wifi:subscribe({ "routine", "system_woke", "wifi_change" }, function()
	refresh_wifi()
end)

wifi:subscribe("mouse.entered", function()
	wifi:set({ popup = { drawing = true } })
	apply_popup_state()

	if wifi_state.connected then
		refresh_public_ip(public_ip_item, false)
	else
		set_popup_label(public_ip_item, "Offline")
	end
end)

wifi:subscribe("mouse.exited.global", function()
	wifi:set({ popup = { drawing = false } })
end)

wifi:subscribe("mouse.exited", function()
	wifi:set({ popup = { drawing = false } })
end)

refresh_wifi()
