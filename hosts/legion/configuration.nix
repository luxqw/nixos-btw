{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  system = pkgs.stdenv.hostPlatform.system;

  agenixPackage = inputs.agenix.packages.${system}.default;

  tunnelSecretsDir = ../../secrets/wg;

  tunnelNames =
    map (lib.removeSuffix ".age")
    (builtins.attrNames
      (lib.filterAttrs
        (name: type: type == "regular" && lib.hasSuffix ".age" name)
        (builtins.readDir tunnelSecretsDir)));

  tunnelUnits = map (name: "wg-quick-${name}.service") tunnelNames;

  manualTunnels = ["home"];

  tunnelCli = pkgs.writeShellApplication {
    name = "tunnel";
    runtimeInputs = [pkgs.age agenixPackage pkgs.systemd];
    text = ''
      set -euo pipefail

      dir=/etc/nixos/secrets
      key="$HOME/.ssh/id_ed25519"

      usage() {
        cat <<'USAGE'
      tunnel — manage wireguard tunnels

        tunnel list                 list tunnels and their state
        tunnel up <name>            bring a tunnel up
        tunnel down <name>          take a tunnel down
        tunnel restart <name>       restart a tunnel
        tunnel add <name> <config>  encrypt a new config
        tunnel edit <name>          open an existing one in $EDITOR
        tunnel show <name>          print the decrypted config
        tunnel rm <name>            remove a tunnel

      up, down and restart need no password — see the polkit rule in
      configuration.nix. Tunnels also start on their own at boot.

      add, edit and rm need a rebuild afterwards:
        sudo nixos-rebuild switch --flake /etc/nixos
      USAGE
      }

      require_tunnel() {
        [ -n "''${1-}" ] || { echo "usage: tunnel $2 <name>" >&2; exit 1; }
        [ -e "$dir/wg/$1.age" ] || { echo "no such tunnel: $1" >&2; exit 1; }
      }

      case "''${1-}" in
        list)
          for f in "$dir"/wg/*.age; do
            [ -e "$f" ] || continue
            n=$(basename "$f" .age)
            printf '%-16s %s\n' "$n" "$(systemctl is-active "wg-quick-$n" 2>&1)"
          done
          ;;

        up|down|restart)
          verb=$1
          require_tunnel "''${2-}" "$verb"
          case "$verb" in
            up) systemctl start "wg-quick-$2" ;;
            down) systemctl stop "wg-quick-$2" ;;
            restart) systemctl restart "wg-quick-$2" ;;
          esac
          printf '%-16s %s\n' "$2" "$(systemctl is-active "wg-quick-$2" 2>&1)"
          ;;

        add)
          [ $# -eq 3 ] || { echo "usage: tunnel add <name> <config>" >&2; exit 1; }
          name=$2
          [ ''${#name} -le 15 ] || { echo "name longer than 15 characters — not a valid interface name" >&2; exit 1; }
          [ ! -e "$dir/wg/$name.age" ] || { echo "tunnel $name already exists — use tunnel edit" >&2; exit 1; }
          [ -f "$3" ] || { echo "no such file: $3" >&2; exit 1; }
          age -R "$key.pub" -o "$dir/wg/$name.age" "$3"
          echo "created $dir/wg/$name.age"
          echo "next: sudo nixos-rebuild switch --flake /etc/nixos"
          ;;

        edit)
          [ $# -eq 2 ] || { echo "usage: tunnel edit <name>" >&2; exit 1; }
          [ -e "$dir/wg/$2.age" ] || { echo "no such tunnel: $2" >&2; exit 1; }
          (cd "$dir" && RULES=./secrets.nix agenix -e "wg/$2.age" -i "$key")
          echo "next: sudo nixos-rebuild switch --flake /etc/nixos && systemctl restart wg-quick-$2"
          ;;

        show)
          [ $# -eq 2 ] || { echo "usage: tunnel show <name>" >&2; exit 1; }
          [ -e "$dir/wg/$2.age" ] || { echo "no such tunnel: $2" >&2; exit 1; }
          (cd "$dir" && RULES=./secrets.nix agenix -d "wg/$2.age" -i "$key")
          ;;

        rm)
          [ $# -eq 2 ] || { echo "usage: tunnel rm <name>" >&2; exit 1; }
          [ -e "$dir/wg/$2.age" ] || { echo "no such tunnel: $2" >&2; exit 1; }
          rm "$dir/wg/$2.age"
          echo "removed $2; next: sudo nixos-rebuild switch --flake /etc/nixos"
          ;;

        *)
          usage
          [ -z "''${1-}" ] && exit 0 || exit 1
          ;;
      esac
    '';
  };
in {
  imports = [
    inputs.noctalia-greeter.nixosModules.default
    inputs.umbriel.nixosModules.default
    ./hardware-configuration.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 10;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;

  boot.extraModulePackages = with config.boot.kernelPackages; [
    v4l2loopback
  ];

  boot.kernelModules = [
    "xt_TPROXY"
    "xt_socket"
    "xt_mark"
    "iptable_mangle"
    "nf_tproxy_ipv4"
    "v4l2loopback"
    "nvidia"
    "nvidia_modeset"
    "nvidia_drm"
  ];

  boot.extraModprobeConfig = ''
    options v4l2loopback devices=1 video_nr=10 card_label="OBS Cam" exclusive_caps=1

    options nvidia_modeset vblank_sem_control=0

    options rtw89_pci disable_aspm_l1=y disable_aspm_l1ss=y disable_clkreq=y
    options rtw89_core disable_ps_mode=y
  '';

  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  hardware.bluetooth.enable = true;

  users.groups.lenovoctl = {};

  systemd.tmpfiles.rules = [
    "z /sys/bus/platform/drivers/ideapad_acpi/*/conservation_mode 0664 root lenovoctl - -"
  ];

  services.printing.enable = true;
  services.udisks2.enable = true;
  services.gvfs.enable = true;
  services.libinput.enable = true;

  services.power-profiles-daemon.enable = true;
  services.upower.enable = true;

  services.logind.settings.Login.HandlePowerKey = "ignore";

  services.xserver.videoDrivers = ["amdgpu" "nvidia"];

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      nvidia-vaapi-driver
    ];
  };

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = true;
    powerManagement.finegrained = false;
    open = true;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  hardware.nvidia.prime = {
    nvidiaBusId = "PCI:1:0:0";
    amdgpuBusId = "PCI:6:0:0";
  };

  environment.sessionVariables = {
    GBM_BACKEND = "nvidia-drm";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    LIBVA_DRIVER_NAME = "nvidia";
    NVD_BACKEND = "direct";
    ELECTRON_OZONE_PLATFORM_HINT = "auto";
    NIXOS_OZONE_WL = "1";
    MOZ_ENABLE_WAYLAND = "1";
    __GL_SHADER_DISK_CACHE_SKIP_CLEANUP = "1";
  };

  specialisation = {
    on-the-go.configuration = {
      system.nixos.tags = ["on-the-go"];
      hardware.nvidia = {
        prime.offload.enable = lib.mkForce true;
        prime.offload.enableOffloadCmd = lib.mkForce true;
        powerManagement.finegrained = lib.mkForce true;
      };
      environment.sessionVariables = lib.mkForce {
        LIBVA_DRIVER_NAME = "radeonsi";
        ELECTRON_OZONE_PLATFORM_HINT = "auto";
        MOZ_ENABLE_WAYLAND = "1";
      };
    };
  };

  fileSystems."/run/media/gamedisk" = {
    device = "/dev/disk/by-label/Games";
    fsType = "ntfs";
    options = ["nofail" "x-gvfs-show" "uid=1000" "gid=1000" "umask=000" "exec"];
  };

  networking.hostName = "legion";
  networking.networkmanager.enable = true;

  services.zerotierone = {
    enable = true;
    joinNetworks = [
      "159924d630a2b0a0"
    ];
  };

  services.v2raya = {
    enable = true;
    cliPackage = pkgs.xray;
  };

  programs.throne = {
    enable = true;
    tunMode.enable = true;
  };

  networking.wg-quick.interfaces = lib.genAttrs tunnelNames (name: {
    configFile = config.age.secrets.${name}.path;
    autostart = !(builtins.elem name manualTunnels);
  });

  nix.distributedBuilds = true;
  nix.buildMachines = [
    {
      hostName = "homelab.rakhmatullin.dev";
      sshUser = "lux";
      sshKey = "/home/lux/.ssh/id_ed25519";
      protocol = "ssh-ng";
      system = "x86_64-linux";
      maxJobs = 6;
      speedFactor = 2;
      supportedFeatures = ["nixos-test" "benchmark" "big-parallel" "kvm"];
    }
  ];

  nix.settings = {
    builders-use-substitutes = true;
    connect-timeout = 3;
    extra-substituters = ["https://cache.rakhmatullin.dev"];
    extra-trusted-public-keys = ["cache.rakhmatullin.dev-1:ysIIVJpZZyE3gdeJ542ooRjC6iYqkbawCN93gpSsek4="];
  };

  programs.ssh.knownHosts.homelab = {
    hostNames = ["homelab.rakhmatullin.dev" "192.168.1.10" "10.100.0.1"];
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIItAd+Zf3tM9hJbLr+QnBLmcJWB0JFzw9Al8zWLvzepq";
  };

  programs.ssh.extraConfig = ''
    Host homelab homelab.rakhmatullin.dev
      HostName homelab.rakhmatullin.dev
      User lux
      ConnectTimeout 3
  '';

  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      var units = ${builtins.toJSON tunnelUnits};
      if (action.id == "org.freedesktop.systemd1.manage-units" &&
          units.indexOf(action.lookup("unit")) >= 0 &&
          ["start", "stop", "restart"].indexOf(action.lookup("verb")) >= 0 &&
          subject.user == "lux") {
        return polkit.Result.YES;
      }
    });
  '';

  age.identityPaths = ["/home/lux/.ssh/id_ed25519"];

  age.secrets =
    lib.genAttrs tunnelNames (name: {
      file = tunnelSecretsDir + "/${name}.age";
    })
    // lib.genAttrs ["syncthing-cert" "syncthing-key"] (name: {
      file = ../../secrets/legion + "/${name}.age";
      owner = "lux";
    });

  services.syncthing = {
    enable = true;
    user = "lux";
    group = "users";
    dataDir = "/home/lux";
    configDir = "/home/lux/.config/syncthing";
    cert = config.age.secrets.syncthing-cert.path;
    key = config.age.secrets.syncthing-key.path;
    settings = {
      options = {
        globalAnnounceEnabled = false;
        relaysEnabled = false;
        natEnabled = false;
        urAccepted = -1;
      };
      devices.homelab = {
        id = "L53YR5L-AMCVGBF-JGDVO4Y-P5DRG3F-H2SVGI6-6X4SVM5-FKX5KOD-VTB2LA4";
        addresses = ["tcp://192.168.1.10:22000"];
      };
      folders = {
        documents = {
          path = "/home/lux/Documents";
          devices = ["homelab"];
          ignorePatterns = map (dir: "(?d)${dir}") [
            ".cache"
            ".direnv"
            ".gradle"
            ".venv"
            ".zig-cache"
            "__pycache__"
            "build"
            "dist"
            "node_modules"
            "result"
            "target"
          ];
        };
        downloads = {
          path = "/home/lux/Downloads";
          devices = ["homelab"];
        };
      };
    };
  };

  systemd.services.photos-backup = {
    description = "Copy homelab's photo backup repository";
    path = [pkgs.rsync pkgs.openssh];
    serviceConfig = {
      Type = "oneshot";
      User = "lux";
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p /home/lux/Backups/photos";
      ExecStart = "${pkgs.rsync}/bin/rsync -a lux@192.168.1.10:/var/backup/photos/ /home/lux/Backups/photos/";
    };
  };
  systemd.timers.photos-backup = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "weekly";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };

  fileSystems."/mnt/media" = {
    device = "192.168.1.10:/srv/media";
    fsType = "nfs";
    options = [
      "nfsvers=4.2"
      "noauto"
      "x-systemd.automount"
      "x-systemd.idle-timeout=600"
      "x-systemd.mount-timeout=10"
      "soft"
      "timeo=50"
      "retrans=2"
    ];
  };

  programs.umbriel.enable = true;

  services.displayManager.noctalia-greeter = {
    enable = true;
    package = inputs.noctalia-greeter.packages.${system}.default;

    greeter-args = "";
    settings = {
      cursor = {
        theme = "Bibata-Modern-Classic";
        size = 24;
      };
      keyboard = {
        layout = "us";
      };
    };
  };

  fonts.packages = with pkgs; [
    nerd-fonts.iosevka
    (iosevka-bin.override {variant = "Aile";})
    (iosevka-bin.override {variant = "Etoile";})
    noto-fonts-color-emoji
  ];

  fonts.fontconfig.defaultFonts = {
    sansSerif = ["Iosevka Aile"];
    serif = ["Iosevka Etoile"];
    monospace = ["Iosevka Nerd Font Mono"];
    emoji = ["Noto Color Emoji"];
  };

  virtualisation.docker.enable = true;

  services.jellyfin = {
    enable = true;
    openFirewall = true;
    user = "lux";
  };

  programs.gamemode.enable = true;
  programs.gamescope.enable = true;

  programs.steam = {
    enable = true;
    package = inputs.millennium.packages.${system}.millennium-steam;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
  };

  programs.wireshark = {
    enable = true;
    package = pkgs.wireshark;
  };

  environment.systemPackages = [
    pkgs.bibata-cursors
    pkgs.nix-output-monitor
    pkgs.nixd

    pkgs.age
    agenixPackage
    pkgs.wireguard-tools
    tunnelCli

    inputs.noctalia.packages.${system}.default
    pkgs.polkit_gnome

    pkgs.ntfs3g
    pkgs.neovim-unwrapped
    pkgs.claude-code
  ];

  programs.nh.flake = "/etc/nixos";

  nixpkgs.overlays = [inputs.claude-code.overlays.default];

  users.users.lux = {
    extraGroups = ["networkmanager" "wheel" "docker" "input" "lenovoctl" "wireshark"];
    linger = true;
  };

  system.stateVersion = "25.11";
}
