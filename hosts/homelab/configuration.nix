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
  publicPort = 8443;

  secret = name: {file = ../../secrets/homelab + "/${name}.age";};
  sudoKeys = ./sudo_keys;

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
    couchdb = 5984;
    firefly = 8084;
    flaresolverr = 8191;
    gatus = 8083;
    harmonia = 5000;
    homemusic = 8092;
    homepage = 8082;
    immich = 2283;
    ipp = 3010;
    jackett = 9117;
    jellyfin = 8096;
    karakeep = 3020;
    navidrome = 4533;
    opencloud = 9200;
    paperless = 28981;
    qbittorrent = 8080;
    scrutiny = 8081;
    syncthing = 8384;
    torrserver = 8091;
    vaultwarden = 8222;
    webdav = 6065;
  };

  media = "/srv/media";
  photos = "/srv/photos";
  cloud = "/srv/cloud";
  music = "/srv/music";

  # HomeMusic Hub: stays off until secrets/homelab/homemusic.age exists (wizards/homemusic.sh).
  hubEnabled = builtins.pathExists ../../secrets/homelab/homemusic.age;
  hubRev = "f852fca71885eb1bb4797d420f96325864ca6775";
  hubSrc = pkgs.fetchFromGitHub {
    owner = "justman-1";
    repo = "HomeMusic-public";
    rev = hubRev;
    hash = "sha256-aMSIwUjfdqVgmOuvAGUpT7bnFr1LZVwI3kAy/sbF7O4=";
  };
  # A stable tag: a rev bump rebuilds and restarts in the background instead of failing the switch.
  hubImage = "localhost/homemusic-hub:pinned";
  hubRoot = "/srv/homemusic";
  hubData = "/var/lib/homemusic-hub";
  potPort = 4416;

  photosRepo = "/var/backup/photos";
  filesRepo = "/var/backup/files";
  vaultwardenBackup = "/var/lib/backups/vaultwarden";

  storagebox = lib.importJSON ../storagebox.json;

  retention = ["--keep-daily 7" "--keep-weekly 4" "--keep-monthly 6"];

  statusbotInbox = "/var/lib/statusbot-inbox";

  statusbot = pkgs.buildGoModule {
    pname = "statusbot";
    version = "1";
    src = ./statusbot;
    vendorHash = null;
  };

  pumpkin = {
    port = 41565;
    hostAddress = "10.233.1.1";
    localAddress = "10.233.1.2";
  };

  abcdeConf = pkgs.writeText "abcde.conf" (lib.concatLines [
    "CDDBMETHOD=musicbrainz"
    "OUTPUTTYPE=flac"
    "OUTPUTDIR=${music}"
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
      (handbrake.override {
        ffmpeg_8-full = ffmpeg_8-full.override {
          version = "8.1.2";
          hash = "sha256-wJ3c8VVo/tK84K7bKYs/UWcln4mSO+tf/w5NLNjKhiI=";
        };
      })
      systemd
      util-linux
      xorriso
    ];
    runtimeEnv = {
      MEDIA = media;
      MUSIC = music;
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

  loopback = port: "http://127.0.0.1:${toString port}";

  # Firefly is PHP-FPM with no port of its own; the loopback copy is for Gatus and Homepage.
  firefly = ''
    root * ${config.services.firefly-iii.package}/public
    php_fastcgi unix/${config.services.phpfpm.pools.firefly-iii.socket}
    file_server
  '';

  app = port: sub: icon: description: {
    href = "https://${sub}.${domain}";
    siteMonitor = loopback port;
    inherit icon description;
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

  # A touch on the YubiKey, through the agent legion forwards, stands in for
  # the password. Only the key in sudo_keys counts, not every authorized key.
  security.pam.rssh = {
    enable = true;
    settings.auth_key_file = "${sudoKeys}";
  };
  security.pam.services.sudo.rssh = true;
  # Without this, sudo -n refuses before PAM can ask the agent.
  security.sudo.extraConfig = ''
    Defaults:lux noninteractive_auth
  '';

  users.mutableUsers = false;
  users.users.lux = {
    # The Hub container runs as lux:media, so the uid has to be known at build time.
    uid = 1000;
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
    couchdb-admin = secret "couchdb-admin" // {owner = "couchdb";};
    webdav = secret "webdav";
    rutracker = secret "rutracker";
    syncthing-cert = secret "syncthing-cert" // {owner = "syncthing";};
    syncthing-key = secret "syncthing-key" // {owner = "syncthing";};
    firefly-app-key = secret "firefly-app-key" // {owner = "firefly-iii";};
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
    virtualHosts =
      {
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
        "share.${domain}" =
          proxy ports.ipp
          // {
            serverAliases = ["share.${domain}:${toString publicPort}"];
          };
        "cloud.${domain}" = proxy ports.opencloud;
        "couch.${domain}" = proxy ports.couchdb;
        "dav.${domain}" = proxy ports.webdav;
        "music.${domain}" = proxy ports.navidrome;
        "docs.${domain}" = proxy ports.paperless;
        "keep.${domain}" = proxy ports.karakeep;
        "budget.${domain}" = {
          useACMEHost = domain;
          extraConfig = firefly;
        };
        "http://127.0.0.1:${toString ports.firefly}".extraConfig = firefly + "bind 127.0.0.1\n";
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
      }
      // lib.optionalAttrs hubEnabled {"musichub.${domain}" = proxy ports.homemusic;};
  };

  services.adguardhome = {
    enable = true;
    mutableSettings = false;
    settings = {
      http.address = "127.0.0.1:${toString ports.adguard}";
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
          {
            domain = "share.${domain}";
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
    settings.web = {
      listen = {
        host = "127.0.0.1";
        port = ports.scrutiny;
      };
      influxdb.host = "127.0.0.1";
    };
  };
  # Its only client is Scrutiny, which connects over loopback.
  services.influxdb2.settings.http-bind-address = "127.0.0.1:8086";

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
      endpoints =
        [
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
          (listening "ipp")
          (listening "opencloud")
          (local "couchdb" "/_up")
          (listening "webdav")
          (local "navidrome" "/ping")
          (listening "paperless")
          (listening "karakeep")
          (local "firefly" "/health")
          {
            name = "pumpkin";
            url = "tcp://${pumpkin.localAddress}:${toString pumpkin.port}";
            interval = "1m";
            conditions = ["[CONNECTED] == true"];
            alerts = [{type = "telegram";}];
          }
          {
            name = "certificate";
            url = "https://home.${domain}";
            interval = "1h";
            conditions = ["[CERTIFICATE_EXPIRATION] > 240h"];
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
        ]
        ++ lib.optional hubEnabled (local "homemusic" "/healthz");
    };
  };

  services.homepage-dashboard = {
    enable = true;
    listenPort = ports.homepage;
    allowedHosts = "home.${domain}";
    settings = {
      title = "homelab";
      language = "ru";
      theme = "dark";
      color = "slate";
      headerStyle = "clean";
      statusStyle = "dot";
      hideVersion = true;
    };
    widgets = [
      {
        resources = {
          cpu = true;
          memory = true;
          disk = ["/" "/srv"];
          cputemp = true;
          units = "metric";
        };
      }
      {
        datetime = {
          text_size = "xl";
          format = {
            dateStyle = "long";
            timeStyle = "short";
            hour12 = false;
          };
        };
      }
    ];
    services = [
      {
        "Медиа" =
          [
            {Jellyfin = app ports.jellyfin "jellyfin" "jellyfin.svg" "Фильмы и сериалы";}
            {Navidrome = app ports.navidrome "music" "navidrome.svg" "Музыка";}
            {
              qBittorrent =
                app ports.qbittorrent "torrent" "qbittorrent.svg" "Загрузки"
                // {
                  widget = {
                    type = "qbittorrent";
                    url = loopback ports.qbittorrent;
                  };
                };
            }
            {Jackett = app ports.jackett "jackett" "jackett.svg" "Поиск по трекерам";}
            {TorrServer = app ports.torrserver "torrserver" "torrserver.png" "Торренты онлайн для Lampa";}
          ]
          ++ lib.optional hubEnabled {"HomeMusic Hub" = app ports.homemusic "musichub" "mdi-music-box-multiple" "Поиск и загрузка музыки";};
      }
      {
        "Файлы" = [
          {OpenCloud = app ports.opencloud "cloud" "sh-opencloud.svg" "Облако";}
          {Immich = app ports.immich "photos" "immich.svg" "Фото";}
          {Vaultwarden = app ports.vaultwarden "vault" "vaultwarden.svg" "Пароли";}
          {Syncthing = app ports.syncthing "sync" "syncthing.svg" "Documents и Downloads с ноутбука";}
        ];
      }
      {
        "Личное" = [
          {Paperless = app ports.paperless "docs" "paperless-ngx.svg" "Документы и сканы";}
          {Karakeep = app ports.karakeep "keep" "karakeep.svg" "Закладки и статьи";}
          {"Firefly III" = app ports.firefly "budget" "firefly-iii.svg" "Бюджет";}
        ];
      }
      {
        "Система" = [
          {
            AdGuard =
              app ports.adguard "adguard" "adguard-home.svg" "DNS и блокировка рекламы"
              // {
                widget = {
                  type = "adguard";
                  url = loopback ports.adguard;
                  fields = ["queries" "blocked" "latency"];
                };
              };
          }
          {Beszel = app ports.beszel "beszel" "beszel.svg" "Нагрузка на сервер";}
          {
            Gatus =
              app ports.gatus "status" "gatus.svg" "Живы ли сервисы"
              // {
                widget = {
                  type = "gatus";
                  url = loopback ports.gatus;
                };
              };
          }
          {
            Scrutiny =
              app ports.scrutiny "disks" "scrutiny.svg" "Здоровье дисков"
              // {
                widget = {
                  type = "scrutiny";
                  url = loopback ports.scrutiny;
                };
              };
          }
        ];
      }
      {
        "Игры" = [
          {
            Minecraft = {
              href = "https://mcsrvstat.us/server/mc.${domain}";
              icon = "minecraft.svg";
              description = "mc.${domain}, клиент 26.3";
              widget = {
                type = "minecraft";
                url = "udp://${pumpkin.localAddress}:${toString pumpkin.port}";
              };
            };
          }
        ];
      }
    ];
    bookmarks = [
      {
        "Ссылки" = [
          {
            "Роутер" = [
              {
                href = "http://192.168.1.1";
                icon = "huawei.svg";
              }
            ];
          }
          {
            Cloudflare = [
              {
                href = "https://dash.cloudflare.com";
                icon = "cloudflare.svg";
              }
            ];
          }
          {
            GitHub = [
              {
                href = "https://github.com/luxqw/nixos-btw";
                icon = "github-light.svg";
              }
            ];
          }
        ];
      }
    ];
  };

  environment.etc."homepage-dashboard/settings.yaml".source = let
    rows = ["Медиа" "Файлы" "Личное" "Система" "Игры" "Ссылки"];
    layout = lib.concatMapStringsSep "," (group: ''${builtins.toJSON group}:{"style":"row","columns":4}'') rows;
  in
    lib.mkForce (pkgs.writeText "settings.yaml"
      (lib.removeSuffix "}" (builtins.toJSON config.services.homepage-dashboard.settings) + '',"layout":{${layout}}}''));

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
        # Only 8443 and Pumpkin are forwarded; UPnP would open a port on its own.
        Connection.UPnP = false;
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
  # Only Jackett and Gatus use it, both over loopback.
  systemd.services.flaresolverr.environment.HOST = "127.0.0.1";

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
    backupDir = vaultwardenBackup;
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

  services.immich-public-proxy = {
    enable = true;
    immichUrl = loopback ports.immich;
    port = ports.ipp;
  };

  services.opencloud = {
    enable = true;
    package = pkgs.opencloud;
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

  services.paperless = {
    enable = true;
    port = ports.paperless;
    domain = "docs.${domain}";
    exporter.enable = true;
    settings = {
      PAPERLESS_OCR_LANGUAGE = "srp+srp_latn+rus+eng";
      PAPERLESS_TIME_ZONE = config.time.timeZone;
      PAPERLESS_FILENAME_FORMAT = "{{ created_year }}/{{ correspondent }}/{{ title }}";
    };
  };

  services.karakeep = {
    enable = true;
    extraEnvironment = {
      PORT = toString ports.karakeep;
      NEXTAUTH_URL = "https://keep.${domain}";
      DISABLE_NEW_RELEASE_CHECK = "true";
      DISABLE_SIGNUPS = "true";
      # Caddy, Gatus and Homepage reach it over loopback; NEXTAUTH_URL leaves no direct clients.
      HOSTNAME = "127.0.0.1";
      CRAWLER_FULL_PAGE_ARCHIVE = "true";
      CRAWLER_STORE_SCREENSHOT = "true";
    };
  };

  services.firefly-iii = {
    enable = true;
    poolConfig = {
      "listen.owner" = config.services.caddy.user;
      "listen.group" = config.services.caddy.group;
    };
    settings = {
      APP_URL = "https://budget.${domain}";
      APP_KEY_FILE = config.age.secrets.firefly-app-key.path;
      TZ = config.time.timeZone;
      MAIL_MAILER = "log";
      ENABLE_EXCHANGE_RATES = "true";
      ENABLE_EXTERNAL_RATES = "true";
    };
  };

  services.couchdb = {
    enable = true;
    bindAddress = "127.0.0.1";
    port = ports.couchdb;
    extraConfigFiles = [config.age.secrets.couchdb-admin.path];
    extraConfig = {
      couchdb = {
        single_node = true;
        max_document_size = 50000000;
      };
      chttpd = {
        require_valid_user_except_for_up = true;
        max_http_request_size = 4294967296;
        enable_cors = true;
      };
      httpd = {
        WWW-Authenticate = ''Basic realm="couchdb"'';
        enable_cors = true;
      };
      cors = {
        origins = "app://obsidian.md,capacitor://localhost,http://localhost";
        credentials = true;
        headers = "accept, authorization, content-type, origin, referer";
        methods = "GET,PUT,POST,HEAD,DELETE";
        max_age = 3600;
      };
    };
  };

  services.webdav = {
    enable = true;
    environmentFile = config.age.secrets.webdav.path;
    settings = {
      address = "127.0.0.1";
      port = ports.webdav;
      behindProxy = true;
      directory = "/var/lib/webdav";
      permissions = "CRUD";
      users = [
        {
          username = "{env}WEBDAV_USERNAME";
          password = "{env}WEBDAV_PASSWORD";
        }
      ];
    };
  };
  systemd.services.webdav.serviceConfig.StateDirectory = "webdav";

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
    ${music}.d = {
      user = "root";
      group = "media";
      mode = "2775";
    };
    ${vaultwardenBackup}.d = {
      user = "vaultwarden";
      group = "vaultwarden";
      mode = "0700";
    };
  };

  environment.systemPackages = [disc];

  systemd.services."disc@" = {
    description = "Rip or burn the disc in %I";
    unitConfig.RequiresMountsFor = [media music];
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
            name = "luxqww";
            uuid = "79ef51ec-132e-603b-6d0c-75fde3703c85";
          }
        ];
        settings = {
          white_list = false;
          enforce_whitelist = false;
          spawn_protection = 0;
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
      systemd.services.pumpkin.preStart = let
        ops = pkgs.writeText "ops.json" (builtins.toJSON [
          {
            name = "luxqww";
            uuid = "79ef51ec-132e-603b-6d0c-75fde3703c85";
            level = 4;
            bypassesPlayerLimit = true;
          }
        ]);
      in
        lib.mkAfter ''
          mkdir -p data
          if [ -s data/ops.json ]; then
            ${lib.getExe pkgs.jq} -s 'add | unique_by(.uuid)' ${ops} data/ops.json > data/ops.json.new
            mv data/ops.json.new data/ops.json
          else
            install -m600 ${ops} data/ops.json
          fi
        '';
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
    pruneOpts = retention;
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

  services.restic.backups.files = {
    repository = filesRepo;
    passwordFile = config.age.secrets.restic.path;
    initialize = true;
    paths = [cloud "/srv/sync" music];
    timerConfig = {
      OnCalendar = "04:15";
      Persistent = true;
    };
    pruneOpts = retention;
  };

  services.restic.backups.offsite = {
    repository = "sftp:storagebox:restic";
    passwordFile = config.age.secrets.restic.path;
    initialize = true;
    paths = ["/var/lib" photos cloud "/srv/sync" music];
    exclude = [
      "/var/lib/systemd/coredump"
      "/var/lib/containers"
      "/var/lib/postgresql"
      "${photos}/thumbs"
      "${photos}/encoded-video"
    ];
    timerConfig = {
      OnCalendar = "04:30";
      Persistent = true;
    };
    pruneOpts = retention;
    checkOpts = ["--read-data-subset=5%"];
  };

  age.secrets.storagebox-key = secret "storagebox-key";

  programs.ssh = {
    extraConfig = ''
      Host storagebox
        HostName ${storagebox.homelab.host}
        User ${storagebox.homelab.user}
        Port 23
        ServerAliveInterval 15
        ServerAliveCountMax 4
        IdentityFile ${config.age.secrets.storagebox-key.path}
    '';
    knownHosts.storagebox = {
      hostNames = ["[${storagebox.homelab.host}]:23"];
      publicKey = storagebox.hostKey;
    };
  };

  systemd.services."notify-telegram@" = {
    description = "Tell Telegram that %i failed";
    path = [pkgs.curl];
    scriptArgs = "%i";
    script = ''
      curl -sf -o /dev/null "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage" \
        -d chat_id="$TELEGRAM_CHAT_ID" --data-urlencode text="❌ $1 failed on homelab: journalctl -u $1"
    '';
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = config.age.secrets.telegram.path;
    };
  };
  # /srv is nofail: without it a job would back up (or initialise a repo in) an empty mount point.
  systemd.services.restic-backups-local.unitConfig = {
    OnFailure = ["notify-telegram@%N.service"];
    RequiresMountsFor = ["/srv"];
  };
  systemd.services.restic-backups-photos.unitConfig = {
    OnFailure = ["notify-telegram@%N.service"];
    RequiresMountsFor = ["/srv"];
  };
  systemd.services.restic-backups-files.unitConfig = {
    OnFailure = ["notify-telegram@%N.service"];
    RequiresMountsFor = ["/srv"];
  };
  systemd.services.restic-backups-offsite.unitConfig = {
    OnFailure = ["notify-telegram@%N.service"];
    RequiresMountsFor = ["/srv"];
  };
  systemd.services.backup-vaultwarden.unitConfig.OnFailure = ["notify-telegram@%N.service"];
  systemd.services.paperless-exporter.unitConfig.OnFailure = lib.mkAfter ["notify-telegram@%N.service"];
  systemd.services.btrbk-local.unitConfig.OnFailure = ["notify-telegram@%N.service"];
  systemd.services.statusbot-digest.unitConfig.OnFailure = ["notify-telegram@%N.service"];
  systemd.services.scrutiny-collector.unitConfig.OnFailure = ["notify-telegram@%N.service"];

  # Restores the newest offsite copy of Vaultwarden's database and opens it, so a
  # backup that can't be restored shows up here and not on the day it's needed.
  systemd.services.restore-test = {
    description = "Restore Vaultwarden from the offsite backup and check it";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    startAt = "monthly";
    path = [pkgs.restic pkgs.openssh pkgs.sqlite];
    environment = {
      RESTIC_REPOSITORY = "sftp:storagebox:restic";
      RESTIC_PASSWORD_FILE = config.age.secrets.restic.path;
    };
    unitConfig.OnFailure = ["notify-telegram@%N.service"];
    script = ''
      dir=$(mktemp -d)
      trap 'rm -rf "$dir"' EXIT
      # System units have no HOME for a cache, and a test should not trust local state.
      restic --no-cache restore latest --target "$dir" --include ${vaultwardenBackup}
      db=$dir${vaultwardenBackup}/db.sqlite3
      [ "$(sqlite3 "$db" 'PRAGMA integrity_check')" = ok ]
      [ "$(sqlite3 "$db" 'SELECT count(*) FROM users')" -gt 0 ]
    '';
    serviceConfig = {
      Type = "oneshot";
      PrivateTmp = true;
      TimeoutStartSec = "30min";
    };
  };
  systemd.timers.restore-test.timerConfig.Persistent = true;

  environment.etc."statusbot.json".text = builtins.toJSON {
    passwordFile = config.age.secrets.restic.path;
    repos = {
      local = {
        medium = "hdd";
        repo = "/srv/backup/restic";
      };
      photos = {
        medium = "nvme";
        repo = photosRepo;
      };
      files = {
        medium = "nvme";
        repo = filesRepo;
      };
      legion = {
        medium = "offsite";
        heartbeat = "${statusbotInbox}/legion";
      };
      offsite = {
        medium = "offsite";
        repo = "sftp:storagebox:restic";
      };
    };
    classes = [
      {
        name = "vaultwarden";
        live = "nvme";
        repos = ["local" "offsite"];
      }
      {
        name = "obsidian, tasks, app state";
        live = "nvme";
        repos = ["local" "offsite"];
      }
      {
        name = "documents, bookmarks, budget";
        live = "nvme";
        repos = ["local" "offsite"];
      }
      {
        name = "photos";
        live = "hdd";
        repos = ["photos" "offsite"];
      }
      {
        name = "cloud, synced folders, music";
        live = "hdd";
        repos = ["files" "offsite"];
      }
      {
        name = "legion";
        live = "laptop";
        repos = ["legion"];
        # One offsite repo is all the laptop has.
        copies = 2;
      }
    ];
    backupUnits = ["backup-vaultwarden" "restic-backups-local" "restic-backups-photos" "restic-backups-files" "restic-backups-offsite"];
    services =
      [
        "adguardhome"
        "caddy"
        "container@pumpkin"
        "couchdb"
        "flaresolverr"
        "gatus"
        "homepage-dashboard"
        "immich-machine-learning"
        "immich-server"
        "jackett"
        "jellyfin"
        "karakeep-web"
        "karakeep-workers"
        "navidrome"
        "opencloud"
        "paperless-consumer"
        "paperless-web"
        "phpfpm-firefly-iii"
        "qbittorrent"
        "scrutiny"
        "syncthing"
        "torrserver"
        "vaultwarden"
        "webdav"
      ]
      ++ lib.optionals hubEnabled ["podman-homemusic-hub" "podman-youtube-pot"];
    disks = ["/" "/srv"];
    gatus = loopback ports.gatus;
    scrutiny = loopback ports.scrutiny;
    flakeLock = "https://raw.githubusercontent.com/luxqw/nixos-btw/main/flake.lock";
    maxAgeHours = 36;
  };

  systemd.services.statusbot = {
    description = "Telegram status bot";
    wantedBy = ["multi-user.target"];
    wants = ["network-online.target"];
    after = ["network-online.target"];
    path = [pkgs.restic pkgs.openssh config.systemd.package];
    environment.RESTIC_CACHE_DIR = "/var/cache/statusbot";
    restartTriggers = [config.environment.etc."statusbot.json".source];
    serviceConfig = {
      ExecStart = "${statusbot}/bin/statusbot serve /etc/statusbot.json";
      EnvironmentFile = config.age.secrets.telegram.path;
      CacheDirectory = "statusbot";
      Restart = "always";
      RestartSec = 10;
    };
  };

  systemd.services.statusbot-digest = {
    description = "Morning digest from the status bot";
    startAt = "08:00";
    path = [pkgs.restic pkgs.openssh config.systemd.package];
    environment.RESTIC_CACHE_DIR = "/var/cache/statusbot";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${statusbot}/bin/statusbot digest /etc/statusbot.json";
      EnvironmentFile = config.age.secrets.telegram.path;
      CacheDirectory = "statusbot";
      TimeoutStartSec = "5min";
    };
  };

  systemd.tmpfiles.settings."10-statusbot".${statusbotInbox}.d = {
    user = "root";
    group = "users";
    mode = "0775";
  };

  services.navidrome = {
    enable = true;
    group = "media";
    settings =
      lib.recursiveUpdate {
        Address = "127.0.0.1";
        Port = ports.navidrome;
        MusicFolder = music;
        BaseUrl = "https://music.${domain}";
        Scanner.Schedule = "@every 1h";
        ListenBrainz.Enabled = true;
        EnableInsightsCollector = false;
      } (lib.optionalAttrs hubEnabled {
        # The Hub links its files to Navidrome songs by path. No PID.* rules: they would re-key the existing library.
        Subsonic.DefaultReportRealPath = true;
        Scanner.PurgeMissing = "never";
        Tags = {
          homemusic_track_id.Aliases = ["homemusic_track_id" "txxx:homemusic_track_id" "----:com.apple.itunes:homemusic_track_id"];
          homemusic_album_id = {
            Aliases = ["homemusic_album_id" "txxx:homemusic_album_id" "----:com.apple.itunes:homemusic_album_id"];
            Album = true;
          };
        };
      });
  };
  systemd.services.navidrome.unitConfig.RequiresMountsFor = [music];

  # Both Hub containers share the host network and listen on loopback only.
  virtualisation = lib.mkIf hubEnabled {
    podman.enable = true;
    oci-containers = {
      backend = "podman";
      containers = {
        # bgutil 2.0.2 takes --host; the image's default CMD binds 0.0.0.0.
        youtube-pot = {
          image = "brainicism/bgutil-ytdlp-pot-provider:2.0.2";
          # Pulled when the Hub starts (dependsOn), so a Docker Hub outage can't fail a switch.
          autoStart = false;
          cmd = ["--host" "127.0.0.1" "--port" (toString potPort)];
          extraOptions = ["--network=host" "--init" "--cap-drop=ALL" "--security-opt=no-new-privileges"];
        };

        homemusic-hub = {
          image = hubImage;
          # Built locally by homemusic-build, never pulled; that unit starts it, not the switch.
          pull = "never";
          autoStart = false;
          dependsOn = ["youtube-pot"];
          # lux:media owns what beets and abcde wrote to the library, and Navidrome reads it by group.
          user = "${toString config.users.users.lux.uid}:${toString config.users.groups.media.gid}";
          cmd = [
            "uvicorn"
            "app.main:app"
            "--host"
            "127.0.0.1"
            "--port"
            (toString ports.homemusic)
            "--proxy-headers"
            "--forwarded-allow-ips"
            "127.0.0.1"
            "--no-access-log"
          ];
          environment = {
            MUSIC_ROOT = "/music";
            DATA_DIR = "/data";
            HOME = "/data";
            CONFIG_FILE = "/config/config.yaml";
            NAVIDROME_URL = loopback ports.navidrome;
            YTDLP_POT_BASE_URL = loopback potPort;
            YTDLP_CACHE_DIR = "/data/yt-dlp-cache";
            PUBLIC_MUSIC_URL = "https://music.${domain}";
            PUBLIC_HUB_URL = "https://musichub.${domain}";
            TIMEZONE = "Europe/Belgrade";
            EMBEDDER_URL = "";
          };
          environmentFiles = [config.age.secrets.homemusic.path];
          volumes = [
            "${hubData}:/data"
            "${hubRoot}:/music"
            "${music}:/music/library"
            "${hubSrc}/config.example.yaml:/config/config.yaml:ro"
          ];
          extraOptions = ["--network=host" "--init" "--cap-drop=ALL" "--security-opt=no-new-privileges"];
        };
      };
    };
  };

  age.secrets.homemusic = lib.mkIf hubEnabled (secret "homemusic");

  systemd.tmpfiles.settings."10-homemusic" = lib.mkIf hubEnabled (lib.genAttrs [hubData hubRoot "${hubRoot}/library" "${hubRoot}/staging" "${hubRoot}/.trash" "${hubRoot}/.backups"] (_: {
    d = {
      user = "lux";
      group = "media";
      mode = "0755";
    };
  }));

  # The Hub's source is a Nix store path, so the image is built here, once per pinned revision.
  # A timer runs it after boot and after a rev bump, so a long or failed build never blocks or
  # fails deploy-homelab.
  systemd.services.homemusic-build = lib.mkIf hubEnabled {
    description = "Build the HomeMusic Hub image";
    wants = ["network-online.target"];
    after = ["network-online.target"];
    path = [config.virtualisation.podman.package config.systemd.package];
    unitConfig.OnFailure = ["notify-telegram@%N.service"];
    # A switch must never restart (and wait on) a running build; the timer picks up a new rev.
    restartIfChanged = false;
    script = ''
      built=$(podman image inspect --format '{{index .Labels "homemusic.rev"}}' ${hubImage} 2>/dev/null || true)
      if [ "$built" = ${hubRev} ]; then
        systemctl start --no-block podman-homemusic-hub.service
      else
        podman build --label homemusic.rev=${hubRev} -t ${hubImage} -f ${hubSrc}/hub/Dockerfile ${hubSrc}
        podman image prune -f
        systemctl restart --no-block podman-homemusic-hub.service
      fi
    '';
    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = "1h";
    };
  };

  systemd.timers.homemusic-build = lib.mkIf hubEnabled {
    wantedBy = ["timers.target"];
    restartTriggers = [hubRev];
    # The re-check catches a rev bump deployed while an older build was still running.
    timerConfig = {
      OnActiveSec = "1min";
      OnUnitInactiveSec = "6h";
    };
  };

  # Not ordered after homemusic-build: that unit starts the Hub itself, and the ordering would make
  # a switch-driven restart wait behind a running build.
  systemd.services.podman-homemusic-hub = lib.mkIf hubEnabled {
    requires = ["navidrome.service"];
    after = ["navidrome.service"];
    unitConfig.RequiresMountsFor = [music hubRoot];
  };

  system.stateVersion = "26.11";
}
