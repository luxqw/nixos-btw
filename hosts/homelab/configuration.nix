{
  config,
  pkgs,
  ...
}: let
  domain = "rakhmatullin.dev";
  lan = "eno1";
  wgPort = 51820;

  secret = name: {file = ../../secrets/homelab + "/${name}.age";};

  proxy = port: {
    useACMEHost = domain;
    extraConfig = "reverse_proxy 127.0.0.1:${toString port}";
  };

  ports = {
    adguard = 3000;
    beszel = 8090;
    gatus = 8083;
    harmonia = 5000;
    homepage = 8082;
    scrutiny = 8081;
  };

  local = name: path: {
    inherit name;
    url = "http://127.0.0.1:${toString ports.${name}}${path}";
    interval = "1m";
    conditions = ["[STATUS] == 200"];
    alerts = [{type = "telegram";}];
  };
in {
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  hardware.enableRedistributableFirmware = true;

  services.fstrim.enable = true;

  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="block", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", RUN+="${pkgs.hdparm}/bin/hdparm -S 242 /dev/%k"
  '';

  networking.hostName = "homelab";
  networking.useNetworkd = true;
  networking.nftables.enable = true;
  services.resolved.settings.Resolve.DNSStubListener = false;
  networking.firewall = {
    trustedInterfaces = [lan "home"];
    allowedUDPPorts = [wgPort];
  };

  networking.wireguard.interfaces.home = {
    ips = ["10.100.0.1/24"];
    listenPort = wgPort;
    privateKeyFile = config.age.secrets.wg-home.path;
    peers = [
      {
        name = "legion";
        publicKey = "y/0sUdhUYig0pLS5UZnlfMea8ZXnDqh4w0CNKR0xjms=";
        allowedIPs = ["10.100.0.2/32"];
      }
      {
        name = "phone";
        publicKey = "57T2WBD4hSvjGoTKroM8OddmnuhatxTtokB8iFM86R4=";
        allowedIPs = ["10.100.0.3/32"];
      }
    ];
  };

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  users.mutableUsers = false;
  users.users.lux = {
    extraGroups = ["wheel"];
    hashedPasswordFile = config.age.secrets.lux-password.path;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE/1YvuBqo5bySoS2EczLFGNzx8ONDJqeibq6O8n4KiG lux@nixos"
    ];
  };

  age.secrets = {
    lux-password = secret "lux-password";
    wg-home = secret "wg-home";
    cloudflare = secret "cloudflare";
    telegram = secret "telegram";
    restic = secret "restic";
    harmonia = secret "harmonia";
    caddy-auth = secret "caddy-auth";
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "rakhmatullin.damir@tutamail.com";
    certs.${domain} = {
      domain = "*.${domain}";
      dnsProvider = "cloudflare";
      dnsResolver = "jacob.ns.cloudflare.com:53";
      environmentFile = config.age.secrets.cloudflare.path;
      group = config.services.caddy.group;
    };
  };

  services.caddy = {
    enable = true;
    environmentFile = config.age.secrets.caddy-auth.path;
    virtualHosts = {
      "home.${domain}" = proxy ports.homepage;
      "beszel.${domain}" = proxy ports.beszel;
      "status.${domain}" = proxy ports.gatus;
      "disks.${domain}" = proxy ports.scrutiny;
      "cache.${domain}" = proxy ports.harmonia;
      "adguard.${domain}" = {
        useACMEHost = domain;
        extraConfig = ''
          basic_auth {
            lux {$ADMIN_HASH}
          }
          reverse_proxy 127.0.0.1:${toString ports.adguard}
        '';
      };
    };
  };

  services.adguardhome = {
    enable = true;
    host = "127.0.0.1";
    port = ports.adguard;
    mutableSettings = false;
    settings = {
      dns = {
        bind_hosts = ["0.0.0.0"];
        upstream_dns = [
          "https://dns.quad9.net/dns-query"
          "https://cloudflare-dns.com/dns-query"
        ];
        bootstrap_dns = ["9.9.9.9" "1.1.1.1"];
      };
      filtering = {
        protection_enabled = true;
        filtering_enabled = true;
      };
      filters = [
        {
          enabled = true;
          id = 1;
          name = "AdGuard DNS filter";
          url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt";
        }
        {
          enabled = true;
          id = 2;
          name = "OISD";
          url = "https://big.oisd.nl";
        }
      ];
    };
  };

  services.beszel.hub = {
    enable = true;
    host = "127.0.0.1";
    port = ports.beszel;
  };

  services.beszel.agent = {
    enable = true;
    environment = {
      LISTEN = "127.0.0.1:45876";
      KEY = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDUNhE1OxJCE2//iu1V6ZhCqJspO2AN37nHQEWbrFLBa";
      EXTRA_FILESYSTEMS = "/srv";
    };
  };

  services.scrutiny = {
    enable = true;
    collector.enable = true;
    settings.web.listen = {
      host = "127.0.0.1";
      port = ports.scrutiny;
    };
  };

  services.gatus = {
    enable = true;
    environmentFile = config.age.secrets.telegram.path;
    settings = {
      web = {
        address = "127.0.0.1";
        port = ports.gatus;
      };
      alerting.telegram = {
        token = "\${TELEGRAM_TOKEN}";
        id = "\${TELEGRAM_CHAT_ID}";
        default-alert = {
          failure-threshold = 3;
          success-threshold = 2;
          send-on-resolved = true;
        };
      };
      endpoints = [
        (local "adguard" "/")
        (local "beszel" "/")
        (local "scrutiny" "/web/dashboard")
        (local "homepage" "/")
        (local "harmonia" "/nix-cache-info")
        {
          name = "dns";
          url = "127.0.0.1";
          interval = "1m";
          dns = {
            query-name = "nixos.org";
            query-type = "A";
          };
          conditions = ["[DNS_RCODE] == NOERROR"];
          alerts = [{type = "telegram";}];
        }
      ];
    };
  };

  services.homepage-dashboard = {
    enable = true;
    listenPort = ports.homepage;
    allowedHosts = "home.${domain}";
    widgets = [
      {
        resources = {
          cpu = true;
          memory = true;
          disk = ["/" "/srv"];
        };
      }
    ];
    services = [
      {
        "Сеть" = [
          {
            AdGuard = {
              href = "https://adguard.${domain}";
              icon = "adguard-home.svg";
              description = "DNS и блокировка рекламы";
            };
          }
        ];
      }
      {
        "Мониторинг" = [
          {
            Beszel = {
              href = "https://beszel.${domain}";
              icon = "beszel.svg";
              description = "Нагрузка на сервер";
            };
          }
          {
            Gatus = {
              href = "https://status.${domain}";
              icon = "gatus.svg";
              description = "Живы ли сервисы";
            };
          }
          {
            Scrutiny = {
              href = "https://disks.${domain}";
              icon = "scrutiny.svg";
              description = "Здоровье дисков";
            };
          }
        ];
      }
    ];
  };

  services.harmonia = {
    enable = true;
    signKeyPaths = [config.age.secrets.harmonia.path];
    settings.bind = "127.0.0.1:${toString ports.harmonia}";
  };

  services.btrbk.instances.local = {
    onCalendar = "hourly";
    settings = {
      snapshot_preserve_min = "2h";
      snapshot_preserve = "24h 7d";
      volume."/mnt/pool" = {
        snapshot_dir = "@snapshots";
        subvolume = "@var-lib";
      };
    };
  };

  services.restic.backups.local = {
    repository = "/srv/backup/restic";
    passwordFile = config.age.secrets.restic.path;
    initialize = true;
    paths = ["/var/lib"];
    exclude = ["/var/lib/systemd/coredump"];
    timerConfig = {
      OnCalendar = "03:00";
      Persistent = true;
    };
    pruneOpts = ["--keep-daily 7" "--keep-weekly 4" "--keep-monthly 6"];
  };

  system.stateVersion = "26.11";
}
