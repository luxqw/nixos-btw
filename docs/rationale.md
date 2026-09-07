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
niri+nvidia bug: flicker and a black screen on resume.
<https://github.com/niri-wm/niri/issues/3384>

**`nvidia`, `nvidia_modeset` and `nvidia_drm` in `boot.kernelModules`**
are declared by hand. nixpkgs' `nvidia.nix` only force-loads them early
via `systemd-modules-load` when `services.xserver.enable` is on. Xorg
doesn't run here — niri is Wayland-only — so without these three, early
KMS races with greetd/niri startup at boot.

**The blank line inside `boot.extraModprobeConfig`** is load-bearing for
byte-identical output only; see [Merge order](#merge-order).

### hardware

**`services.logind.settings.Login.HandlePowerKey = "ignore"`** — logind's
own handling suspends directly, bypassing noctalia and its
`lockOnSuspend = true` entirely. niri binds the power key to noctalia's
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
| `xwayland-satellite`| X11 applications under niri                   |

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

**The whole `niri` directory is symlinked, not just `config.kdl`.** The
config pulls in `include "/home/lux/.config/niri/noctalia.kdl"`, so the
second file has to sit beside it. This used to rest on a hand-made
symlink created outside home-manager.

**foot's `include` points at noctalia's matugen output.** It re-opens
`[colors-dark]` and overrides `foreground`/`background`/`regular*`/
`bright*` only — `alpha` and `dim*` are not part of the matugen palette
and are left untouched.

**`home.activation.seedFootTheme`** seeds a fallback theme so that
`include` always resolves to a real file. noctalia's matugen template
writes live colors to the same path; once it has, the activation leaves
the file alone, so rebuilds never clobber the live theme.

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

### packages

**`home.packages` carries `lib.mkBefore`** — see
[Merge order](#merge-order).

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
