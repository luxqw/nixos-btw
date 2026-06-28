{
  description = "NixOS configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    zen-browser.url = "github:0xc000022070/zen-browser-flake";
    claude-code.url = "github:sadjow/claude-code-nix";
    noctalia-greeter.url = "github:noctalia-dev/noctalia-greeter";
    millennium.url = "github:SteamClientHomebrew/Millennium?dir=packages/nix";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
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
      ./configuration.nix
      ({pkgs, ...}: {
        nixpkgs.overlays = [
          claude-code.overlays.default
          inputs.millennium.overlays.default
        ];

        environment.systemPackages = [pkgs.claude-code];
      })
      home-manager.nixosModules.home-manager
      {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.backupFileExtension = "backup";
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
            ./noctalia.nix
            {home-manager.users.lux = import ./home.nix;}
          ];
      };

    };
  };
}
