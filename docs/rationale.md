# Rationale

The nix code carries no comments. What can't be recovered by reading it —
the bug being worked around, the option that looks redundant but isn't, the
thing that was tried and failed — lives here, grouped by topic.

---

## flake.nix

**`millennium` has no `nixpkgs.follows`.** Its Bun FOD hash is pinned to its
own nixpkgs; following ours breaks the hash.

## hosts/legion/configuration.nix

### boot

**`v4l2loopback` deletes its own `modules.*` files.** Since kernel 7.3
`modules_install` runs depmod even for out-of-tree modules, and the index it
writes into the package collides with the kernel's in the merged module tree.
Fixed in nixpkgs by #575861/#577221; drop the override once they reach
`nixos-unstable`.

**`options nvidia_modeset vblank_sem_control=0`** works around flicker and a
black screen on resume, first seen under niri.
<https://github.com/niri-wm/niri/issues/3384>

**`nvidia`, `nvidia_modeset`, `nvidia_drm` in `boot.kernelModules`.**
nixpkgs only force-loads them early when `services.xserver.enable` is on.
There is no Xorg here, so without them early KMS races greetd and the
compositor at boot.

**The blank line inside `boot.extraModprobeConfig`** — see
[Merge order](#merge-order).

### hardware

**`HandlePowerKey = "ignore"`.** logind suspends directly and bypasses
noctalia's `lockOnSuspend`. noctalia handles the power key itself.

**The `lenovoctl` group and the tmpfiles rule** let the `lux/lenovo-legion`
noctalia plugin toggle `conservation_mode` without root. It has to be
tmpfiles: udev's `GROUP=`/`MODE=` apply only to `/dev` nodes, so a udev rule
on `ATTR{conservation_mode}` is a silent no-op (`udev(7)`). The glob covers
the ACPI instance name (`VPC2004:00`) without hardcoding it.

### graphics

**`NIXOS_OZONE_WL = "1"` next to `ELECTRON_OZONE_PLATFORM_HINT`** is not
redundant. The hint only reaches Electron; the chromium wrapper gates
`--ozone-platform-hint` on `NIXOS_OZONE_WL`. Without it chromium runs under
XWayland and screen sharing never starts.

### network

**v2raya is the only proxy client.** throne solved the same problem, and its
tun mode fought v2raya for the default route.

**The tunnel list is written down nowhere.** It is derived from
`secrets/wg/`; a filename is both the interface and the unit name. See
ADR 0001.

**The polkit rule** lets `lux` start/stop/restart exactly the tunnel units
without a password, and nothing else.

**`home` is in `manualTunnels`.** It is for reaching homelab from outside;
at home it would send traffic for the server out to the public IP and
back. `tunnel up home` when away.

**homelab is a remote builder and a substituter.** `connect-timeout = 3` and
the ssh `ConnectTimeout` keep builds from stalling away from home, where
`homelab.rakhmatullin.dev` (a LAN address) is unreachable.
The host key lives in `programs.ssh.knownHosts`, which root's ssh in the
build hook also reads, so `buildMachines` needs no `publicHostKey`.

**`deploy-homelab` builds on homelab itself** (`--build-host` = target): only
`.drv` files leave the laptop, and they are content-addressed, so they need
no signature. Pushing locally built outputs with `nix copy --to ssh-ng://…`
— what nh does when building locally — fails with "lacks a signature by a
trusted key" even for a trusted user: `nix copy` asks the remote to check,
and trusted only means `--no-check-sigs` is allowed. `nix-copy-closure`
(nixos-rebuild) doesn't check.

**`/mnt/media` is NFS from homelab, by IP**, so it doesn't depend on DNS.
`soft`, short timeouts and the automount keep file managers from hanging
when the server is out of reach.

### secrets

**Secrets are decrypted with the user's ssh key, not a host key.** There is
no openssh and no host key. That key is part of the system: reissue it for
GitHub and the tunnels silently stop coming up. See ADR 0001.

**The `tunnel` command** exists because the bare commands need three
unrelated facts at once: run from `/etc/nixos/secrets`, spell the name
`wg/<name>.age`, use `age` rather than `agenix` for a secret that doesn't
exist yet. `pkgs.age` is installed for that last one.

### apps

**Steam comes from Millennium's flake** (noctalia's steam template needs
it). Its profile relinks `ubuntu12_*/libXtst.so.6` on every launch, so the
loader never points at a garbage-collected store path.

**Wireshark goes through `programs.wireshark`.** Non-root capture needs the
`dumpcap` wrapper with `cap_net_raw`/`cap_net_admin` and the `wireshark`
group, both from the module. The default package is `wireshark-cli`, which
has no GUI.

**`neovim-unwrapped` is in the system packages** so root has an editor when
home-manager is unavailable.

**`environment.systemPackages` holds only what services, hardware or login
need.** Everything user-facing is in `home.nix`; what every host shares is
in `modules/common.nix`.

| package           | why                                           |
| ----------------- | --------------------------------------------- |
| `bibata-cursors`  | noctalia-greeter runs as its own user         |
| `ntfs3g`          | mounting the games partition                  |
| `wireguard-tools` | `wg show`                                     |

---

## hosts/homelab/configuration.nix

**The firewall trusts `eno1` and `home` outright.** Everything on the LAN
and the tunnel may reach every service. That is only safe because the
Huawei router forwards nothing but the WireGuard and game ports: never
turn on its DMZ.

**The tunnel routes `192.168.1.10/32`, not the whole LAN.** Service names
resolve to the server's LAN address. A /32 wins over any foreign network
that also uses `192.168.1.0/24`, which a /24 would collide with.

**`DNSStubListener = false`.** resolved's stub on 127.0.0.53:53 keeps
AdGuard from binding `0.0.0.0:53`.

**AdGuard's UI sits behind Caddy's `basic_auth`.** AdGuard's own users need
a bcrypt hash in its settings, which end up in this public repository; the
Caddy hash comes from an agenix env file instead. The same passphrase is
`lux`'s sudo password.

**`/srv` is `nofail`.** A dead HDD must not keep the server off the network.

**`hdparm -S 242`** spins the HDD down after an hour idle.

**No powertop.** Its autotune enables runtime PM on the I219 NIC, which is
known to drop the link.

**`dnsResolver` is Cloudflare's authoritative server.** lego otherwise
waits for the TXT record through the LAN resolver, which caches the
NXDOMAIN it got before the record existed, and the order times out.

**Gatus checks `127.0.0.1`, not the public names**, so the checks don't
depend on which LAN the server is plugged into.

**btrbk works on `/mnt/pool`**, the btrfs top level, because snapshots of
`@var-lib` go into the sibling `@snapshots`.

**Backups are 3-2-1 by disk.** Data on the NVMe (`/var/lib`) gets a
restic repo on the HDD (`local`); data on the HDD (`/srv/photos`,
`/srv/cloud`, `/srv/sync`) gets repos on the NVMe (`photos`, `files`).
`offsite` sends all of it, minus `/srv/media` (re-downloadable) and Immich's
thumbnails, to a Hetzner Storage Box over sftp on port 23. Live Postgres files
are left out of `offsite`: Immich's own nightly dump under `/srv/photos`
is the consistent copy. Vaultwarden's SQLite is copied with `.backup` by
`backup-vaultwarden` at 23:00, before restic runs; the module refuses a
`backupDir` that merely starts with `/var/lib/vaultwarden`.

**`offsite` exists only once `hosts/storagebox.json` and its key do**, so
the host builds before `wizards/backup.sh` has run. Each machine has its own
sub-account, chrooted into its own folder, so a compromised homelab can't
delete legion's backups; the box's own snapshots cover deletion from inside a
sub-account. Every repo shares one restic password, the one on the printed
emergency sheet. A failed backup unit triggers `notify-telegram@`.

**statusbot is ours, in Go, in `hosts/homelab/statusbot/`.** It answers
only `TELEGRAM_CHAT_ID`, on the bot token Gatus already sends with (sending
and long polling don't conflict). It runs as root: it reads the restic
password, restarts units and reads every journal. That is why its surface is
fixed: `/restart` and `/logs` take only names from the allowlist in
`/etc/statusbot.json`, and there is no shell, deploy or reboot. The 3-2-1 report
counts a repo as a copy only if its newest snapshot is under 36 h old; legion's
repo is behind a sub-account homelab can't open, so legion reports success by
writing a timestamp into `/var/lib/statusbot-inbox` over ssh. The drift line
compares the running nixpkgs with `flake.lock` on GitHub main, so it is only
as fresh as the last push. `statusbot print` writes the digest to stdout.

**The host key was generated before install** and is kept encrypted in
`secrets/homelab/host-key.age`. A reinstall decrypts it into the
nixos-anywhere `--extra-files` tree, so the secrets keep decrypting.

### media

**Jellyfin uses VAAPI, not QSV**, with `LIBVA_DRIVER_NAME=iHD`: on the
UHD 630 VAAPI through `intel-media-driver` needs nothing else. No tone
mapping (it wants OpenCL, which this GPU only gets from the legacy compute
runtime) and no low-power encoding (it needs GuC/HuC firmware loading).

**`media` has a fixed gid, 2000, in the common module.** NFS with `sec=sys`
compares raw ids, so `lux` and the group must be the same numbers on both
hosts. Directories under `/srv/media` are setgid `media`, and qBittorrent
runs with `media` as its primary group and umask 0002, so `lux` can move
and delete what it downloads.

**qBittorrent `RequiresMountsFor = /srv/media`.** With the HDD missing it
would otherwise fill the empty mountpoint on the NVMe.

**qBittorrent has `LocalHostAuth = false`** and listens on 127.0.0.1 only:
the one way in is Caddy, which does `basic_auth`. `serverConfig` is copied
over `qBittorrent.conf` on every start, so changes made in the UI to those
keys don't survive a restart.

**No port forward for torrents.** The router forwards only the WireGuard
and game ports; qBittorrent works passively.

**Jackett has no admin password and `AllowExternal = false`**, set in
`preStart` because Jackett writes `ServerConfig.json` itself. Caddy's
`basic_auth` covers everything but `/api/*`: Torznab clients (Lampa,
qBittorrent's search) can't do basic auth and use the API key instead.

**FlareSolverr exists for RuTracker.** `login.php` sits behind a Cloudflare
challenge that Jackett can't pass alone; search pages don't.

**Indexers are configured by `jackett-indexers` through Jackett's API.**
Jackett encrypts stored credentials with its own DataProtection keys, so
the indexer JSON can't be templated. The timer runs hourly, skips indexers
that already have a file in `Indexers/`, and so retries RuTracker through
its maintenance windows. To change the RuTracker login: delete
`Indexers/rutracker.json` and start the service.

**TorrServer is on 8091** (8090 is Beszel) and listens on every interface:
Lampa on the TV talks to `192.168.1.10:8091` directly.

**Syncthing keys are in agenix** so both device IDs can be written into the
config. Global discovery and relays are off: the laptop dials
`192.168.1.10`, which works at home and through `home`. `Documents` lives
under `/var/lib` (NVMe, btrbk, restic), `Downloads` on the HDD. Ignore
patterns are set on the laptop, the side that has the build directories.

### pumpkin

**Pumpkin comes from the upstream flake**, run by the nixpkgs module: the
nixpkgs package lags, and the client version has to match the server's.
The input is `git+https` with `submodules=1` because the flake sets
`self.submodules`, which the `github:` scheme rejects.

**It runs in a container with its own network.** On the host's network a
compromised game server could reach everything bound to 127.0.0.1 —
qBittorrent and Jackett have no auth there. The port reaches it through
`networking.nat.forwardPorts`; LAN players come in on `eno1` the same way.

**Offline mode with a whitelist.** Online mode needs every player to own a
Mojang account. The whitelist holds `lux`'s offline UUID (UUID v3 of
`OfflinePlayer:lux`); `whitelist.json` is only written when absent, so
later changes go through the game. Nobody is op. Offline mode trusts
whatever name the client sends, so the whitelist only keeps out strangers
who don't know a player's name.

**No RCON.** Upstream dropped it for the management protocol (MSMP), which
stays off.

**Port 41565, not 25565**, keeps the scanners that sweep 25565 away.
Players use `mc.rakhmatullin.dev`: an SRV record points it at
`wg.rakhmatullin.dev:41565`, and AdGuard rewrites `wg` to `192.168.1.10`
for the LAN, so the same name works at home without NAT loopback on the
router. The rewrite also lets the phone's `home` tunnel connect on home
Wi-Fi.

**World backups come for free**: the container's state is under
`/var/lib/nixos-containers`, inside `@var-lib`, which btrbk snapshots
hourly and restic copies nightly.

### apps

**Vaultwarden signups are open, but only for `tutamail.com` addresses.**
There is no admin page (no `ADMIN_TOKEN`), so nobody could invite; the
service is reachable only from the LAN and the tunnel.

**Immich keeps photos on the HDD** (`/srv/photos`) and its database on the
NVMe. Immich dumps the database into `backups/` under the media location
every night, so the `photos` restic repository covers both. Thumbnails and
transcoded video are excluded: Immich regenerates them.

**The `photos` repository is on the NVMe** — the other disk from the
photos — and has no prune: photos only accumulate. After every run it is
made readable for group `users`, and the laptop's weekly `photos-backup`
rsyncs it to `~/Backups/photos` as a third copy. rsync runs without
`--delete`, so a wiped repository on the server doesn't wipe the copy.

**OpenCloud uses the posix driver on `/srv/cloud`**, so the files are plain
files on disk that other tools (the `disc` burner) can read. The path
templates use the user name and the space name instead of UUIDs; they had
to be set before the first start, since existing spaces keep their paths.
`STORAGE_USERS_POSIX_WATCH_FS` picks up files changed behind OpenCloud's
back through `inotifywait`, hence `inotify-tools` on the unit's `PATH`.

**OpenCloud runs with `PROXY_TLS=false` and `OC_INSECURE=true`.** Caddy
terminates TLS; inside, OpenCloud's services talk to each other over
self-signed TLS (the IDP to the LDAP of IDM), which needs the insecure flag.
The admin password is generated by `opencloud init` on first start and
lives in `/etc/opencloud/opencloud.yaml`.

**Obsidian syncs through CouchDB, Super Productivity through WebDAV.**
Obsidian is the notes, Super Productivity the tasks. LiveSync replicates
per change, so two devices editing the same vault merge instead of producing
conflict copies; a file-level sync (Syncthing, WebDAV) can't do that. A
Super Productivity sync is one JSON file, which plain WebDAV handles. Neither
vault nor task file sits under `~/Documents`, which Syncthing already syncs.

**CouchDB's admin password comes from an agenix ini** in `extraConfigFiles`,
not `adminPass`, which would land in the store. CouchDB hashes it into the
writable `local.ini` on first start. `require_valid_user_except_for_up`
keeps every request behind the password except `/_up`, which Gatus polls.
The `[cors]` origins are the Obsidian desktop and mobile app schemes.
`wizards/sync.sh` creates both secrets and walks through the app setup.

### disc

**`disc` is a script in `hosts/homelab/disc.sh`**, not inline nix: it is
long and shellcheck-checked by `writeShellApplication`. udev starts
`disc@sr0` on a media change; `disc auto` rips a full disc (audio CD → abcde
FLAC into `music/`, video DVD → dvdbackup + HandBrake x265 into `movies/`,
anything else → copied to `discs/`) and burns a blank one. Everything goes
to Telegram.

**Burning reads from the OpenCloud space "Burn"**
(`/srv/cloud/projects/burn/{data,audio,video}`): drop files in one folder,
insert a blank disc. With several folders filled, or a rewritable that
isn't blank, it waits for `sudo disc burn <mode>` — erasing a disc is never
automatic. Burned files move to `done/`.

**HandBrake encodes x265 in software.** The GPU's HEVC encoder makes
bigger files of worse quality; a rip is kept for years and nobody waits
for it.

**Video DVDs are authored as PAL** — the region the discs get played in.

**udev uses `RUN+="systemctl --no-block start"`**, not `SYSTEMD_WANTS`:
the `sr0` device unit exists all the time, and wants are not re-applied on
the `change` event a disc insertion produces.

---

## hosts/legion/home.nix

### shell

**`defaultKeymap = "emacs"`.** zsh switches to vi bindings whenever
`$EDITOR`/`$VISUAL` contains `vi`, and `nvim` does.

**No `extended_glob`.** It makes `#` a glob operator and breaks unquoted
flake refs like `/etc/nixos#legion`.

**`stty -ixon`** disables XON/XOFF, so a stray Ctrl+S doesn't freeze the
terminal. **The Ctrl+Left/Right `bindkey`s** exist because the emacs keymap
only binds Alt+B/F, and foot and zellij send the CSI sequences.

**`historyWidget.command = ""`** gives fzf's Ctrl-R to Atuin.

**zoxide has no shell integration.** It is only there for yazi's `Z`.

**`completionInit` caches the compinit dump.** fpath spans several profile
generations, and `compaudit` over all of them is most of zsh's startup. The
full audit runs once a day.

**`initContent` carries `lib.mkOrder 950`** — see [Merge order](#merge-order).

### zellij

**`config.kdl` is a raw dotfile**, but only the file is symlinked: noctalia's
`zellij` template writes `themes/noctalia.kdl` next to it, and that must not
land in the repo.

**Unlock-first, by hand.** `default_mode "locked"` and `clear-defaults=true`:
locked mode owns only Ctrl+g, so no Ctrl key is taken from the shell or nvim.
The everyday actions sit in `shared` on Alt so they work in every mode.

**`on_force_close "quit"`.** Closing a foot window ends its session instead of
detaching, so nothing runs in the background; serialization keeps it
resurrectable from the session manager. `zellij-prune` deletes exited `s-*`
sessions at login; a renamed session survives because only the prefix is
matched.

### desktop

**The whole `umbriel` directory is symlinked**, because `config.toml`
includes `noctalia.toml`, written by noctalia's template. Edits hot-reload.

**Workspaces are named "1" "2" "3"**, pinned to DP-2. The names are what the
bar shows.

**`blur_optimized = true`** on the noctalia layer rule. Unoptimized blur
re-blurs everything under the bar each frame: 5 s of workspace flipping cost
~3.5 s CPU against ~2.0 s, and animations stuttered.

**foot's `shell` is `zellij-scratch`**, a fresh `s-N` session per window.
Older and per-project sessions come from `Alt+p` (`zellij-pick`).

**foot's `include` points at noctalia's matugen output** and overrides only
the palette keys. `home.activation.seedFootTheme` seeds a fallback so the
include always resolves, and leaves the file alone once noctalia writes it.

**lazygit opens from `Alt+g` and `<leader>gg`.** `os.editPreset =
"nvim-remote"` makes `e` inside nvim's float open the file in that nvim.

**Mod+F1 is `dotfiles/keyhints/`.** umbriel and zellij binds are parsed
from their configs and skills from each `SKILL.md`, so those never go stale;
apps whose binds are defaults (nvim, yazi, lazygit, the shell, Claude Code)
are hand-written `<app>.toml`. A curated entry with the same keys overrides a
parsed one, which is how stars and better descriptions reach parsed binds.
Every row starts with `★` or `·` so fzf's `--nth=2..` always lands on the app
name.

**`selection-clipboard = "clipboard"`** in zathura, so Ctrl+C copies.

### theme

**Theme bases, not colors.** noctalia's templates write the colors; home.nix
only picks adw-gtk3-dark, Papirus-Dark, Bibata and qt*ct with Fusion.
`gtk4.theme = null` because a gtk4 theme makes home-manager own
`gtk-4.0/gtk.css`, which is noctalia's. The `qt*ct.conf` files only point at
the palette that noctalia rewrites on every wallpaper change. The cursor is
also set in umbriel and the greeter, which don't read `XCURSOR_THEME`.

### files

**`xdg.mimeApps` lists every common type.** Left to `mimeinfo.cache`,
folders and zips opened in zathura, images and PDFs in chromium, torrents in
mpv. `mimeapps.list` is `force`d, so "set as default" in an app doesn't
stick — add the type here.

**Torrents and magnets go to homelab, not the local qBittorrent.**
`torrent-add` pipes them over ssh to `curl` on homelab, against qBittorrent's
API on 127.0.0.1, where `LocalHostAuth = false` — so no password lives on the
laptop. The local qBittorrent stays installed for the odd one-off.

### editor

**The neovim config is a raw dotfile**, symlinked past the store. It is
LazyVim (ADR 0005); `lua/plugins/nix.lua` is where it meets Nix.

**Treesitter parsers and nvim-treesitter both come from nixpkgs**, so
queries and parsers stay on the same revision. `grammarPlugins`, not
`withPlugins`, which yields no `.so`. `:TSInstall` can't work: `site/parser`
is a store path. A new language is a line in `nvimGrammars`. nvim-treesitter
sits in `nvim/nix/`, not under `pack/`, because lazy.nvim loads it by `dir`
and resets the packpath anyway; `site/` is added to its rtp for the parsers.

**LSP servers, formatters and linters come from Nix, not Mason** — Mason's
binaries expect an FHS layout. The LazyVim lang extras name some of them
(marksman, markdownlint-cli2, gofumpt, golangci-lint, statix), so they are in
`home.packages` even though nothing else calls them.

**`goimports` is copied out of `gotools`** (254 MiB, forty-odd binaries);
`go` is already in `home.packages`.

### packages

**The YubiKey is `sufficient` for sudo only**, before `pam_unix`: a touch
skips the password, and without the key the password prompt follows as
before. It is not on login or the greeter, where a misconfigured PAM stack
locks you out of the desktop. `hosts/legion/u2f_keys` is the public half
that `pamu2fcfg` prints — a key handle and a public key, nothing secret —
and sudo only asks for it once that file exists. `origin`/`appid` are pinned
to `pam://legion` so the registration doesn't depend on the hostname.
`wizards/yubikey.sh` registers it, and the key on the websites that matter.

**`bitwarden-cli` and `super-productivity`** are there for the noctalia
plugins of the same names (`bw serve`, the REST API).

**`obsidian-plugins` is a command, not an activation step.** The plugins are
pinned by hash but *copied* into `<vault>/.obsidian/plugins/` on demand:
the vault is user data at a path the config doesn't know, LiveSync
replicates it, and Obsidian writes into `.obsidian/` at runtime, which
store symlinks would break. Upstream's flake fetches `releases/latest`, so a
plugin upgrade is a hash bump here.

**`home.packages` carries `lib.mkBefore`** — see [Merge order](#merge-order).

---

## Merge order

Three constructs pin the order in which the module system merges
contributions. They look removable; deleting any of them changes the built
system.

- **`home.packages = lib.mkBefore (...)`** — home-manager's program modules
  append their packages at the default order; without it the user's
  packages land after them and PATH precedence flips on collisions.
- **`programs.zsh.initContent = lib.mkOrder 950`** — keeps these setopts
  after the zsh module's own (900) and before the starship/atuin/yazi/fzf
  integrations (910–1000).
- **The blank line in `boot.extraModprobeConfig`** reproduces the newline
  `types.lines` used to put between two contributions.

The order of `environment.systemPackages` is also deliberate: it reproduces
the old merge order.
