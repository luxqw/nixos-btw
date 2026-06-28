# nixos-btw

NixOS configuration. AMD + NVIDIA hybrid laptop, niri compositor, external ultrawide, noctalia shell.

## Structure

```
├── flake.nix                  # inputs: nixpkgs-unstable, home-manager, zen-browser, noctalia, millennium
├── configuration.nix          # system: NVIDIA PRIME, pipewire, steam, docker, wireguard
├── noctalia.nix               # installs noctalia-shell package
├── home.nix                   # user: packages, git, bash aliases, gtk, foot
├── niri/
│   ├── config.kdl             # niri compositor config
│   └── noctalia.kdl           # noctalia color overrides for niri
└── foot/
    └── themes/noctalia        # noctalia foot color theme
```

## Usage

```bash
rebuild    # nixos-rebuild switch --flake /etc/nixos#nixos
edit       # nvim /etc/nixos/
```

## Hardware

- GPU: AMD iGPU (eDP-1 internal) + NVIDIA dGPU (DP-2 external)
- Monitors: 3440×1440@165 ultrawide (DP-2) + 2560×1600@60 laptop (eDP-1)
- NVIDIA PRIME offload by default; boot `[docked]` specialisation when external monitor is connected for PRIME sync
