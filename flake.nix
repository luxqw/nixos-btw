{
  description = "Nix Hyprland Lua, btw.";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    hyprland.url = "github:hyprwm/Hyprland/v0.55.0";
    zen-browser.url = "github:0xc000022070/zen-browser-flake";
  };
  outputs = inputs @ {
    self,
    nixpkgs,
    hyprland,
    zen-browser,
    ...
  }: {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {inherit inputs;};
      modules = [
        ./configuration.nix
        ./hardware-configuration.nix
      ];
    };
  };
}
