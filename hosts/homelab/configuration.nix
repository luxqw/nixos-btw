{
  config,
  lib,
  pkgs,
  inputs,
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

  guarded = port: {
    useACMEHost = domain;
    extraConfig = ''
      basic_auth {
        lux {$ADMIN_HASH}
      }
      reverse_proxy 127.0.0.1:${toString port}
    '';
  };

  ports = {
    adguard = 3000;
    beszel = 8090;
    flaresolverr = 8191;
    gatus = 8083;
    harmonia = 5000;
    homepage = 8082;
    immich = 2283;
    jackett = 9117;
    jellyfin = 8096;
    opencloud = 9200;
    qbittorrent = 8080;
    scrutiny = 8081;
    syncthing = 8384;
    torrserver = 8091;
    vaultwarden = 8222;
  };

  media = "/srv/media";
  photos = "/srv/photos";
  cloud = "/srv/cloud";
  photosRepo = "/var/backup/photos";

  pumpkin = {
    port = 41565;
    hostAddress = "10.233.1.1";
    localAddress = "10.233.1.2";
  };

  abcdeConf = pkgs.writeText "abcde.conf" (lib.concatLines [
    "CDDBMETHOD=musicbrainz"
    "OUTPUTTYPE=flac"
    "OUTPUTDIR=${media}/music"
    "WAVOUTPUTDIR=${media}/.disc"
    "OUTPUTFORMAT='\${ARTISTFILE}/\${ALBUMFILE}/\${TRACKNUM} - \${TRACKFILE}'"
    "VAOUTPUTFORMAT='Various/\${ALBUMFILE}/\${TRACKNUM} - \${ARTISTFILE} - \${TRACKFILE}'"
    "PADTRACKS=y"
    "INTERACTIVE=n"
  ]);

  disc = pkgs.writeShellApplication {
    name = "disc";
    runtimeInputs = with pkgs; [
      abcde
      cdrkit
      coreutils
      curl
      dvdauthor
      dvdbackup
      ffmpeg
      findutils
      gnugrep
      gnused
      handbrake
      systemd
      util-linux
      xorriso
    ];
    runtimeEnv = {
      MEDIA = media;
      BURN_ROOT = "${cloud}/projects/burn";
      ABCDE_CONF = abcdeConf;
      TELEGRAM_ENV = config.age.secrets.telegram.path;
    };
    text = builtins.readFile ./disc.sh;
  };

  jackettIndexers = pkgs.writeShellApplication {
    name = "jackett-indexers";
    runtimeInputs = [pkgs.curl pkgs.jq];
    text = ''
      api=http://127.0.0.1:${toString ports.jackett}
      dir=${config.services.jackett.dataDir}/Indexers
      jar=$(mktemp)
      trap 'rm -f "$jar"' EXIT

      curl -sf -c "$jar" -b "$jar" -L -o /dev/null "$api/UI/Login"

      configure() {
        local id=$1 patch=$2
        [ -e "$dir/$id.json" ] && return 0
        curl -sf -b "$jar" "$api/api/v2.0/indexers/$id/config" \
          | jq -c "$patch" \
          | curl -sf -b "$jar" -H 'Content-Type: application/json' \
              --data @- "$api/api/v2.0/indexers/$id/config"
        echo "configured $id"
      }

      configure rutor .
      configure noname-club .
      configure rutracker '
        map(if .id == "username" then .value = env.RUTRACKER_USERNAME
            elif .id == "password" then .value = env.RUTRACKER_PASSWORD
            elif .id == "striprussianletters" then .value = false
            else . end)'
    '';
  };

  local = name: path: {
    inherit name;
    url = "http://127.0.0.1:${toString ports.${name}}${path}";
    interval = "1m";
    conditions = ["[STATUS] == 200"];
    alerts = [{type = "telegram";}];
  };

  listening = name: {
    inherit name;
    url = "tcp://127.0.0.1:${toString ports.${name}}";
    interval = "1m";
    conditions = ["[CONNECTED] == true"];
    alerts = [{type = "telegram";}];
  };

  link = name: href: icon: description: {
    ${name} = {inherit href icon description;};
  };
in {
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  hardware.enableRedistributableFirmware = true;
  hardware.graphics = {
    enable = true;
    extraPackages = [pkgs.intel-media-driver];
  };

  services.fstrim.enable = true;

  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="block", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", RUN+="${pkgs.hdparm}/bin/hdparm -S 242 /dev/%k"
    ACTION=="change", SUBSYSTEM=="block", KERNEL=="sr[0-9]", ENV{DISK_MEDIA_CHANGE}=="1", ENV{ID_CDROM_MEDIA}=="1", RUN+="${pkgs.systemd}/bin/systemctl --no-block start disc@%k.service"
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
    rutracker = secret "rutracker";
    syncthing-cert = secret "syncthing-cert" // {owner = "syncthing";};
    syncthing-key = secret "syncthing-key" // {owner = "syncthing";};
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
      "adguard.${domain}" = guarded ports.adguard;
      "jellyfin.${domain}" = proxy ports.jellyfin;
      "torrent.${domain}" = guarded ports.qbittorrent;
      "torrserver.${domain}" = guarded ports.torrserver;
      "sync.${domain}" = guarded ports.syncthing;
      "vault.${domain}" = proxy ports.vaultwarden;
      "photos.${domain}" = proxy ports.immich;
      "cloud.${domain}" = proxy ports.opencloud;
      "jackett.${domain}" = {
        useACMEHost = domain;
        extraConfig = ''
          @ui not path /api/* /dl/*
          basic_auth @ui {
            lux {$ADMIN_HASH}
          }
          reverse_proxy 127.0.0.1:${toString ports.jackett}
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
        rewrites_enabled = true;
        rewrites = [
          {
            domain = "wg.${domain}";
            answer = "192.168.1.10";
            enabled = true;
          }
        ];
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
        (local "jellyfin" "/health")
        (local "qbittorrent" "/")
        (local "flaresolverr" "/")
        (local "torrserver" "/echo")
        (local "syncthing" "/rest/noauth/health")
        (listening "jackett")
        (local "vaultwarden" "/alive")
        (local "immich" "/api/server/ping")
        (listening "opencloud")
        {
          name = "pumpkin";
          url = "tcp://${pumpkin.localAddress}:${toString pumpkin.port}";
          interval = "1m";
          conditions = ["[CONNECTED] == true"];
          alerts = [{type = "telegram";}];
        }
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
        "Медиа" = [
          (link "Jellyfin" "https://jellyfin.${domain}" "jellyfin.svg" "Фильмы и сериалы")
          (link "qBittorrent" "https://torrent.${domain}" "qbittorrent.svg" "Загрузки")
          (link "Jackett" "https://jackett.${domain}" "jackett.svg" "Поиск по трекерам")
          (link "TorrServer" "https://torrserver.${domain}" "torrserver.png" "Торренты онлайн для Lampa")
        ];
      }
      {
        "Файлы" = [
          (link "OpenCloud" "https://cloud.${domain}" "opencloud.svg" "Облако")
          (link "Immich" "https://photos.${domain}" "immich.svg" "Фото")
          (link "Vaultwarden" "https://vault.${domain}" "vaultwarden.svg" "Пароли")
          (link "Syncthing" "https://sync.${domain}" "syncthing.svg" "Documents и Downloads с ноутбука")
        ];
      }
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

  systemd.tmpfiles.settings."10-media" = lib.genAttrs (map (dir: "${media}${dir}") ["" "/downloads" "/movies" "/shows" "/music" "/discs"]) (_: {
    d = {
      user = "lux";
      group = "media";
      mode = "2775";
    };
  });

  services.jellyfin = {
    enable = true;
    hardwareAcceleration = {
      enable = true;
      type = "vaapi";
      device = "/dev/dri/renderD128";
    };
    transcoding = {
      enableHardwareEncoding = true;
      hardwareDecodingCodecs = {
        h264 = true;
        hevc = true;
        hevc10bit = true;
        mpeg2 = true;
        vc1 = true;
        vp8 = true;
        vp9 = true;
      };
      hardwareEncodingCodecs.hevc = true;
    };
  };
  users.users.jellyfin.extraGroups = ["media" "render" "video"];
  systemd.services.jellyfin.environment.LIBVA_DRIVER_NAME = "iHD";

  services.qbittorrent = {
    enable = true;
    group = "media";
    webuiPort = ports.qbittorrent;
    serverConfig = {
      LegalNotice.Accepted = true;
      BitTorrent.Session = {
        DefaultSavePath = "${media}/downloads";
        TempPathEnabled = true;
        TempPath = "${media}/downloads/.incomplete";
      };
      Preferences = {
        General.Locale = "ru";
        WebUI = {
          Address = "127.0.0.1";
          LocalHostAuth = false;
          AlternativeUIEnabled = true;
          RootFolder = "${pkgs.vuetorrent}/share/vuetorrent";
        };
      };
    };
  };
  systemd.services.qbittorrent = {
    unitConfig.RequiresMountsFor = [media];
    serviceConfig.UMask = "0002";
  };

  services.flaresolverr = {
    enable = true;
    port = ports.flaresolverr;
  };

  services.jackett = {
    enable = true;
    port = ports.jackett;
  };
  systemd.services.jackett.preStart = ''
    conf=${config.services.jackett.dataDir}/ServerConfig.json
    [ -e "$conf" ] || echo '{}' > "$conf"
    ${lib.getExe pkgs.jq} '.AllowExternal = false | .FlareSolverrUrl = "http://127.0.0.1:${toString ports.flaresolverr}"' \
      "$conf" > "$conf.tmp"
    mv "$conf.tmp" "$conf"
  '';

  systemd.services.jackett-indexers = {
    after = ["jackett.service" "flaresolverr.service"];
    requires = ["jackett.service"];
    serviceConfig = {
      Type = "oneshot";
      User = config.services.jackett.user;
      EnvironmentFile = config.age.secrets.rutracker.path;
      ExecStart = lib.getExe jackettIndexers;
    };
  };
  systemd.timers.jackett-indexers = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnActiveSec = "2min";
      OnUnitInactiveSec = "1h";
    };
  };

  systemd.services.torrserver = {
    description = "TorrServer";
    wantedBy = ["multi-user.target"];
    after = ["network-online.target"];
    wants = ["network-online.target"];
    serviceConfig = {
      ExecStart = "${lib.getExe' pkgs.torrserver "torrserver"} --port ${toString ports.torrserver} --path /var/lib/torrserver";
      DynamicUser = true;
      StateDirectory = "torrserver";
      Restart = "on-failure";
    };
  };

  services.nfs.server = {
    enable = true;
    exports = ''
      ${media} 192.168.1.0/24(rw,sync,no_subtree_check) 10.100.0.0/24(rw,sync,no_subtree_check)
    '';
  };

  services.syncthing = {
    enable = true;
    guiAddress = "127.0.0.1:${toString ports.syncthing}";
    cert = config.age.secrets.syncthing-cert.path;
    key = config.age.secrets.syncthing-key.path;
    settings = {
      gui.insecureSkipHostcheck = true;
      options = {
        globalAnnounceEnabled = false;
        relaysEnabled = false;
        natEnabled = false;
        urAccepted = -1;
      };
      devices.legion.id = "AYXBQIS-CZIULWX-6ISSWZZ-APOZQ22-WH573C5-TB5PS5Q-7XZVSMB-2QQZPQW";
      folders = {
        documents = {
          path = "/var/lib/syncthing/Documents";
          devices = ["legion"];
          versioning = {
            type = "staggered";
            params.maxAge = toString (90 * 24 * 3600);
          };
        };
        downloads = {
          path = "/srv/sync/Downloads";
          devices = ["legion"];
        };
      };
    };
  };
  systemd.tmpfiles.settings."10-sync"."/srv/sync".d = {
    user = "syncthing";
    group = "syncthing";
    mode = "0750";
  };

  services.vaultwarden = {
    enable = true;
    domain = "vault.${domain}";
    config = {
      ROCKET_ADDRESS = "127.0.0.1";
      ROCKET_PORT = ports.vaultwarden;
      SIGNUPS_ALLOWED = true;
      SIGNUPS_DOMAINS_WHITELIST = "tutamail.com";
    };
  };

  services.immich = {
    enable = true;
    host = "127.0.0.1";
    port = ports.immich;
    mediaLocation = photos;
    accelerationDevices = ["/dev/dri/renderD128"];
  };
  users.users.immich.extraGroups = ["render" "video"];
  systemd.services.immich-server.unitConfig.RequiresMountsFor = [photos];

  services.opencloud = {
    enable = true;
    port = ports.opencloud;
    url = "https://cloud.${domain}";
    environment = {
      OC_INSECURE = "true";
      PROXY_TLS = "false";
      STORAGE_USERS_POSIX_ROOT = cloud;
      STORAGE_USERS_POSIX_WATCH_FS = "true";
      STORAGE_USERS_POSIX_PERSONAL_SPACE_PATH_TEMPLATE = "users/{{.User.Username}}";
      STORAGE_USERS_POSIX_GENERAL_SPACE_PATH_TEMPLATE = "projects/{{.SpaceName | replace \" \" \"-\" | lower}}";
    };
  };
  systemd.services.opencloud = {
    path = [pkgs.inotify-tools];
    unitConfig.RequiresMountsFor = [cloud];
    serviceConfig.ReadWritePaths = [cloud];
  };

  systemd.tmpfiles.settings."10-apps" = {
    ${photos}.d = {
      user = "immich";
      group = "immich";
      mode = "0750";
    };
    ${cloud}.d = {
      user = "opencloud";
      group = "opencloud";
      mode = "0750";
    };
    ${photosRepo}.d = {
      user = "root";
      group = "users";
      mode = "0750";
    };
  };

  environment.systemPackages = [disc];

  systemd.services."disc@" = {
    description = "Rip or burn the disc in %I";
    unitConfig.RequiresMountsFor = [media];
    serviceConfig = {
      Type = "exec";
      ExecStart = "${lib.getExe disc} auto /dev/%I";
      Nice = 10;
      IOSchedulingClass = "idle";
    };
  };

  networking.nat = {
    enable = true;
    internalInterfaces = ["ve-pumpkin"];
    externalInterface = lan;
    forwardPorts = [
      {
        sourcePort = pumpkin.port;
        destination = "${pumpkin.localAddress}:${toString pumpkin.port}";
        proto = "tcp";
      }
    ];
  };

  containers.pumpkin = {
    autoStart = true;
    privateNetwork = true;
    inherit (pumpkin) hostAddress localAddress;
    config = {
      networking.firewall.allowedTCPPorts = [pumpkin.port];
      services.pumpkin = {
        enable = true;
        package = inputs.pumpkin.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs (old: {
          meta = old.meta // {mainProgram = "pumpkin";};
        });
        whitelist.entries = [
          {
            name = "lux";
            uuid = "9ff79cfc-7c53-3f13-a106-bc356cf2522a";
          }
        ];
        settings = {
          white_list = true;
          enforce_whitelist = true;
          networking = {
            query.enabled = false;
            java = {
              address = "0.0.0.0:${toString pumpkin.port}";
              online_mode = false;
              authentication.enabled = false;
              max_players = 10;
              motd = "homelab";
            };
          };
        };
      };
      system.stateVersion = "26.11";
    };
  };

  services.harmonia.cache = {
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

  services.restic.backups.photos = {
    repository = photosRepo;
    passwordFile = config.age.secrets.restic.path;
    initialize = true;
    paths = [photos];
    exclude = ["${photos}/thumbs" "${photos}/encoded-video"];
    backupCleanupCommand = "chgrp -R users ${photosRepo} && chmod -R g+rX ${photosRepo}";
    timerConfig = {
      OnCalendar = "04:00";
      Persistent = true;
    };
  };

  system.stateVersion = "26.11";
}
