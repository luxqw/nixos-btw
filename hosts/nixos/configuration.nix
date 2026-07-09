{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
  ];

  networking.hostName = "nixos";

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
    open = false;
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
    MOZ_ENABLE_WAYLAND = "1";
    __GL_SHADER_DISK_CACHE_SKIP_CLEANUP = "1";
  };

  environment.etc."niri-render-device.kdl".text = ''
    debug {
      render-drm-device "/dev/dri/renderD129"
      disable-direct-scanout
    }
  '';

  environment.etc."nvidia/nvidia-application-profiles-rc.d/50-niri-vram-fix.json".text = ''
    {
      "rules": [{"pattern": {"feature": "procname", "matches": "niri"}, "profile": "limit-free-buffer-pool"}],
      "profiles": [{"name": "limit-free-buffer-pool", "settings": [{"key": "GLVidHeapReuseRatio", "value": 0}]}]
    }
  '';

  specialisation = {
    on-the-go.configuration = {
      system.nixos.tags = ["on-the-go"];
      hardware.nvidia = {
        prime.offload.enable = lib.mkForce true;
        prime.offload.enableOffloadCmd = lib.mkForce true;
        powerManagement.finegrained = lib.mkForce true;
      };
      environment.etc."niri-render-device.kdl".text = lib.mkForce ''
        debug {
          render-drm-device "/dev/dri/renderD128"
        }
      '';
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

  system.stateVersion = "25.11";
}
