-- Ported from ../niri/config.kdl; the shell binds go to Caelestia. Dropped (no
-- Hyprland equivalent): overview (Mod+O), hotkey overlay, move workspace
-- (Mod+Shift+PageUp/Down, U, I), column to first/last (Mod+Ctrl+Home/End),
-- preset window height (Mod+Shift+R). Mod+Space (us/ru) is xkb's, see input.lua.
-- dotfiles/keyhints/hyprland.toml lists these for Mod+F1; keep the two in step.
local M = "SUPER"

local exec = hl.dsp.exec_cmd
local global = hl.dsp.global
local layout = hl.dsp.layout
local focus = hl.dsp.focus
local move = hl.dsp.window.move

local locked = { locked = true }
local locked_repeating = { locked = true, repeating = true }
local repeating = { repeating = true }

local function bind(keys, action, flags)
  hl.bind(keys, action, flags)
end

-- ── apps and shell ──
bind(M .. " + F1", exec("foot --app-id=keyhints keyhints"))
bind(M .. " + Return", exec("foot"))
bind(M .. " + D", global("caelestia:launcher"))
bind(M .. " + T", exec("pkill fuzzel || caelestia clipboard"))
bind(M .. " + N", global("caelestia:sidebar"))
bind(M .. " + ALT + S", global("caelestia:nexus"))
bind(M .. " + ALT + Escape", global("caelestia:session"))
bind("CTRL + ALT + Delete", global("caelestia:session"))
-- Never `loginctl lock-session` or caelestia:lock: Caelestia answers logind's
-- Lock signal with its own lock screen; this session locks with hyprlock (U2F).
bind(M .. " + ALT + L", exec("pidof hyprlock || hyprlock"))

-- ── media, volume, brightness ──
bind("XF86AudioRaiseVolume", exec("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 10%+"), locked_repeating)
bind("XF86AudioLowerVolume", exec("wpctl set-volume @DEFAULT_AUDIO_SINK@ 10%-"), locked_repeating)
bind("XF86AudioMute", exec("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), locked)
bind("XF86AudioMicMute", exec("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), locked)
bind("XF86MonBrightnessUp", global("caelestia:brightnessUp"), locked)
bind("XF86MonBrightnessDown", global("caelestia:brightnessDown"), locked)
bind("XF86AudioPlay", global("caelestia:mediaToggle"), locked)
bind("XF86AudioNext", global("caelestia:mediaNext"), locked)
bind("XF86AudioPrev", global("caelestia:mediaPrev"), locked)
bind("XF86AudioStop", global("caelestia:mediaStop"), locked)

bind(M .. " + Q", hl.dsp.window.close())

-- ── focus and move: arrows and hjkl ──
-- Focus moves between columns (left/right) and inside one (up/down); the
-- column moves swap whole columns; up/down move a window inside its column.
local directions = {
  { "Left", "H", "left", "l" },
  { "Down", "J", "down", "d" },
  { "Up", "K", "up", "u" },
  { "Right", "L", "right", "r" },
}
for _, d in ipairs(directions) do
  local horizontal = d[3] == "left" or d[3] == "right"
  for _, key in ipairs({ d[1], d[2] }) do
    bind(M .. " + " .. key, focus({ direction = d[3] }))
    bind(M .. " + CTRL + " .. key, horizontal and layout("swapcol " .. d[4]) or move({ direction = d[3] }))
    bind(M .. " + SHIFT + " .. key, focus({ monitor = d[4] }))
    bind(M .. " + SHIFT + CTRL + " .. key, move({ monitor = d[4] }))
  end
end

-- The view jumps to the first/last column; focus follows the centred column.
bind(M .. " + Home", layout("move -99999"))
bind(M .. " + End", layout("move +99999"))

-- ── workspaces ──
-- "r" steps through this monitor's workspaces, skipping those pinned to
-- another one (1-3 live on DP-2).
bind(M .. " + Page_Down", focus({ workspace = "r+1" }))
bind(M .. " + Page_Up", focus({ workspace = "r-1" }))
bind(M .. " + U", focus({ workspace = "r+1" }))
bind(M .. " + I", focus({ workspace = "r-1" }))
bind(M .. " + CTRL + Page_Down", move({ workspace = "r+1" }))
bind(M .. " + CTRL + Page_Up", move({ workspace = "r-1" }))
bind(M .. " + CTRL + U", move({ workspace = "r+1" }))
bind(M .. " + CTRL + I", move({ workspace = "r-1" }))

for i = 1, 9 do
  bind(M .. " + " .. i, focus({ workspace = i }))
  bind(M .. " + SHIFT + " .. i, move({ workspace = i }))
end

-- Not in niri: a scratch workspace, so that the bar's special workspaces
-- have something to show.
bind(M .. " + Z", hl.dsp.workspace.toggle_special("magic"))
bind(M .. " + SHIFT + Z", move({ workspace = "special:magic" }))

-- ── wheel (events are spaced by binds.scroll_event_delay) ──
bind(M .. " + mouse_down", focus({ workspace = "r+1" }))
bind(M .. " + mouse_up", focus({ workspace = "r-1" }))
bind(M .. " + CTRL + mouse_down", move({ workspace = "r+1" }))
bind(M .. " + CTRL + mouse_up", move({ workspace = "r-1" }))
bind(M .. " + mouse_right", focus({ direction = "right" }))
bind(M .. " + mouse_left", focus({ direction = "left" }))
bind(M .. " + SHIFT + mouse_down", focus({ direction = "right" }))
bind(M .. " + SHIFT + mouse_up", focus({ direction = "left" }))
bind(M .. " + CTRL + mouse_right", layout("swapcol r"))
bind(M .. " + CTRL + mouse_left", layout("swapcol l"))
bind(M .. " + CTRL + SHIFT + mouse_down", layout("swapcol r"))
bind(M .. " + CTRL + SHIFT + mouse_up", layout("swapcol l"))

-- ── columns ──
bind(M .. " + bracketleft", layout("consume_or_expel prev"))
bind(M .. " + bracketright", layout("consume_or_expel next"))
bind(M .. " + comma", layout("consume"))
bind(M .. " + period", layout("expel"))

bind(M .. " + R", layout("colresize +conf"))
bind(M .. " + F", hl.dsp.window.fullscreen({ mode = "maximized" }))
bind(M .. " + SHIFT + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
bind(M .. " + CTRL + F", layout("colresize 1.0"))
bind(M .. " + C", layout("center"))
bind(M .. " + CTRL + C", layout("fit visible"))

bind(M .. " + minus", layout("colresize -0.1"), repeating)
bind(M .. " + equal", layout("colresize +0.1"), repeating)
bind(M .. " + SHIFT + minus", hl.dsp.window.resize({ x = 0, y = -60, relative = true }), repeating)
bind(M .. " + SHIFT + equal", hl.dsp.window.resize({ x = 0, y = 60, relative = true }), repeating)

bind(M .. " + V", hl.dsp.window.float({ action = "toggle" }))
-- Floating <-> tiled focus.
bind(M .. " + SHIFT + V", function()
  local win = hl.get_active_window()
  if win and win.floating then
    hl.dispatch(hl.dsp.window.cycle_next({ tiled = true }))
  else
    hl.dispatch(hl.dsp.window.cycle_next({ floating = true }))
  end
end)
-- A group is the tabbed column.
bind(M .. " + W", hl.dsp.group.toggle())

-- ── screenshots ──
-- To ~/Pictures/Screenshots and the clipboard.
--   Mod+S              region (drag with slurp, Esc cancels)
--   Mod+Shift+S, Print the whole focused monitor
local shot = [[mkdir -p ~/Pictures/Screenshots; f=~/Pictures/Screenshots/"Screenshot from $(date '+%Y-%m-%d %H-%M-%S').png"; ]]
local region = shot .. [[g=$(slurp) && grim -g "$g" "$f" && wl-copy < "$f"]]
local output = shot .. [[o=$(hyprctl -j monitors | jq -r '.[] | select(.focused) | .name'); grim -o "$o" "$f" && wl-copy < "$f"]]
bind(M .. " + S", exec(region))
bind(M .. " + SHIFT + S", exec(output))
bind("Print", exec(output))

-- ── session ──
-- Mod+Escape hands every key to the focused window (remote desktop, VM) until
-- it is pressed again.
bind(M .. " + Escape", hl.dsp.submap("passthru"))
hl.define_submap("passthru", function()
  bind(M .. " + Escape", hl.dsp.submap("reset"))
end)

bind(M .. " + SHIFT + E", hl.dsp.exit())
bind(M .. " + SHIFT + P", hl.dsp.dpms({ action = "disable" }))
-- Blanks the laptop panel; disabling it would fight kanshi.
bind(M .. " + SHIFT + O", hl.dsp.dpms({ action = "toggle", monitor = "eDP-1" }))

-- ── mouse ──
bind(M .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
bind(M .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })
