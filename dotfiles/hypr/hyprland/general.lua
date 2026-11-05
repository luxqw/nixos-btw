local theme = require("hyprland.theme")
local scheme = theme.scheme()

hl.config({
  general = {
    layout = "scrolling",
    gaps_in = 3,
    gaps_out = 5,
    border_size = 2,
    allow_tearing = false,
    col = {
      active_border = "rgba(" .. scheme.primary .. "e6)",
      inactive_border = "rgba(" .. scheme.onSurfaceVariant .. "11)",
    },
  },

  -- Columns like niri: half the screen by default, 1/3 - 1/2 - 2/3 on Mod+R.
  scrolling = {
    fullscreen_on_one_column = true,
    column_width = 0.5,
    explicit_column_widths = "0.33333, 0.5, 0.66667",
    follow_focus = true,
    focus_fit_method = 1,
  },

  decoration = {
    rounding = 8,
    blur = {
      enabled = true,
      size = 6,
      passes = 2,
      new_optimizations = true,
    },
    shadow = {
      enabled = true,
      range = 12,
      render_power = 3,
      color = "rgba(" .. scheme.inversePrimary .. "10)",
    },
  },

  misc = {
    disable_hyprland_logo = true,
    force_default_wallpaper = 0,
    background_color = "rgb(" .. scheme.surfaceContainer .. ")",
    focus_on_activate = true,
    -- Power-off-monitors (Mod+Shift+P) wakes on any key or mouse move.
    key_press_enables_dpms = true,
    mouse_move_enables_dpms = true,
    allow_session_lock_restore = true,
  },

  -- A wheel notch is several events; niri waits 150 ms between workspace steps.
  binds = {
    scroll_event_delay = 150,
  },
})
