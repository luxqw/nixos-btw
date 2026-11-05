-- Same layout as Umbriel and niri. kanshi owns the outputs at runtime (it drops
-- the laptop panel to 60 Hz when docked); these rules are the starting point and
-- are applied again on every config reload, where kanshi is told to redo its
-- profile (execs.lua).
hl.monitor({
  output = "DP-2",
  mode = "3440x1440@165",
  position = "0x0",
  scale = 1,
  -- Fullscreen only: "always" flickers on this VA panel on the desktop.
  vrr = 2,
})

hl.monitor({
  output = "eDP-1",
  mode = "2560x1600@165",
  position = "3440x0",
  scale = 1.5,
})

hl.monitor({ output = "HDMI-A-1", disabled = true })

-- Pinned to the ultrawide like Umbriel's workspaces 1-3.
for i = 1, 3 do
  hl.workspace_rule({ workspace = tostring(i), monitor = "DP-2", default = i == 1 })
end
