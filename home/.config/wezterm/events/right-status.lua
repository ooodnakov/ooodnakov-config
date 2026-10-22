local wezterm = require('wezterm')
local umath = require('utils.math')
local Cells = require('utils.cells')
local OptsValidator = require('utils.opts-validator')

---@alias Event.RightStatusOptions { date_format?: string }

---Setup options for the right status bar
local EVENT_OPTS = {}

---@type OptsSchema
EVENT_OPTS.schema = {
   {
      name = 'date_format',
      type = 'string',
      default = '%a %H:%M:%S',
   },
}
EVENT_OPTS.validator = OptsValidator:new(EVENT_OPTS.schema)

local nf = wezterm.nerdfonts
local attr = Cells.attr

local M = {}

local ICON_SEPARATOR = nf.oct_dash
local ICON_DATE = nf.fa_calendar
local ICON_CWD = nf.cod_folder
local ICON_HOST = nf.cod_server

---@type string[]
local discharging_icons = {
   nf.md_battery_10,
   nf.md_battery_20,
   nf.md_battery_30,
   nf.md_battery_40,
   nf.md_battery_50,
   nf.md_battery_60,
   nf.md_battery_70,
   nf.md_battery_80,
   nf.md_battery_90,
   nf.md_battery,
}
---@type string[]
local charging_icons = {
   nf.md_battery_charging_10,
   nf.md_battery_charging_20,
   nf.md_battery_charging_30,
   nf.md_battery_charging_40,
   nf.md_battery_charging_50,
   nf.md_battery_charging_60,
   nf.md_battery_charging_70,
   nf.md_battery_charging_80,
   nf.md_battery_charging_90,
   nf.md_battery_charging,
}

---@type table<string, Cells.SegmentColors>
-- stylua: ignore
local colors = {
   date      = { fg = '#fab387', bg = 'rgba(0, 0, 0, 0.4)' },
   battery   = { fg = '#f9e2af', bg = 'rgba(0, 0, 0, 0.4)' },
   cwd       = { fg = '#a6e3a1', bg = 'rgba(0, 0, 0, 0.4)' },
   host      = { fg = '#89b4fa', bg = 'rgba(0, 0, 0, 0.4)' },
   separator = { fg = '#74c7ec', bg = 'rgba(0, 0, 0, 0.4)' }
}

local cells = Cells:new()

cells
   :add_segment('host_icon', ICON_HOST .. ' ', colors.host, attr(attr.intensity('Bold')))
   :add_segment('host_text', '', colors.host, attr(attr.intensity('Bold')))
   :add_segment('separator_host', ' ' .. ICON_SEPARATOR .. '  ', colors.separator)
   :add_segment('cwd_icon', ICON_CWD .. ' ', colors.cwd, attr(attr.intensity('Bold')))
   :add_segment('cwd_text', '', colors.cwd, attr(attr.intensity('Bold')))
   :add_segment('separator_cwd', ' ' .. ICON_SEPARATOR .. '  ', colors.separator)
   :add_segment('date_icon', ICON_DATE .. '  ', colors.date, attr(attr.intensity('Bold')))
   :add_segment('date_text', '', colors.date, attr(attr.intensity('Bold')))
   :add_segment('separator_date', ' ' .. ICON_SEPARATOR .. '  ', colors.separator)
   :add_segment('battery_icon', '', colors.battery)
   :add_segment('battery_text', '', colors.battery, attr(attr.intensity('Bold')))

---@return string, string
local function battery_info()
   -- ref: https://wezfurlong.org/wezterm/config/lua/wezterm/battery_info.html

   local charge = ''
   local icon = ''
   local ok, batteries = pcall(wezterm.battery_info)

   if not ok or type(batteries) ~= 'table' then
      return charge, icon
   end

   for _, b in ipairs(batteries) do
      local idx = umath.clamp(umath.round(b.state_of_charge * 10), 1, 10)
      charge = string.format('%.0f%%', b.state_of_charge * 100)

      if b.state == 'Charging' then
         icon = charging_icons[idx]
      else
         icon = discharging_icons[idx]
      end
   end

   if icon == '' then
      return charge, icon
   end
   return charge, icon .. ' '
end

local function shorten_cwd(path)
   if not path or path == '' then
      return ''
   end

   path = path:gsub('^file://', ''):gsub('%%20', ' ')
   path = path:gsub('^' .. wezterm.home_dir:gsub('([^%w])', '%%%1'), '~')
   local max_len = 42
   if wezterm.column_width(path) > max_len then
      path = '…' .. wezterm.truncate_left(path, max_len - 1)
   end
   return path
end

local function destination_host(destination)
   destination = destination:gsub('^ssh://', ''):gsub('/.*$', ''):gsub('^.*@', '')
   destination = destination:match('^%[([^%]]+)%]')
      or destination:match('^([^:]+):%d+$')
      or destination
   return destination ~= '' and destination or nil
end

local SSH_VALUE_OPTIONS = 'BbcDEeFIiJLlmOoPpQRSWw'

local function ssh_host(pane)
   local executable = pane:get_foreground_process_name()
   if not executable or executable == '' then
      return nil
   end
   executable = executable:gsub('.*[/\\]', ''):lower()
   if executable ~= 'ssh' and executable ~= 'ssh.exe' then
      return nil
   end

   local process = pane:get_foreground_process_info()
   local argv = process and process.argv
   if not argv or not argv[1] then
      return nil
   end

   local i = 2
   while i <= #argv do
      local arg = argv[i]
      if arg == '--' then
         return argv[i + 1] and destination_host(argv[i + 1])
      end
      if arg:sub(1, 1) ~= '-' then
         return destination_host(arg)
      end

      -- OpenSSH accepts both "-p 2222" and grouped/attached options like "-vTp2222".
      for j = 2, #arg do
         if SSH_VALUE_OPTIONS:find(arg:sub(j, j), 1, true) then
            if j == #arg then
               i = i + 1
            end
            break
         end
      end
      i = i + 1
   end
end

local function is_local_host(host)
   host = host:lower()
   local local_host = wezterm.hostname():lower()
   return host == 'localhost'
      or host == local_host
      or host == local_host:match('^[^.]+')
      or local_host == host:match('^[^.]+')
end

local function cwd_and_host(window, pane)
   local local_host = wezterm.hostname()
   if not pane then
      return '', local_host
   end

   local uri = pane:get_current_working_dir()
   local path, host
   if type(uri) == 'userdata' then
      path, host = uri.file_path, uri.host
   elseif type(uri) == 'string' then
      host, path = uri:match('^%w+://([^/]*)(/.*)$')
      path = (path or uri):gsub('%%(%x%x)', function(hex)
         return string.char(tonumber(hex, 16))
      end)
   end

   -- Remote OSC 7 metadata identifies nested SSH hosts, so it outranks the
   -- destination of the local SSH client. A local URI must not override SSH.
   if host and host ~= '' and not is_local_host(host) then
      return shorten_cwd(path), host
   end

   local ssh_destination = ssh_host(pane)
   if not ssh_destination then
      local domain_name = pane:get_domain_name()
      if domain_name ~= 'local' then
         for _, domain in ipairs(window:effective_config().ssh_domains or {}) do
            if domain.name == domain_name and type(domain.remote_address) == 'string' then
               ssh_destination = destination_host(domain.remote_address)
               break
            end
         end
      end
   end

   if ssh_destination then
      -- Without remote OSC 7, the URI still describes the local SSH client.
      return '', ssh_destination
   end
   return shorten_cwd(path), host ~= '' and host or local_host
end

---@param opts? Event.RightStatusOptions Default: {date_format = '%a %H:%M:%S'}
M.setup = function(opts)
   local valid_opts, err = EVENT_OPTS.validator:validate(opts or {})

   if err then
      wezterm.log_error(err)
   end

   wezterm.on('update-status', function(window, pane)
      local battery_text, battery_icon = battery_info()
      local cwd, host = cwd_and_host(window, pane)
      local segments = { 'host_icon', 'host_text', 'separator_host', 'date_icon', 'date_text' }

      cells
         :update_segment_text('host_text', host)
         :update_segment_text('cwd_text', cwd)
         :update_segment_text('date_text', wezterm.strftime(valid_opts.date_format))
         :update_segment_text('battery_icon', battery_icon)
         :update_segment_text('battery_text', battery_text)

      if cwd ~= '' then
         segments = {
            'host_icon',
            'host_text',
            'separator_host',
            'cwd_icon',
            'cwd_text',
            'separator_cwd',
            'date_icon',
            'date_text',
         }
      end

      if battery_text ~= '' then
         table.insert(segments, 'separator_date')
         table.insert(segments, 'battery_icon')
         table.insert(segments, 'battery_text')
      end

      window:set_right_status(wezterm.format(cells:render(segments)))
   end)
end

return M
