{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
  ];

  services.xserver.videoDrivers = ["amdgpu" "nvidia"];

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
    };
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.kernelPackages = pkgs.linuxPackages_latest;

  boot.kernelParams = ["nvidia_drm.fbdev=1"];

  networking.hostName = "nixos";

  networking.networkmanager.enable = true;

  time.timeZone = "Europe/Belgrade";

  i18n.defaultLocale = "en_US.UTF-8";

  services.xserver.enable = true;

  #services.xserver.displayManager.gdm.enable = true;
  #services.xserver.desktopManager.gnome.enable = true;
  services.displayManager.ly.enable = true;
  programs.niri.enable = true;
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  services.printing.enable = true;
  services.libinput.enable = true;

  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  users.users.lux = {
    isNormalUser = true;
    description = "Lux";
    extraGroups = ["networkmanager" "wheel" "docker"];
    packages = with pkgs; [
      tree
      vis
      git
      foot
      alacritty
      fuzzel
      neovim
      gcc
      lua-language-server
      nil
      alejandra
      vim
      wget
      adwaita-icon-theme
      gnome-themes-extra
      nitch
      thunar
      rofi
      swaybg
      swaylock
      telegram-desktop
    ];
  };

  programs.gamemode.enable = true;

  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
  };

  nix.settings = {
    experimental-features = ["nix-command" "flakes"];
    download-buffer-size = 268435456;
    trusted-users = ["root" "lux"];
    extra-substituters = ["https://hyprland.cachix.org"];
    extra-trusted-public-keys = ["hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="];
  };

  nixpkgs.config.allowUnfree = true;

  hardware.bluetooth.enable = true;

  services.power-profiles-daemon.enable = true;

  services.upower.enable = true;

  virtualisation.docker.enable = true;

  environment.systemPackages = with pkgs; [
    inputs.zen-browser.packages."${pkgs.stdenv.hostPlatform.system}".default
    protonup-qt
    ntfs3g
  ];

  fileSystems."/run/media/gamedisk" = {
    device = "/dev/disk/by-label/Games";
    fsType = "ntfs";
    options = ["nofail" "x-gvfs-show" "uid=1000" "gid=1000" "umask=000" "exec"];
  };

  fonts.packages = with pkgs; [
    nerd-fonts.iosevka
  ];

  system.stateVersion = "25.11";
}
