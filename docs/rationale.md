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

**v2raya and throne** solve the same problem and both want the default
route; throne's tun mode fights v2raya.

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

---

## hosts/legion/home.nix

### shell

**`defaultKeymap = "emacs"`.** zsh switches to vi bindings whenever
`$EDITOR`/`$VISUAL` contains `vi`, and `nvim` does.

**No `extended_glob`.** It makes `#` a glob operator and breaks unquoted
flake refs like `/etc/nixos#legion`.

**`stty -ixon`** disables XON/XOFF, so a stray Ctrl+S doesn't freeze the
terminal. **The Ctrl+Left/Right `bindkey`s** exist because the emacs keymap
only binds Alt+B/F, and foot and tmux send the CSI sequences.

**`historyWidget.command = ""`** gives fzf's Ctrl-R to Atuin.

**zoxide has no shell integration.** It is only there for yazi's `Z`.

**`completionInit` caches the compinit dump.** fpath spans several profile
generations, and `compaudit` over all of them is most of zsh's startup. The
full audit runs once a day.

**`initContent` carries `lib.mkOrder 950`** — see [Merge order](#merge-order).

### tmux

**Colors come from noctalia's `tmux` template**, which writes
`themes/noctalia.conf`. The `source-file` line must stay last and verbatim,
or the template's `apply.sh` tries to rewrite the read-only `tmux.conf`.
`status-left`/`status-right` sit in continuum's block because continuum
appends its autosave hook to `status-right` when it loads.

**`extended-keys always`.** nvim negotiates the kitty keyboard protocol with
foot; without this, root-table Alt binds stop matching once nvim has touched
the pane.

**The `pane-mode-changed` hook** flashes a message on entering copy mode:
with `mouse` on and vi keys, any scroll drops into copy-mode-vi, which
rebinds the whole keytable.

**`unbind-key -a -T root` wipes the default mouse binds too**, so the three
`Mouse*` entry points are re-added. copy-mode-vi's own drag binds are
untouched.

**`M-S-<` rather than `M-<`.** With extended keys foot reports Alt+Shift+<
as CSI 27;4;60~, which tmux names `M-S-<`.

### desktop

**The whole `umbriel` directory is symlinked**, because `config.toml`
includes `noctalia.toml`, written by noctalia's template. Edits hot-reload.

**Workspaces are named "1" "2" "3"**, pinned to DP-2. The names are what the
bar shows and what foot's tmux sessions are called.

**`blur_optimized = true`** on the noctalia layer rule. Unoptimized blur
re-blurs everything under the bar each frame: 5 s of workspace flipping cost
~3.5 s CPU against ~2.0 s, and animations stuttered.

**foot's `shell` attaches to one tmux session per umbriel workspace** (`main`
outside umbriel) instead of piling up numbered sessions that continuum
restores. The jq filter uses `.ok?`, not `.ok`: the reply is a bare array,
and `.ok` on an array errors in a way `//` doesn't catch. Per-project
sessions come from the sessionizer on `prefix f`.

**foot's `include` points at noctalia's matugen output** and overrides only
the palette keys. `home.activation.seedFootTheme` seeds a fallback so the
include always resolves, and leaves the file alone once noctalia writes it.

**lazygit opens from `prefix g` and `<leader>gg`.** `os.editPreset =
"nvim-remote"` makes `e` inside nvim's float open the file in that nvim.

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

### editor

**The neovim config is a raw dotfile**, symlinked past the store.

**Treesitter parsers and nvim-treesitter both come from nixpkgs**, so
queries and parsers stay on the same revision. `grammarPlugins`, not
`withPlugins`, which yields no `.so`. `:TSInstall` can't work: `site/parser`
is a store path. A new language is a line in `nvimGrammars`.

**LSP servers and formatters come from Nix, not Mason** — Mason's binaries
expect an FHS layout.

**`goimports` is copied out of `gotools`** (254 MiB, forty-odd binaries);
`go` is already in `home.packages`.

### packages

**`bitwarden-cli` and `super-productivity`** are there for the noctalia
plugins of the same names (`bw serve`, the REST API).

**`python3` with numpy/onnxruntime/pillow** is for noctalia's
`wallpaper_depth`, which can't use its own venv on NixOS.

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
