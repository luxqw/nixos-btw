{
  description = "NixOS configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    zen-browser.url = "github:0xc000022070/zen-browser-flake";
    claude-code.url = "github:sadjow/claude-code-nix";
    clin.url = "github:reekta92/clin-rs";
    creamlinux-installer = {
      type = "github";
      owner = "Novattz";
      repo = "creamlinux-installer";
      flake = false;
    };
    dux-shell = {
      url = "github:duxlabs-dev/dux-shell/v2.1.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    dux-greeter = {
      url = "github:duxlabs-dev/dux-greeter/v2.1.0";
      inputs.nixpkgs.follows = "nixpkgs";
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
    pumpkin = {
      url = "git+https://github.com/Pumpkin-MC/Pumpkin?shallow=1&submodules=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    elyprismlauncher = {
      url = "github:ElyPrismLauncher/ElyPrismLauncher";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    t3-code-nix = {
      url = "github:LisaScheers/t3-code-nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
    # Own nixpkgs pin on purpose: fastmcp is broken in this flake's revision.
    dispatcher.url = "git+ssh://lux@homelab.rakhmatullin.dev/home/lux/repos/dispatcher.git?ref=main";
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
    formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.alejandra;

    nixosConfigurations.legion = host "legion" [
      home-manager.nixosModules.home-manager
      {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.extraSpecialArgs = {inherit inputs;};
        home-manager.users.lux = import ./hosts/legion/home.nix;
      }
      ./hosts/legion/niri-git.nix
    ];

    nixosConfigurations.homelab = host "homelab" [
      disko.nixosModules.disko
    ];
  };
}
