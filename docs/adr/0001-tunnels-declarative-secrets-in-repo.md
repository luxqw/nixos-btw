# Tunnels are declarative and their configs live encrypted in the repository

Tunnels used to be brought up by hand: `/etc/wireguard` was a symlink into the repository, inside it sat another symlink `wg0.conf`, and `wg-quick` was granted passwordless sudo. The hardcoded `wg0` name meant exactly one tunnel could run at a time. Each tunnel is now an entry in `networking.wg-quick.interfaces` started at boot, and its config is an agenix secret that lives encrypted under `secrets/` and is decrypted into `/run/agenix` during system activation.

Being declarative does not cost manual control. Every tunnel is an ordinary `wg-quick-<name>` systemd unit that can be stopped and started at any point; a polkit rule permits `start`/`stop`/`restart` on those units without a password. Running both tunnels at once is made possible not by autostart but by their distinct interfaces and non-overlapping `AllowedIPs` — neither claims the default route.

The list of tunnels is written down nowhere. It is derived from the contents of `secrets/wg/` via `builtins.readDir`, and a filename doubles as the interface name and the unit name. This only became possible because of the choice of agenix: while the configs sat outside git the flake could not see them, and the names would have had to be duplicated in nix by hand. Adding a tunnel comes down to a single step — drop in a new `.age` and rebuild.

## Considered Options

Three ways of storing the configs were weighed, and this is the one part of the decision that changed during the discussion:

- **Files outside git** (`wireguard/` in `.gitignore`, an absolute string path in `configFile`) — the status quo, and the original plan. Rejected: the repository stops being deployable from scratch, and on a fresh machine the tunnels silently fail to come up.
- **A private repository** — rejected: privacy is not encryption, and the private keys would still sit in history as plaintext.
- **agenix** — chosen. Encrypted `.age` files can be kept in a public repository.

Just as important as `configFile` is that the path must lie **outside** `/nix/store`: the store is world-readable, and a WireGuard private key in it would be compromised. `config.age.secrets.<name>.path` satisfies that.

## Consequences

Decryption is tied to the `~/.ssh/id_ed25519` of user `lux` rather than a host key, because `services.openssh` is disabled and the machine has no host keys at all. Two non-obvious consequences follow:

- Reissuing that ssh key — for GitHub, say — stops the tunnels from coming up on the next boot, silently, because `nixos-rebuild` still succeeds. The key has to be treated as part of the system rather than as personal.
- System-level secrets depend on a file in `/home`. A dedicated key under `/root` would remove that dependency but would cost a manual step at install time and a separate backup.

A missing or wrong secret fails the `wg-quick-<name>` unit but not the build: the mismatch shows up only in the logs.
