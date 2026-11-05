-- The greeter starts Hyprland without Home Manager's variables, which the user
-- manager holds (environment.d). Copy the ones the session needs: Qt theming
-- for qt5ct/qt6ct and the cursor.
local wanted = { "^QT_", "^QML2_IMPORT_PATH$", "^XCURSOR_", "^EDITOR$", "^VISUAL$" }

local function wanted_key(key)
  for _, pattern in ipairs(wanted) do
    if key:match(pattern) then
      return true
    end
  end
  return false
end

local function import(lines)
  for line in lines do
    local key, value = line:match("^([%w_]+)=(.*)$")
    -- show-environment quotes exotic values as $'...'; those are not ours.
    if key and wanted_key(key) and not value:match("^%$'") and not os.getenv(key) then
      hl.env(key, value)
    end
  end
end

local function lines_of(cmd)
  local pipe = io.popen(cmd .. " 2>/dev/null")
  if not pipe then
    return function() end
  end
  local iter = pipe:lines()
  return function()
    local line = iter()
    if line == nil then
      pipe:close()
    end
    return line
  end
end

pcall(import, lines_of("systemctl --user show-environment"))

-- Hyprland leaves the user manager's variables alone and the environment.d
-- file keeps them across sessions (Hyprland's own logout unsets some).
local hm = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/environment.d/10-home-manager.conf"
local file = io.open(hm)
if file then
  pcall(import, file:lines())
  file:close()
end

-- Same theme as home.pointerCursor in home.nix.
hl.env("XCURSOR_THEME", "Bibata-Modern-Classic")
hl.env("XCURSOR_SIZE", "24")
