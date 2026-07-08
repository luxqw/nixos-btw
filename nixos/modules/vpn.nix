{pkgs, ...}: {
  services.v2raya.enable = true;
  services.v2raya.cliPackage = pkgs.xray;

  services.zerotierone = {
    enable = true;
    joinNetworks = [
      "159924d630a2b0a0"
    ];
  };

  systemd.tmpfiles.rules = [
    "L /etc/wireguard - - - - /etc/nixos/wireguard"
  ];

  security.sudo.extraConfig = ''
    lux ALL=(root) NOPASSWD: /run/current-system/sw/bin/wg-quick
  '';
}
