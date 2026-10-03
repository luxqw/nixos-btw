# Rationale

Why the settings are what they are. The configuration itself carries no
comments; the reasons live here, in sections named after the sections of
`configuration.nix` and `home.nix`.

None of this describes what the code does — read the code for that. It
records what you cannot recover by reading it: the bug being worked
around, the option that looks redundant but is not, the thing that was
tried and failed.

---

## configuration.nix

### boot

**`options nvidia_modeset vblank_sem_control=0`** works around a
nvidia bug first seen under niri: flicker and a black screen on resume.
<https://github.com/niri-wm/niri/issues/3384>

**`nvidia`, `nvidia_modeset` and `nvidia_drm` in `boot.kernelModules`**
are declared by hand. nixpkgs' `nvidia.nix` only force-loads them early
via `systemd-modules-load` when `services.xserver.enable` is on. Xorg
doesn't run here — umbriel is Wayland-only — so without these three, early
KMS races with greetd/compositor startup at boot.

**The blank line inside `boot.extraModprobeConfig`** is load-bearing for
byte-identical output only; see [Merge order](#merge-order).

### hardware

**`services.logind.settings.Login.HandlePowerKey = "ignore"`** — logind's
own handling suspends directly, bypassing noctalia and its
`lockOnSuspend = true` entirely. noctalia handles the power key with its
lock-and-suspend instead, so logind is told to stay out of it.

**The `lenovoctl` group and the tmpfiles rule** let that group toggle
Lenovo IdeaPad/Legion ACPI features (currently battery
`conservation_mode`) without root, for the `lux/lenovo-legion` noctalia
plugin.

The tmpfiles `z` rule is not a stylistic choice. udev's `GROUP=`/`MODE=`
rule keys apply only to the `/dev` device node, not to arbitrary sysfs
`ATTR` files (see `udev(7)`) — a `services.udev.extraRules` rule matching
`ATTR{conservation_mode}` is a **silent no-op** here. The tmpfiles rule
runs after udev has settled at boot, and its glob covers the ACPI
instance name (e.g. `VPC2004:00`) without hardcoding it.

### graphics

**`NIXOS_OZONE_WL = "1"`** looks redundant next to
`ELECTRON_OZONE_PLATFORM_HINT`, and is not.
`ELECTRON_OZONE_PLATFORM_HINT` only reaches Electron apps; the nixpkgs
chromium wrapper gates `--ozone-platform-hint` on `NIXOS_OZONE_WL`
instead. Without it chromium runs under XWayland, where the portal
screencast path is unreachable and screen sharing never starts.

### network

**v2raya and throne** solve the same problem and both want the default
route. Enabling throne's tun mode will fight v2raya. Only v2raya is
actually in use right now.

**The tunnel list is written down nowhere.** It is derived from the
contents of `secrets/wg/`, where a filename serves as both the interface
name and the unit name. Adding a tunnel means dropping a new `.age` in
there and rebuilding. See ADR 0001.

**The polkit rule** exists because tunnels start at boot but stopping and
starting them by hand should need no password. The grant is deliberately
narrow: only those units, only `start`/`stop`/`restart`, only for `lux`.

### secrets

**Secrets are decrypted with the user's ssh key, not a host key.**
`services.openssh` is disabled and the machine has no host keys at all.

The consequence is easy to trip over: that key is part of the system, not
personal. Reissue it for GitHub and the tunnels silently stop coming up.
See ADR 0001.

**The `tunnel` command** wraps agenix/age because the bare commands
require holding three unrelated facts at once: run from
`/etc/nixos/secrets`, spell the name `wg/<name>.age`, and reach for `age`
rather than `agenix` when the secret does not exist yet. All three are
baked into the wrapper.

**`pkgs.age` is installed alongside agenix** because `agenix -e` only
edits secrets that already exist; creating a new one needs `age` itself.

### desktop

**noctalia's shell and its greeter** were previously split across two
modules despite being one program.

### apps

**Wireshark needs `programs.wireshark`, not a line in the package list.**
Capturing as a non-root user takes a `dumpcap` wrapper holding
`cap_net_raw` and `cap_net_admin`, executable only by the `wireshark`
group. Both the wrapper and the group come from the module; the `system`
section puts `lux` in that group.

The default package is `wireshark-cli`, which ships no GUI at all. The
full package is named plainly `wireshark` and carries the Qt interface
alongside the same `tshark` and `dumpcap`.

**jellyfin runs as `lux`**, not its own `jellyfin` user, so it can read
the media in the home directory (downloads) without loosening permissions
on it.

**`neovim-unwrapped` in the system packages** is a deliberate exception
to "only system things in the system": root needs an editor to fix
configs by hand when home-manager is unavailable. The user's neovim and
its config live in `home.nix`.

**What belongs in `environment.systemPackages`** is only what services,
hardware or login cannot work without. Everything user-facing lives in
`home.nix`. The current entries are there for:

| package             | why                                          |
| ------------------- | -------------------------------------------- |
| `ntfs3g`            | mounting the games partition                  |
| `polkit_gnome`      | authorisation agent for the graphical session |
| `wireguard-tools`   | `wg show`, for inspecting tunnels             |

(In the pre-collapse tree the "mounting the games partition" comment sat
on the `nixd` line rather than `ntfs3g`; it describes `ntfs3g`.)

---

## home.nix

### shell

**`defaultKeymap = "emacs"`** is pinned because zsh picks vi keybindings
on its own whenever `$EDITOR` or `$VISUAL` contains the substring `vi` —
`nvim` does, so the prompt silently came up in vi mode. Pinning the
keymap beats renaming the editor.

**`historyWidget.command = ""`** in fzf gives up Ctrl-R: it is owned by
Atuin. fzf keeps Ctrl-T and Alt-C.

**zoxide is installed without shell integration** — no `z`/`zi` commands.
It exists for yazi's `Z` keybind, to jump to frecent directories while
browsing. Atuin's Ctrl-R covers shell history instead.

**`completionInit` caches the compinit dump.** NixOS' fpath spans
multiple profile generations (thousands of completion files), and
compinit's full security audit (`compaudit`) rescanning all of them on
every start is most of zsh's startup time. The full audit runs once a
day; otherwise the cached dump is fast-loaded.

**`initContent` carries `lib.mkOrder 950`** — see
[Merge order](#merge-order).

### desktop

**The whole `umbriel` directory is symlinked, not just `config.toml`.**
The config includes `noctalia.toml`, written by noctalia's umbriel
template, so the second file has to sit beside it. Edits hot-reload.

**umbriel workspaces are named "1" "2" "3"**, pinned to DP-2. The names
are what noctalia's bar shows and what foot's tmux sessions are called;
letters (carried over from niri) showed up as `c b a 4`.

**`blur_optimized = true`** on the noctalia layer rule. Unoptimized blur
re-blurs everything under the bar every frame: flipping workspaces for
5 s cost the compositor ~3.5 s CPU vs ~2.0 s optimized (1.65 s with no
blur at all), and animations stuttered.

**Theme bases, not colors.** noctalia's templates write the colors
(`gtk-3.0`/`gtk-4.0` `noctalia.css`, `qt*ct/colors/noctalia.conf`,
`kdeglobals`); home.nix only picks what they sit on: adw-gtk3-dark,
Papirus-Dark, the Bibata-Modern-Classic cursor and qt*ct with Fusion.
`gtk.gtk4.theme = null` because a gtk4 theme makes home-manager own
`gtk-4.0/gtk.css`, which is noctalia's file. The cursor is also set in
umbriel's `[input.cursor]` and the greeter, which don't read
`XCURSOR_THEME`.

**`xdg.mimeApps` lists every common type explicitly.** Left to
`mimeinfo.cache`, folders and zips opened in zathura's comic reader,
images and PDFs in chromium and torrents in mpv. `mimeapps.list` used to
be hand-edited, so it is `force`d; "set as default" in an app no longer
sticks, add the type in home.nix instead.

**foot's `include` points at noctalia's matugen output.** It re-opens
`[colors-dark]` and overrides `foreground`/`background`/`regular*`/
`bright*` only — `alpha` and `dim*` are not part of the matugen palette
and are left untouched.

**`home.activation.seedFootTheme`** seeds a fallback theme so that
`include` always resolves to a real file. noctalia's matugen template
writes live colors to the same path; once it has, the activation leaves
the file alone, so rebuilds never clobber the live theme.

**tmux colors come from noctalia's community `tmux` template**, not a
theme plugin (tokyo-night-tmux hardcoded its palette). The template
writes `~/.config/tmux/themes/noctalia.conf`, which `tmux.conf` sources
on its last line. That line must stay last and verbatim: the template's
`apply.sh` rewrites `tmux.conf` otherwise, and it is a read-only store
file. `status-left`/`status-right` are set in continuum's plugin block
because continuum appends its autosave hook to `status-right` on load.

**foot's `shell` attaches to one tmux session per umbriel workspace**,
named after the focused workspace (`main` outside umbriel), instead of
spawning a new numbered one; with continuum
restoring sessions at server start, numbered sessions used to pile up
into the dozens. Per-project sessions come from the sessionizer on
`prefix f` (fzf over `~/Documents/projects`), named after the directory.

**lazygit opens from two places**: `prefix g` in tmux (a popup in the
pane's directory, for when no editor is open) and `<leader>gg` in nvim.
`os.editPreset = "nvim-remote"` makes `e` inside the nvim float open the
file in that nvim rather than a nested one.

**`selection-clipboard = "clipboard"`** in zathura: it copies selections
to PRIMARY by default, so Ctrl+C/Ctrl+V don't see them and only
middle-click paste works.

### editor

**The neovim config stays a raw dotfile** — a symlink past the store — so
lua can be edited without rebuilding the system.

**Treesitter parsers come from nixpkgs.** They used to sit in the
repository as eight `.so` files built by hand against one specific ABI.
neovim finds them in `~/.local/share/nvim/site`, a path that is on the
runtimepath by default and does not collide with the config symlink.

**`grammarPlugins`, not `withPlugins`** — the latter yields a plugin with
no compiled `.so` at all in the current nixpkgs.

**nvim-treesitter itself comes from nixpkgs too**, into
`site/pack/nix/start`, rather than through `vim.pack` like every other
plugin. Its queries must match the parsers' revisions; a query written
for a newer grammar errors on an older parser. Taking both from the same
nixpkgs keeps them in lockstep. It also cannot install anything itself:
`site/parser` is a read-only store path, so `:TSInstall` fails. A new
language is a line in `nvimGrammars`.

**LSP servers and formatters come from Nix, not Mason.** Mason downloads
prebuilt binaries that are dynamically linked against an FHS layout NixOS
does not have.

**`goimports` is copied out of `gotools`**, not installed as `gotools`.
`gotools` is 254 MiB of forty-odd binaries; only `goimports` is used (by
conform, on save). The copy is the unwrapped binary: the wrapper exists
only to put `go` on PATH, and `go` is already in `home.packages`.

### packages

**`home.packages` carries `lib.mkBefore`** — see
[Merge order](#merge-order).

**`obsidian-plugins` is a command you run, not an activation step.** The
two Obsidian community plugins (Self-hosted LiveSync, TaskNotes) are
fetched declaratively with pinned hashes, but they are *copied* into
`<vault>/.obsidian/plugins/` rather than symlinked from the store, and
only when invoked. Three reasons, none reversible:

- A vault is user data at a path the configuration does not know, and
  LiveSync replicates it to other devices. Nothing here may own it.
- `.obsidian/` is written by Obsidian at runtime — `data.json`, the
  enabled-plugin list, plugin self-updates — and by LiveSync when hidden
  file sync is on. Read-only store symlinks make all of that fail.
- Upstream's own flake downloads `releases/latest` inside a `shellHook`,
  so the result depends on the day it ran. Pinning the three release
  assets per plugin by hash is what makes a rebuild reproducible; the
  cost is that a plugin upgrade is a hash bump here.

---

## Merge order

Three constructs exist purely to pin the order in which the nix module
system merges contributions. They look removable and are not: deleting
any of them changes the built system.

They date from the collapse of the old 50-file tree into two files. Back
then each option was defined in several modules and merged; now each is
defined once, and the merge order it used to get has to be stated
explicitly.

- **`home.packages = lib.mkBefore (...)`** — home-manager's own program
  modules each append their package at the default order. Without
  `mkBefore` the user's packages land *after* them, changing PATH
  precedence on any collision.

- **`programs.zsh.initContent = lib.mkOrder 950 ...`** — home-manager's
  zsh module emits its `setopt` block at order 900, and the
  starship/atuin/yazi/fzf integrations sit at 910–1000. 950 keeps these
  setopts after zsh's own and before the integrations, which is where
  they were.

- **The blank line in `boot.extraModprobeConfig`** — the v4l2loopback and
  nvidia options used to come from two modules, and `types.lines` joins
  contributions with a newline. The blank line reproduces that join.

A fourth is unmarked and worth knowing: **the order of
`environment.systemPackages` is not arbitrary.** It reproduces the old
merge order, which ran *opposite* to the order the `imports` lists were
written in.
