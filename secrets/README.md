# Secrets

`wg/` holds the laptop's tunnel configs. `homelab/` holds the server's
secrets, encrypted to both `lux` and homelab's host key — `secrets.nix`
derives the rules for both directories from their contents.

## Tunnels

Tunnel configs, encrypted with age. The filename is the interface and the
unit name: `wg/fleet.age` → `fleet` → `wg-quick-fleet.service`. The list of
tunnels is derived from `wg/`.

### `tunnel`

```bash
tunnel list                 # what exists and what is up
tunnel up|down|restart fleet
tunnel add work ~/work.conf # encrypt a new config
tunnel edit fleet           # $EDITOR on the decrypted config
tunnel show fleet           # print it
tunnel rm fleet
```

`add`, `edit` and `rm` need a rebuild; `edit` also needs a restart. The
command prints the follow-up.

### By hand

Run from `/etc/nixos/secrets` — agenix reads `secrets.nix` from the current
directory and the rule name is `wg/<name>.age`.

```bash
age -R ~/.ssh/id_ed25519.pub -o wg/<name>.age <config>.conf  # new
agenix -e wg/<name>.age                                     # edit
agenix -d wg/<name>.age                                     # read
```

A new secret goes through `age`: it has no rule until the file exists, so
`agenix -e` fails with `attribute '"wg/<name>.age"' missing`. Names are at
most 15 characters (the interface name limit).

After an edit, restart the unit: `/run/agenix/<name>` keeps its path, so
systemd sees nothing to restart.

## homelab

```bash
H="$(grep root@homelab secrets.nix | cut -d'"' -f2)"
age -R ~/.ssh/id_ed25519.pub -r "$H" -o homelab/<name>.age <file>  # new
agenix -e homelab/<name>.age                                       # edit
```

`wg-phone.age` is the phone's tunnel config, `qrencode -t ansiutf8` turns it
into a QR code. `host-key.age` is homelab's ssh host key, for reinstalls.

## Rotating the key

Update the public key in `secrets.nix`, then `agenix -r -i <old key>`. Until
then the tunnels don't come up, and only `journalctl -u wg-quick-<name>`
says so. See `docs/adr/0001`.

Decrypted `.conf` files are gitignored, but don't leave them on disk.
