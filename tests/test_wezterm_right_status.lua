-- Run from the repository root: lua tests/test_wezterm_right_status.lua
package.path = 'home/.config/wezterm/?.lua;' .. package.path

local update_status
local local_host = 'workstation'
package.preload.wezterm = function()
   return {
      nerdfonts = setmetatable({}, { __index = function(_, key) return '<' .. key .. '>' end }),
      home_dir = '/home/tester',
      hostname = function() return local_host end,
      battery_info = function() return {} end,
      column_width = function(text) return #text end,
      truncate_left = function(text, width) return text:sub(-width) end,
      strftime = function() return '12:34:56' end,
      log_error = error,
      on = function(event, callback)
         assert(event == 'update-status')
         update_status = callback
      end,
      format = function(items)
         local text = {}
         for _, item in ipairs(items) do
            if type(item) == 'table' and item.Text then
               text[#text + 1] = item.Text
            end
         end
         return table.concat(text)
      end,
   }
end

require('events.right-status').setup()

local function pane(uri, argv, domain, executable)
   return {
      get_current_working_dir = function() return uri end,
      get_foreground_process_name = function() return executable or (argv and argv[1]) end,
      get_foreground_process_info = function()
         if argv then
            return { argv = argv, executable = executable or argv[1] }
         end
      end,
      get_domain_name = function() return domain or 'local' end,
   }
end

local function check(name, current_pane, host, cwd, domains)
   local status
   local window = {
      set_right_status = function(_, text) status = text end,
      effective_config = function() return { ssh_domains = domains or {} } end,
   }
   update_status(window, current_pane)
   assert(status:find('<cod_server> ' .. host .. ' ', 1, true), name .. ': wrong host: ' .. status)
   if cwd then
      assert(status:find('<cod_folder> ' .. cwd .. ' ', 1, true), name .. ': wrong cwd: ' .. status)
   else
      assert(not status:find('<cod_folder>', 1, true), name .. ': misleading cwd: ' .. status)
   end
   print('PASS: ' .. name)
end

check('local host without cwd', pane(nil), 'workstation')
check('missing pane', nil, 'workstation')
check('local cwd', pane('file://workstation/home/tester/project'), 'workstation', '~/project')
check('remote OSC 7', pane('file://remote.example/srv/project%20files'), 'remote.example', '/srv/project files')
check('hostless local URI', pane('file:///home/tester/project'), 'workstation', '~/project')
check('plain SSH without OSC 7', pane(nil, { 'ssh', 'user@remote' }), 'remote')
check('stale local OSC 7', pane('file://workstation/home/tester', { 'ssh', 'remote' }), 'remote')
check('SSH options', pane(nil, { '/usr/bin/ssh', '-p', '2222', '-i', '/tmp/key', '-J', 'jump', '-o', 'ServerAliveInterval=10', 'user@remote', 'uptime' }), 'remote')
check('attached SSH options', pane(nil, { 'ssh', '-vvTp2222', '-luser', '-oHostName=target', 'alias' }), 'alias')
check('SSH option terminator', pane(nil, { 'ssh', '--', 'user@remote' }), 'remote')
check('SSH URI', pane(nil, { 'ssh', 'ssh://user@remote.example:2222' }), 'remote.example')
check('IPv6 SSH URI', pane(nil, { 'ssh', 'ssh://user@[2001:db8::1]:2222' }), '2001:db8::1')
check('Windows SSH executable', pane(nil, { 'ssh.exe', 'user@remote' }, nil, 'C:\\Windows\\System32\\OpenSSH\\ssh.exe'), 'remote')
check('remote metadata wins for nested SSH', pane('file://inner/srv/app', { 'ssh', 'outer' }), 'inner', '/srv/app')
check('SSH domain without OSC 7', pane(nil, nil, 'prod'), 'remote.example', nil, {
   { name = 'prod', remote_address = 'remote.example:2222' },
})
check('IPv6 SSH domain', pane(nil, nil, 'prod'), '2001:db8::1', nil, {
   { name = 'prod', remote_address = '[2001:db8::1]:2222' },
})
check('remote metadata wins over domain', pane('file://inner/srv/app', nil, 'prod'), 'inner', '/srv/app', {
   { name = 'prod', remote_address = 'outer' },
})
check('SSH disconnect restores local host', pane('file://workstation/home/tester', { 'zsh' }), 'workstation', '~')
check('ordinary process args are not SSH', pane('file://workstation/tmp', { 'vim', 'user@remote' }), 'workstation', '/tmp')
print('All WezTerm right-status regressions passed.')
