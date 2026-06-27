{ config, pkgs, inputs, ... }: {
  imports = [ ./home.nix ];

  home.packages = with pkgs; [ swaybg ];

  xdg.configFile = {
    "hypr/hyprland.lua".source = ./hyprland/hypr/hyprland.lua;
    "hypr/hl.meta.lua".source  = ./hyprland/hypr/hl.meta.lua;
    "hypr/.luarc.json".source  = ./hyprland/hypr/.luarc.json;
  };
}
