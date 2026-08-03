# Secrets

Tunnel configs live here encrypted with age. A filename is both the interface
name and the unit name: `wg/fleet.age` → `fleet` → `wg-quick-fleet.service`.
The list of tunnels is written down nowhere; it is derived from the contents
of `wg/`.

## The short way: the `tunnel` command

Works from any directory and already knows about every pitfall listed below.

```bash
tunnel list                 # what exists and what is up
tunnel add work ~/work.conf # encrypt a new config
tunnel edit fleet           # open an existing one in $EDITOR
tunnel show fleet           # print the decrypted config
tunnel rm fleet             # remove a tunnel
```

`add`, `edit` and `rm` all need a rebuild afterwards, and `edit` also needs a
unit restart; the command prints the exact follow-up step.

The rest of this file is the same thing with bare `age`/`agenix`, should you
need it.

Every command below runs **from `/etc/nixos/secrets`**, not from `wg/`:
`agenix` looks for `secrets.nix` in the current directory, and the rule name
there is `wg/<name>.age`.

```bash
cd /etc/nixos/secrets
```

And never open a `.age` in a text editor — only through `agenix -e`, which
decrypts to a temporary file and encrypts it back.

## Add a new tunnel

`agenix -e` is no good here: the rules are derived from files that already
exist, so a new name has no attribute yet and the command fails with
`error: attribute '"wg/<name>.age"' missing`. The first encryption goes
through `age` directly.

```bash
age -R ~/.ssh/id_ed25519.pub -o wg/<name>.age /path/to/config.conf
sudo nixos-rebuild switch --flake /etc/nixos
```

The tunnel comes up on its own after the rebuild. From then on the file is
covered by the rules and can be edited with `agenix -e`.

Keep the name at 15 characters or fewer — that is the limit on network
interface names.

## Edit an existing one

```bash
agenix -e wg/fleet.age
sudo nixos-rebuild switch --flake /etc/nixos
systemctl restart wg-quick-fleet
```

The restart is not a formality. The secret's path — `/run/agenix/fleet` —
does not change when its contents do, so systemd sees no reason to restart
the unit by itself. The restart will not ask for a password: the polkit rule
in `nixos/modules/network/tunnels.nix` grants `lux` start/stop/restart on
these units.

## Inspect

```bash
agenix -d wg/fleet.age
```

## Remove a tunnel

```bash
git rm wg/<name>.age
sudo nixos-rebuild switch --flake /etc/nixos
```

The interface and the unit disappear on their own — the list is derived from
the directory, after all.

## Rotate the key

When `~/.ssh/id_ed25519` changes, update the public key in `secrets.nix`
first, then re-encrypt everything using the old key:

```bash
agenix -r -i /path/to/old/key
```

Do not put this off: the system decrypts secrets with exactly that key, and
without re-encryption the tunnels stop coming up on the next boot.
`nixos-rebuild` will still succeed — the error appears only in
`journalctl -u wg-quick-<name>`. See `docs/adr/0001`.

## What must never end up here

Decrypted `.conf` files are gitignored (`secrets/**/*.conf`), but it is safer
not to leave them on disk at all — edit through `agenix -e`, which keeps the
plaintext in a temporary file and cleans it up itself.
