# One flake, several hosts

The repository described one machine, named `nixos`, in a flat `configuration.nix` and `home.nix`. A home server is joining it. Each host now lives in `hosts/<name>/`, and what every host shares — nix settings, locale, the `lux` user, zram, `nh clean` — is in `modules/common.nix`. `flake.nix` builds a host from its directory, the common module and agenix; the laptop adds home-manager on top. The laptop is renamed `legion`, the server is `homelab`.

The split was checked by building the laptop before and after the move: the derivation was identical.

## Considered Options

- **A separate repository for the server** — rejected: the shared module, the secrets and the tunnel to the server would have to be duplicated or published as a flake input.
- **One host per branch** — rejected: a change to the common part has to be merged in two places.

## Consequences

- The first switch after the rename needs the host spelled out (`nh os switch -H legion`); after that the hostname matches the attribute again.
- `homelab` is not rebuilt on itself. It is deployed from the laptop with `nixos-rebuild --flake .#homelab --target-host --build-host`, so the repository only exists on the laptop.
- Unlike the laptop (ADR 0001), `homelab` runs openssh, so its secrets are encrypted to its host key. A secret either host needs lists both keys in `secrets.nix`.
