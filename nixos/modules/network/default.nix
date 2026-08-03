{...}: {
  imports = [
    ./networkmanager.nix
    ./overlay.nix
    ./proxy.nix
    ./tunnel-cli.nix
    ./tunnels.nix
  ];
}
