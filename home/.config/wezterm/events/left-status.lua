local wezterm = require('wezterm')
local Cells = require('utils.cells')

local nf = wezterm.nerdfonts
local attr = Cells.attr

local M = {}

local GLYPH_SEMI_CIRCLE_LEFT = nf.ple_left_half_circle_thick --[[ '' ]]
local GLYPH_SEMI_CIRCLE_RIGHT = nf.ple_right_half_circle_thick --[[ '' ]]
local GLYPH_WORKSPACE = nf.cod_window --[[ '' ]]
local GLYPH_KEY_TABLE = nf.md_table_key --[[ '󱏅' ]]
local GLYPH_KEY = nf.md_key --[[ '󰌆' ]]
local GLYPH_ZOOM = nf.md_fullscreen --[[ '󰊓' ]]

---@type table<string, Cells.SegmentColors>
local colors = {
   default = { bg = '#fab387', fg = '#1c1b19' },
   leader = { bg = '#a6e3a1', fg = '#1c1b19' },
   workspace = { bg = '#74c7ec', fg = '#11111b' },
   zoom = { bg = '#cba6f7', fg = '#11111b' },
   scircle_default = { bg = 'rgba(0, 0, 0, 0.4)', fg = '#fab387' },
   scircle_leader = { bg = 'rgba(0, 0, 0, 0.4)', fg = '#a6e3a1' },
   scircle_workspace = { bg = 'rgba(0, 0, 0, 0.4)', fg = '#74c7ec' },
   scircle_zoom = { bg = 'rgba(0, 0, 0, 0.4)', fg = '#cba6f7' },
}

local cells = Cells:new()

cells
   :add_segment('workspace_left', GLYPH_SEMI_CIRCLE_LEFT, colors.scircle_workspace)
   :add_segment('workspace_icon', GLYPH_WORKSPACE .. ' ', colors.workspace, attr(attr.intensity('Bold')))
   :add_segment('workspace_text', '', colors.workspace, attr(attr.intensity('Bold')))
   :add_segment('workspace_right', GLYPH_SEMI_CIRCLE_RIGHT .. ' ', colors.scircle_workspace)
   :add_segment('mode_left', GLYPH_SEMI_CIRCLE_LEFT, colors.scircle_default)
   :add_segment('mode_icon', ' ', colors.default, attr(attr.intensity('Bold')))
   :add_segment('mode_text', ' ', colors.default, attr(attr.intensity('Bold')))
   :add_segment('mode_right', GLYPH_SEMI_CIRCLE_RIGHT .. ' ', colors.scircle_default)
   :add_segment('zoom_left', GLYPH_SEMI_CIRCLE_LEFT, colors.scircle_zoom)
   :add_segment('zoom_icon', GLYPH_ZOOM .. ' ', colors.zoom, attr(attr.intensity('Bold')))
   :add_segment('zoom_text', 'ZOOM', colors.zoom, attr(attr.intensity('Bold')))
   :add_segment('zoom_right', GLYPH_SEMI_CIRCLE_RIGHT, colors.scircle_zoom)

local function active_pane_is_zoomed(pane)
   if not pane then
      return false
   end

   local ok, tab = pcall(function()
      return pane:tab()
   end)
   if not ok or not tab or type(tab.panes_with_info) ~= 'function' then
      return false
   end

   local panes_ok, panes = pcall(function()
      return tab:panes_with_info()
   end)
   if not panes_ok or type(panes) ~= 'table' then
      return false
   end

   for _, pane_info in ipairs(panes) do
      if pane_info.is_active then
         return pane_info.is_zoomed or false
      end
   end

   return false
end

M.setup = function()
   wezterm.on('update-status', function(window, pane)
      local segments = { 'workspace_left', 'workspace_icon', 'workspace_text', 'workspace_right' }
      local mode_name = window:active_key_table()

      cells:update_segment_text('workspace_text', window:active_workspace())

      if mode_name then
         cells
            :update_segment_text('mode_icon', GLYPH_KEY_TABLE .. ' ')
            :update_segment_text('mode_text', string.upper(mode_name))
            :update_segment_colors('mode_left', colors.scircle_default)
            :update_segment_colors('mode_icon', colors.default)
            :update_segment_colors('mode_text', colors.default)
            :update_segment_colors('mode_right', colors.scircle_default)
         for _, segment in ipairs({ 'mode_left', 'mode_icon', 'mode_text', 'mode_right' }) do
            table.insert(segments, segment)
         end
      elseif window:leader_is_active() then
         cells
            :update_segment_text('mode_icon', GLYPH_KEY .. ' ')
            :update_segment_text('mode_text', 'LEADER')
            :update_segment_colors('mode_left', colors.scircle_leader)
            :update_segment_colors('mode_icon', colors.leader)
            :update_segment_colors('mode_text', colors.leader)
            :update_segment_colors('mode_right', colors.scircle_leader)
         for _, segment in ipairs({ 'mode_left', 'mode_icon', 'mode_text', 'mode_right' }) do
            table.insert(segments, segment)
         end
      end

      if active_pane_is_zoomed(pane) then
         for _, segment in ipairs({ 'zoom_left', 'zoom_icon', 'zoom_text', 'zoom_right' }) do
            table.insert(segments, segment)
         end
      end

      window:set_left_status(wezterm.format(cells:render(segments)))
   end)
end

return M
