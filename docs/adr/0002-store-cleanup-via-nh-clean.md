# Store cleanup is done by `nh clean`, not `nix.gc`

`nix.gc` used to run weekly with `--delete-older-than 14d`. That rule is purely age-based: a burst of rebuilds in one week keeps every one of them for two weeks, and a quiet month deletes everything but the current generation. With 14 system generations sitting on a `/` that was 87% full, the store had grown to 37G.

`programs.nh.clean` now runs `nh clean all --keep 5 --keep-since 7d` weekly. It keeps at least the last five generations *and* anything younger than a week, so there is always something to roll back to, while the count stays bounded. `nh clean all` also cleans per-user profiles (home-manager), which `nix.gc` alone does not prune.

`programs.nh.enable` also takes over installing `nh` and setting `NH_FLAKE` (through `programs.nh.flake`). A side effect: `NH_FLAKE` used to sit in `environment.sessionVariables`, which the `on-the-go` specialisation replaces wholesale with `lib.mkForce`, so `nh` had no default flake there. It is now in `environment.variables` and reaches both.

## Considered Options

- **Keep `nix.gc`, tune `--delete-older-than`** — still age-only; no floor on how many generations survive.
- **Both** — nixpkgs warns against running them together; they race over the same profiles.

## Consequences

`nh clean` also removes stray gcroots (a `result` symlink from a manual `nix build`) once they are older than `--keep-since`, which `nix.gc` never did. A `result` link worth keeping has to be moved out of the way or rebuilt.
