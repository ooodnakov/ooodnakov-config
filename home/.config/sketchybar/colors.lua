local colors = {
  -- Keep SketchyBar's existing role names, but source the palette from Noctalia.
  TEXT_WHITE = 0xFFFBF1C7,
  TEXT_GREY = 0xFFEBDBB2,
  TEXT_SPOTIFY_GREEN = 0xFF1DB954,
  TEXT_RED = 0xFFFB4934,
  TEXT_ORANGE = 0xFFFABD2F,
  BACKGROUND = 0xDA3C3836,
  BACKGROUND_DARK = 0xFF282828,
  BACKGROUND_DARK_BLUE = 0xFF2F4346,
  BACKGROUND_DARK_ORANGE = 0xFF5B4314,
  BACKGROUND_DARK_GREEN = 0xFF4A5423,
  BACKGROUND_DARK_RED = 0xFF5A2D28,
  BACKGROUND_DARKER = 0xFF282828,
  HIGHLIGHT_BACKGROUND = 0xCFB8BB26,
  TRANSPARENT = 0x00000000,
}

local local_override_path = os.getenv("HOME") .. "/.config/ooodnakov/local/sketchybar/colors.lua"
local handle = io.open(local_override_path, "r")
if handle then
  handle:close()
  local ok, local_colors = pcall(dofile, local_override_path)
  if ok and type(local_colors) == "table" then
    for key, value in pairs(local_colors) do
      colors[key] = value
    end
  end
end

return colors
