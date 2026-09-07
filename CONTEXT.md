# nixos-btw

Configuration for a single machine — a Lenovo Legion laptop running NixOS. The repository covers the system, the user environment, and the raw program configs that nix deliberately does not manage.

The nix code carries no comments; the reasons behind individual settings live in `docs/rationale.md`.

## Language

### Configuration structure

**Host**:
A physical machine a system is built for. There is currently one, `nixos`.
_Avoid_: machine, target

**Specialisation**:
An alternative boot entry for the same host with a different set of options. Chosen in the bootloader, not at runtime.
_Avoid_: profile, mode, preset

**System configuration**:
The OS-level half — whatever exists before a user logs in and does not belong to any user. It is one file, `configuration.nix`; the sections inside it are navigation, not boundaries.
_Avoid_: system module, config, nix file

**Home configuration**:
The user half, expressed through home-manager. Everything a person uses rather than the system. It is one file, `home.nix`. It stays separate from the system half because the two share option names that mean different things — `programs.zsh` exists in both.
_Avoid_: home module, user module, hm config

**Dotfile**:
A raw program config in its own language — kdl, lua, toml — kept outside nix and editable without a rebuild.
_Avoid_: resource, asset

**Secret**:
A file holding a private key or credentials, stored in the repository only in encrypted form.
_Avoid_: creds, password

### Network

The word "VPN" is not used in this project: it names three incompatible things at once. The three terms below replace it.

**Tunnel**:
A named WireGuard interface providing access to one private network. It carries only its own subnets and never claims the default route.
_Avoid_: VPN, wg config

**Proxy**:
A client whose job is to move traffic past network restrictions imposed by an ISP.
_Avoid_: VPN, proxy-VPN

**Overlay**:
A mesh network joining separate devices into one addressable segment regardless of where they physically sit.
_Avoid_: VPN, mesh VPN

**Default route**:
The path taken by traffic that matched no specific subnet. Exactly one exists at any moment — the proxy and the tunnels compete for it.
_Avoid_: default gateway, default gw
