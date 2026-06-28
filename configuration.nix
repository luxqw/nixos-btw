{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    inputs.noctalia-greeter.nixosModules.default
  ];

  services.xserver.videoDrivers = ["amdgpu" "nvidia"];

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = true;
    powerManagement.finegrained = true;
    open = false;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  hardware.nvidia.prime = {
    offload = {
      enable = true;
      enableOffloadCmd = true;
    };
    nvidiaBusId = "PCI:1:0:0";
    amdgpuBusId = "PCI:6:0:0";
  };

  specialisation = {
    docked.configuration = {
      system.nixos.tags = ["docked"];
      hardware.nvidia = {
        prime = {
          sync.enable = lib.mkForce true;
          offload.enable = lib.mkForce false;
          offload.enableOffloadCmd = lib.mkForce false;
        };
        powerManagement.finegrained = lib.mkForce false;
      };
      environment.sessionVariables = {
        GBM_BACKEND = "nvidia-drm";
        __GLX_VENDOR_LIBRARY_NAME = "nvidia";
      };
    };
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.kernelModules = ["xt_TPROXY" "xt_socket" "xt_mark" "iptable_mangle" "nf_tproxy_ipv4"];

  networking.hostName = "nixos";
  networking.networkmanager.enable = true;

  time.timeZone = "Europe/Belgrade";
  i18n.defaultLocale = "en_US.UTF-8";

  services.xserver.enable = true;
  #services.displayManager.ly.enable = true;
  programs.niri.enable = true;

  programs.noctalia-greeter = {
    enable = true;
    package = inputs.noctalia-greeter.packages.${pkgs.stdenv.hostPlatform.system}.default;

    greeter-args = "";
    settings = {
      cursor = {
        theme = "Adwaita";
        size = 24;
      };
      keyboard = {
        layout = "us";
      };
    };
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
  nix.settings = {
    auto-optimise-store = true;
    experimental-features = ["nix-command" "flakes"];
    download-buffer-size = 268435456;
    trusted-users = ["root" "lux"];
  };

  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  services.printing.enable = true;
  services.libinput.enable = true;

  services.v2raya.enable = true;
  services.v2raya.cliPackage = pkgs.xray;

  hardware.bluetooth.enable = true;
  services.power-profiles-daemon.enable = true;
  services.upower.enable = true;

  virtualisation.docker.enable = true;

  systemd.tmpfiles.rules = [
    "L /etc/wireguard - - - - /etc/nixos/wireguard"
  ];

  security.sudo.extraConfig = ''
    lux ALL=(root) NOPASSWD: /run/current-system/sw/bin/wg-quick
  '';

  programs.gamemode.enable = true;
  programs.steam = {
    enable = true;
    package = pkgs.millennium-steam;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
  };

  users.users.lux = {
    isNormalUser = true;
    description = "Lux";
    extraGroups = ["networkmanager" "wheel" "docker"];
    packages = with pkgs; [
      tree
      foot
      neovim
      gcc
      lua-language-server
      nil
      alejandra
      adwaita-icon-theme
      gnome-themes-extra
      nitch
      thunar
      rofi
    ];
  };

  environment.systemPackages = with pkgs; [
    inputs.zen-browser.packages."${pkgs.stdenv.hostPlatform.system}".default
    ntfs3g
    wireguard-tools
    xwayland-satellite
  ];

  fileSystems."/run/media/gamedisk" = {
    device = "/dev/disk/by-label/Games";
    fsType = "ntfs";
    options = ["nofail" "x-gvfs-show" "uid=1000" "gid=1000" "umask=000" "exec"];
  };

  fonts.packages = with pkgs; [
    nerd-fonts.iosevka
  ];

  nixpkgs.config.allowUnfree = true;

  system.stateVersion = "25.11";
}
