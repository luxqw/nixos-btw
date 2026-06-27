# nixos-btw

My NixOS configuration. AMD + NVIDIA hybrid laptop, niri compositor, external ultrawide.

## Structure

```
├── flake.nix               # inputs: nixpkgs-unstable, home-manager, zen-browser, noctalia
├── configuration.nix       # system: NVIDIA PRIME, pipewire, steam, docker, wg-easy
├── home.nix                # user: packages, git, bash aliases, gtk
├── niri/config.kdl         # niri compositor config
├── foot/foot.ini           # terminal (TokyoNight)
└── hyprland/               # standalone Hyprland flake
    ├── flake.nix
    ├── configuration.nix
    ├── home.nix
    └── hypr/               # hyprland.lua, hyprlock, hypridle, hyprpaper
```

## Usage

```bash
rebuild           # niri setup
rebuild-hypr      # hyprland setup (first run: cd hyprland && nix flake update)
```

## Hardware

- GPU: AMD iGPU (eDP-1 internal) + NVIDIA dGPU (DP-2 external)
- Monitors: 3440×1440@165 ultrawide + 2560×1600@165 laptop
- Boot into `[docked]` specialisation when external monitor is connected
