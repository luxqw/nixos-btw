-- Hyprland 0.56 (Lua) config for the Caelestia session, beside Umbriel and niri.
-- Live dotfile (mkOutOfStoreSymlink, home.nix): edits reload without a rebuild;
-- check with `Hyprland --verify-config -c /etc/nixos/dotfiles/hypr/hyprland.lua`.
-- Caelestia writes scheme/current.lua here (gitignored).

require("hyprland.env")
require("hyprland.monitors")
require("hyprland.general")
require("hyprland.input")
require("hyprland.rules")
require("hyprland.binds")
require("hyprland.execs")
