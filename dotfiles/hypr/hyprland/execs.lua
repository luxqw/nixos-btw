-- Hyprland 0.56 starts no session target. Import what the user units need,
-- then start hyprland-session.target (home.nix): it pulls in graphical-session,
-- Caelestia, the polkit agent, the clipboard watchers and hypridle. Hyprland's
-- own import into the user manager is off (HYPRLAND_NO_SD_VARS, set system-wide
-- in configuration.nix), because it also unsets PATH and QT_QPA_PLATFORMTHEME
-- from the manager on exit, which the other sessions keep using.
hl.on("hyprland.start", function()
  hl.exec_cmd(
    "dbus-update-activation-environment --systemd DISPLAY HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY "
      .. "XDG_CURRENT_DESKTOP XDG_SESSION_TYPE QT_QPA_PLATFORMTHEME QT_PLUGIN_PATH PATH XDG_DATA_DIRS "
      .. "&& systemctl --user stop hyprland-session.target "
      .. "&& systemctl --user start hyprland-session.target"
  )
  -- Same theme as home.pointerCursor in home.nix.
  hl.exec_cmd("hyprctl setcursor Bibata-Modern-Classic 24")
end)

hl.on("hyprland.shutdown", function()
  hl.exec_cmd(
    "systemctl --user stop hyprland-session.target; "
      .. "systemctl --user unset-environment DISPLAY WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE XDG_CURRENT_DESKTOP"
  )
end)

-- Every reload re-applies the monitor rules, which undoes kanshi's 60 Hz on the
-- laptop panel while docked; let it apply its profile again.
hl.on("config.reloaded", function()
  hl.exec_cmd("systemctl --user try-restart kanshi.service")
end)
