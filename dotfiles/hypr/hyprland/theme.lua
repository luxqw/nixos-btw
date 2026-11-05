-- Caelestia's scheme as Hyprland colours. Caelestia rewrites scheme/current.lua
-- (a plain table of hex strings) on every wallpaper or scheme change; this
-- module reads it with dofile, not require, so that a scheme change does not
-- reload the config and re-apply the monitor rules. session-theme calls
-- apply() through `hyprctl eval` to repaint a running session.
local M = {}

local defaults = {
  surface = "131317",
  surfaceContainer = "201f23",
  onSurfaceVariant = "c8c5d1",
  primary = "c2c1ff",
  inversePrimary = "595992",
}

function M.scheme()
  local path = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/hypr/scheme/current.lua"
  local ok, scheme = pcall(dofile, path)
  if ok and type(scheme) == "table" then
    return setmetatable(scheme, { __index = defaults })
  end
  return defaults
end

function M.apply()
  local s = M.scheme()
  hl.config({
    general = {
      col = {
        active_border = "rgba(" .. s.primary .. "e6)",
        inactive_border = "rgba(" .. s.onSurfaceVariant .. "11)",
      },
    },
    decoration = {
      shadow = { color = "rgba(" .. s.inversePrimary .. "10)" },
    },
    misc = {
      background_color = "rgb(" .. s.surfaceContainer .. ")",
    },
  })
end

return M
