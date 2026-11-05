-- Mod+Space switches us/ru through xkb, as under Umbriel and niri.
hl.config({
  input = {
    kb_layout = "us,ru",
    kb_options = "grp:win_space_toggle",
    repeat_delay = 200,
    repeat_rate = 35,
    numlock_by_default = true,
    follow_mouse = 1,
    touchpad = {
      natural_scroll = true,
      tap_to_click = true,
    },
  },
})
