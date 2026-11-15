# Dispatcher stage 2 on homelab: the read-only Telegram reader daemon (dispatcher docs/patches/telegram-reader.md).
# It owns the MTProto sessions of the owner's own accounts (one login each, by hand) and answers the dispatcher gateway
# over a unix socket; it reads only. Remove the import in configuration.nix and this file to go back; the sessions stay
# in /var/lib/dispatcher-telegram either way.
{
  config,
  inputs,
  ...
}: {
  imports = [inputs.dispatcher.nixosModules.telegram];

  # api_id and api_hash from my.telegram.org. Owned by the daemon user so the one-time `dispatcher-telegram-login` can
  # read it too; the service itself gets it through systemd LoadCredential.
  age.secrets.dispatcher-telegram-api = {
    file = ../../secrets/homelab/dispatcher-telegram-api.age;
    owner = "dispatcher-telegram";
    mode = "0400";
  };

  services.dispatcher-telegram = {
    enable = true;
    accounts = ["damir" "work"];
    # Chats that are never read (numeric ids; the service chat 777000 is always excluded by the program).
    excludeChats = [];
    apiCredentialsFile = config.age.secrets.dispatcher-telegram-api.path;
  };

  # The gateway's telegram_* tools: its `dispatcher` user joins the daemon's group (connect to the socket, nothing else).
  services.dispatcher-gateway.telegram.enable = true;
}
