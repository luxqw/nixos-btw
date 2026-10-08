{
  description = "NixOS configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    zen-browser.url = "github:0xc000022070/zen-browser-flake";
    claude-code.url = "github:sadjow/claude-code-nix";
    noctalia-greeter.url = "github:noctalia-dev/noctalia-greeter";
    clin.url = "github:reekta92/clin-rs";
    creamlinux-installer = {
      type = "github";
      owner = "Novattz";
      repo = "creamlinux-installer";
      flake = false;
    };
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    millennium.url = "github:SteamClientHomebrew/Millennium?dir=packages/nix";
    umbriel = {
      url = "github:noctalia-dev/umbriel";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pumpkin = {
      url = "git+https://github.com/Pumpkin-MC/Pumpkin?shallow=1&submodules=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    elyprismlauncher = {
      url = "github:ElyPrismLauncher/ElyPrismLauncher";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    anicli-ru = {
      url = "github:luxqw/ani-cli-ru/nix-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    nixpkgs,
    agenix,
    home-manager,
    disko,
    ...
  }: let
    host = name: modules:
      nixpkgs.lib.nixosSystem {
        specialArgs = {inherit inputs;};
        modules =
          [
            ./hosts/${name}/configuration.nix
            ./modules/common.nix
            agenix.nixosModules.default
          ]
          ++ modules;
      };
  in {
    nixosConfigurations.legion = host "legion" [
      home-manager.nixosModules.home-manager
      {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.extraSpecialArgs = {inherit inputs;};
        home-manager.users.lux = import ./hosts/legion/home.nix;
      }
    ];

    nixosConfigurations.homelab = host "homelab" [
      disko.nixosModules.disko
    ];
  };
}
