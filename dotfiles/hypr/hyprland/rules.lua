-- Mod+F1 cheat sheet.
hl.window_rule({
  name = "keyhints",
  match = { class = "^keyhints$" },
  float = true,
  size = "monitor_w*0.6 monitor_h*0.7",
  center = true,
})

-- Ignore maximize requests from apps (from the stock config).
hl.window_rule({
  name = "suppress-maximize-events",
  match = { class = ".*" },
  suppress_event = "maximize",
})

-- Fix some dragging issues with XWayland (from the stock config).
hl.window_rule({
  name = "fix-xwayland-drags",
  match = {
    class = "^$",
    title = "^$",
    xwayland = true,
    float = true,
    fullscreen = false,
    pin = false,
  },
  no_focus = true,
})
