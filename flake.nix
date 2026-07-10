{
  description = "NixOS configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    zen-browser.url = "github:0xc000022070/zen-browser-flake";
    claude-code.url = "github:sadjow/claude-code-nix";
    noctalia-greeter.url = "github:noctalia-dev/noctalia-greeter";
    clin.url = "github:reekta92/clin-rs";
    torio.url = "github:y-tretyakov/torio";
    tele.url = "github:sorokin-vladimir/tele";
    creamlinux-installer = {
      type = "github";
      owner = "Novattz";
      repo = "creamlinux-installer";
      flake = false;
    };
    millennium.url = "github:SteamClientHomebrew/Millennium?dir=packages/nix";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-openclaw = {
      url = "github:openclaw/nix-openclaw";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    claude-code,
    home-manager,
    millennium,
    ...
  }: let
    shared = [
      ./nixos/modules
      ({pkgs, ...}: {
        nixpkgs.overlays = [
          claude-code.overlays.default
          inputs.millennium.overlays.default
          inputs.nix-openclaw.overlays.default
        ];

        environment.systemPackages = [pkgs.claude-code];
      })
      home-manager.nixosModules.home-manager
      {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.extraSpecialArgs = {inherit inputs;};
      }
    ];
  in {
    nixosConfigurations = {
      nixos = nixpkgs.lib.nixosSystem {
        specialArgs = {inherit inputs;};
        modules =
          shared
          ++ [
            ./hosts/nixos/configuration.nix
            {home-manager.users.lux = import ./home-manager/home.nix;}
          ];
      };
    };
  };
}
