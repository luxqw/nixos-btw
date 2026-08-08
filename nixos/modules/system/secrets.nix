# Secrets are decrypted with the user's ssh key rather than a host key:
# services.openssh is disabled, and the machine has no host keys at all.
#
# Consequence: this key is part of the system, not personal. Reissue it for
# GitHub and the tunnels silently stop coming up. See docs/adr/0001.
_: {
  age.identityPaths = ["/home/lux/.ssh/id_ed25519"];
}
