let
  btrfsOptions = ["compress=zstd" "noatime"];
in {
  disko.devices.disk = {
    nvme = {
      type = "disk";
      device = "/dev/disk/by-id/nvme-SAMSUNG_MZVLQ512HALU-00000_S4Y4NX0RB01712";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            size = "1G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = ["umask=0077"];
            };
          };
          system = {
            size = "100%";
            content = {
              type = "btrfs";
              extraArgs = ["-L" "system"];
              mountpoint = "/mnt/pool";
              mountOptions = btrfsOptions;
              subvolumes = {
                "@root" = {
                  mountpoint = "/";
                  mountOptions = btrfsOptions;
                };
                "@nix" = {
                  mountpoint = "/nix";
                  mountOptions = btrfsOptions;
                };
                "@var-lib" = {
                  mountpoint = "/var/lib";
                  mountOptions = btrfsOptions;
                };
                "@home" = {
                  mountpoint = "/home";
                  mountOptions = btrfsOptions;
                };
                "@snapshots" = {};
              };
            };
          };
        };
      };
    };

    hdd = {
      type = "disk";
      device = "/dev/disk/by-id/ata-WDC_WD10EZEX-75WN4A1_WD-WCC6Y3FPZSLS";
      content = {
        type = "gpt";
        partitions.srv = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "xfs";
            extraArgs = ["-L" "srv"];
            mountpoint = "/srv";
            mountOptions = ["noatime" "nofail"];
          };
        };
      };
    };
  };
}
